data "aws_region" "current" {}
data "aws_partition" "current" {}

data "aws_subnet" "development" {
  id = var.subnet_id
}

data "aws_ssm_parameter" "al2023" {
  count = var.ami_id == null ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Resolve regional PrivateLink service availability during planning.
data "aws_vpc_endpoint_service" "session_manager" {
  for_each     = toset(["ssm", "ssmmessages"])
  service      = each.key
  service_type = "Interface"
}

resource "aws_security_group" "development" {
  name_prefix = "${var.name_prefix}-development-"
  description = "Development node with no inbound access."
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-development" }
}

# General egress is intentional for a development environment and future private workloads.
resource "aws_vpc_security_group_egress_rule" "development" {
  security_group_id = aws_security_group.development.id
  description       = "Allow outbound development traffic through NAT or private VPC routes."
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "session_manager" {
  name_prefix = "${var.name_prefix}-session-manager-"
  description = "Private Session Manager endpoints accessible only from the development node."
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-session-manager" }
}

resource "aws_vpc_security_group_ingress_rule" "session_manager" {
  security_group_id            = aws_security_group.session_manager.id
  description                  = "Allow node-initiated HTTPS to Session Manager endpoints."
  referenced_security_group_id = aws_security_group.development.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_endpoint" "session_manager" {
  for_each            = data.aws_vpc_endpoint_service.session_manager
  vpc_id              = var.vpc_id
  service_name        = each.value.service_name
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [var.subnet_id]
  security_group_ids  = [aws_security_group.session_manager.id]

  lifecycle {
    precondition {
      condition     = contains(each.value.availability_zones, data.aws_subnet.development.availability_zone)
      error_message = "The selected AZ must support the Session Manager interface endpoint service."
    }
  }

  tags = { Name = "${var.name_prefix}-${each.key}" }
}

resource "aws_iam_role" "development" {
  name_prefix = "${var.name_prefix}-dev-"
  description = "Development EC2 role for Systems Manager connectivity."
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "session_manager" {
  role       = aws_iam_role.development.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "development" {
  name_prefix = "${var.name_prefix}-dev-"
  role        = aws_iam_role.development.name
}

# Independent of the instance so its data survives instance replacement in this AZ.
resource "aws_ebs_volume" "home" {
  availability_zone = data.aws_subnet.development.availability_zone
  encrypted         = true
  type              = "gp3"
  size              = var.home_volume_size

  lifecycle {
    # AZ changes require an explicit data migration, not an empty replacement disk.
    ignore_changes = [availability_zone]
  }

  tags = { Name = "${var.name_prefix}-developer-home" }
}

resource "aws_instance" "development" {
  ami                         = var.ami_id != null ? var.ami_id : nonsensitive(data.aws_ssm_parameter.al2023[0].value)
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.development.id]
  iam_instance_profile        = aws_iam_instance_profile.development.name
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  user_data = join("\n", ["#cloud-config", yamlencode({
    write_files = [
      {
        path        = "/usr/local/sbin/developer-bootstrap"
        permissions = "0755"
        owner       = "root:root"
        content = templatefile("${path.module}/bootstrap.sh.tftpl", {
          home_volume_id    = aws_ebs_volume.home.id
          terraform_version = var.terraform_version
        })
      },
      {
        path        = "/etc/systemd/system/developer-bootstrap.service"
        permissions = "0644"
        owner       = "root:root"
        content     = <<-UNIT
          [Unit]
          Description=Prepare persistent developer home and terminal tools
          Wants=network-online.target
          After=network-online.target
          StartLimitIntervalSec=0

          [Service]
          Type=oneshot
          ExecStart=/usr/local/sbin/developer-bootstrap
          RemainAfterExit=yes
          Restart=on-failure
          RestartSec=30
          TimeoutStartSec=20min

          [Install]
          WantedBy=multi-user.target
        UNIT
      }
    ]
    runcmd = [
      ["systemctl", "daemon-reload"],
      ["systemctl", "enable", "--now", "--no-block", "developer-bootstrap.service"]
    ]
  })])

  lifecycle {
    precondition {
      condition     = aws_ebs_volume.home.availability_zone == data.aws_subnet.development.availability_zone
      error_message = "The existing home volume and instance must share an AZ. Migrate or back up the home volume before changing AZ."
    }
    precondition {
      condition     = data.aws_subnet.development.vpc_id == var.vpc_id
      error_message = "The development subnet must belong to the supplied VPC."
    }
  }

  # The subnet output also waits for NAT routes and route table association.
  depends_on = [
    aws_iam_role_policy_attachment.session_manager,
    aws_vpc_endpoint.session_manager,
    aws_vpc_security_group_ingress_rule.session_manager,
    aws_vpc_security_group_egress_rule.development
  ]

  tags = { Name = "${var.name_prefix}-development" }
}

resource "aws_volume_attachment" "home" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.home.id
  instance_id = aws_instance.development.id

  # Stop before detaching to avoid a live filesystem detach during replacement.
  stop_instance_before_detaching = true
}

resource "aws_ssm_document" "developer_session" {
  name            = "${var.name_prefix}-developer-shell"
  document_type   = "Session"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Open the persistent developer home after bootstrap completes."
    sessionType   = "Standard_Stream"
    inputs = {
      runAsEnabled                = true
      runAsDefaultUser            = "developer"
      idleSessionTimeout          = "20"
      maxSessionDuration          = "240"
      s3BucketName                = ""
      s3KeyPrefix                 = ""
      s3EncryptionEnabled         = false
      cloudWatchLogGroupName      = ""
      cloudWatchEncryptionEnabled = false
      cloudWatchStreamingEnabled  = false
      shellProfile = {
        linux = "if [ \"$(id -un)\" != developer ] || ! mountpoint -q /home/developer || ! test -f /run/developer-bootstrap.ready; then echo 'Developer bootstrap is not ready; inspect developer-bootstrap.service and console output.'; exit 1; fi; export HOME=/home/developer; cd \"$HOME\" && exec /bin/bash -l"
      }
    }
  })
}

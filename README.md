# Cloud Engineer exercise

Cloud infrastructure exercise using:

- **Cloud provider:** AWS
- **Git Provider:** GitHub 

The setup has a terminal development environment on EC2 and a private hello-app service on ECS Fargate.

## What is here

One VPC, one Availability Zone, and three subnets. With the example config:

- **Public — 10.20.0.0/24:** NAT Gateway and an Internet Gateway route.
- **Outbound — 10.20.1.0/24:** Amazon Linux 2023 development instance and internet access through NAT for packages and GitHub.
- **Isolated — 10.20.2.0/24:** one Linux x86_64 Fargate task, private HTTP on port 8080, with no internet default route.

Neither workload gets a public IP. Development has no inbound security group rules, the app HTTP is allowed only from the development security group. Cloud Map provides private DNS at `web.<project_name>-<environment>.internal`. Private endpoints handle SSM, ECR, and logs -> an S3 gateway endpoint handles ECR image layers.

Fargate avoids managing an app host. Session Manager avoids SSH or a bastion. The tradeoff is a single zone setup with one task, plus ongoing NAT and five interface endpoint charges. There is no load balancer or public app URL.

## Set up and apply

Run local commands in **PowerShell**, from `\cloudNative`. Start with Git, Terraform `>= 1.10, < 2.0`, AWS CLI v2, the Session Manager plugin, and Docker running a Linux daemon that can build `linux/amd64`. Keep the provider lock files. The runner needs internet access to AWS, Terraform providers, Docker Hub, and `us-docker.pkg.dev`.

Use an authenticated AWS profile with permission to provision the resources, pass IAM roles, push to ECR, and access the S3 backend. No deployer IAM policy or login setup is included. The EC2 role only supplies Systems Manager access.

```powershell
Set-Location D:\cloud-native-exercise
$env:AWS_PROFILE = "YOUR_AWS_PROFILE"
$env:AWS_REGION = "YOUR_APPLICATION_REGION"
$AccountId = aws sts get-caller-identity --query Account --output text
$AccountId
```

For a fresh checkout, copy the examples below. For an existing deployment, reuse its configuration and original state instead of overwriting them.

```powershell
Copy-Item bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars
Copy-Item infra/terraform.tfvars.example infra/terraform.tfvars
Copy-Item infra/backend.hcl.example infra/backend.hcl
```

Edit the files **before continuing**:


`bootstrap/terraform.tfvars` -> Expected account ID, bucket region, globally unique bucket name. Skip bootstrap if reusing an authorized backend.
`infra/terraform.tfvars` -> Expected account ID, region, AZ, project/environment names, and CIDRs. The AZ must support all five interface endpoint services.
`infra/backend.hcl` -> Actual bucket name and region, a separate state key for this stack.

The example uses `t3.medium`, a 30 GiB home volume, and Terraform `1.17.2` inside development, it resolves AWS's current AMI parameter.

**New state bucket only:** apply the separate bootstrap root, then copy its bucket output into `infra/backend.hcl`.

```powershell
terraform "-chdir=bootstrap" init "-backend-config=path=$AccountId.bootstrap.tfstate"
terraform "-chdir=bootstrap" apply
terraform "-chdir=bootstrap" output -raw state_bucket_name
```

Keep that local bootstrap state safe. The bucket has versioning, AES256 encryption, public access blocking, a TLS-only policy, and `prevent_destroy`. An existing backend needs state read/write and lock-file read/write/delete access, plus bucket listing.

**Deploy the stack:**

```powershell
terraform "-chdir=infra" init "-backend-config=backend.hcl"
terraform "-chdir=infra" apply
```

The apply creates ECR, builds `app/Dockerfile` with `app/` as its context, and pushes through the Docker provider using an ephemeral ECR token. It packages Google's `hello-app:1.0` with a BusyBox HTTP probe. ECS uses the published digest from `application_image_uri`. There is no separate manual build/push step or targeted apply. Keep the same Docker daemon available for later Terraform runs.

## Connect and check

Read the actual identifiers in local PowerShell:

```powershell
$dev = terraform "-chdir=infra" output -json development | ConvertFrom-Json
$app = terraform "-chdir=infra" output -json application | ConvertFrom-Json
$app | Select-Object dns_name,url
terraform "-chdir=infra" output -raw development_human_session_policy
```

 Generated session policy is required to perform, I needed to ask Mauricio for this. Terraform only outputs it. Inspection below needs separate AWS read permissions. Open the custom session:

```powershell
aws ssm start-session --target $dev.instance_id --document-name $dev.session_document_name
```

Bootstrap runs asynchronously. The session opens as `developer` only once the home disk is mounted and `/run/developer-bootstrap.ready` exists. If it is still starting, we need to wait and retry. For persistent failures, we can inspect `developer-bootstrap.service` and `/var/log/developer-bootstrap.log`.

Inside the **Linux development session**:

```bash
id -un
systemctl is-active developer-bootstrap.service docker.service amazon-ssm-agent.service
cat /var/lib/developer-bootstrap/tool-versions.txt
python3 -m pip --version
findmnt /home/developer

# Example values: replace with application.dns_name and application.url above.
APP_HOST='web.cloud-native-exercise-dev.internal'
APP_URL='http://web.cloud-native-exercise-dev.internal:8080/'
getent ahostsv4 "$APP_HOST"
curl --fail --silent --show-error --output /dev/null --write-out '%{http_code}\n' "$APP_URL"
```

Back in **local PowerShell**, check ECS and routing:

```powershell
aws ecs describe-services --cluster $app.cluster_name --services $app.service_name --query 'services[].{Desired:desiredCount,Running:runningCount,Pending:pendingCount,Rollout:deployments[].rolloutState}'
$taskIds = (aws ecs list-tasks --cluster $app.cluster_name --service-name $app.service_name --query taskArns --output text) -split '\s+'
aws ecs describe-tasks --cluster $app.cluster_name --tasks $taskIds --query 'tasks[].{Status:lastStatus,Health:healthStatus}'
$vpcId = terraform "-chdir=infra" output -raw vpc_id
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpcId" --query 'RouteTables[].{Subnets:Associations[].SubnetId,Routes:Routes}'
terraform "-chdir=infra" plan -detailed-exitcode
$LASTEXITCODE
```

**Tested:** Tested deployment, Session Manager access, development tools, private DNS/HTTP, reboot persistence, and a Terraform plan with no changes.

## Optional monitoring proposal

Application container logs are already configured to reach CloudWatch Logs at `/ecs/<name_prefix>/application` through the `awslogs` driver, with seven-day retention. As an optional improvement, I would monitor ECS service CPU and memory utilization using CloudWatch alarms for sustained high usage, with SNS email notifications. I would manage the alarm thresholds, evaluation periods, SNS topic, and email subscriptions through Terraform in the application module. Unfortunately I wasn't able to implement this proposal.

## Limits and cleanup

- Development is terminal-only, with passwordless sudo and Docker access.
- Bootstrap downloads packages and Terraform over the internet. Base images use tags; rebuilds on another daemon can change the digest. ECR tags are mutable, while ECS deploys by digest. Older digests stay until repository deletion.
- Home data survives reboot and instance replacement in the same AZ. Replacement rebuilds the root disk, so root disk customizations are lost. AZ changes need data migration. No backups are configured, the app filesystem is disposable and logs have seven-day retention.


```powershell
terraform "-chdir=infra" destroy
```

This deletes the home volume too, along with the instance, app, logs, network, and ECR repository/images. The separate state bucket and its versions stay behind, as do local configuration and bootstrap state. Retiring the bucket is separate because bootstrap blocks its destruction.

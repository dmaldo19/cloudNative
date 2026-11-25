module "network" {
  source = "./modules/network"

  name_prefix       = "${var.project_name}-${var.environment}"
  availability_zone = var.availability_zone
  vpc_cidr          = var.vpc_cidr
  subnet_newbits    = var.subnet_newbits
}

module "development" {
  source = "./modules/development"

  name_prefix       = "${var.project_name}-${var.environment}"
  vpc_id            = module.network.vpc_id
  subnet_id         = module.network.outbound_subnet_id
  instance_type     = var.development_instance_type
  ami_id            = var.development_ami_id
  home_volume_size  = var.development_home_volume_size
  terraform_version = var.development_terraform_version
}

module "application_image" {
  source = "./modules/container-image"

  name_prefix   = "${var.project_name}-${var.environment}"
  build_context = abspath("${path.module}/../app")
}

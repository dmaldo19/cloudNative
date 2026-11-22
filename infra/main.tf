module "network" {
  source = "./modules/network"

  name_prefix       = "${var.project_name}-${var.environment}"
  availability_zone = var.availability_zone
  vpc_cidr          = var.vpc_cidr
  subnet_newbits    = var.subnet_newbits
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Provider configuration accepts values without storing them in state or plans
ephemeral "aws_ecr_authorization_token" "image" {}

provider "docker" {
  # Select the daemon with DOCKER_HOST or DOCKER_CONTEXT on the terraform runner
  registry_auth {
    address  = trimprefix(ephemeral.aws_ecr_authorization_token.image.proxy_endpoint, "https://")
    username = ephemeral.aws_ecr_authorization_token.image.user_name
    password = ephemeral.aws_ecr_authorization_token.image.password
  }
}

terraform {
  backend "s3" {
    bucket       = "reqsai-terraform-state-418272789689"
    key          = "envs/production/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "reqsai"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

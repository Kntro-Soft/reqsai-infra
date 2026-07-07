provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "reqsai"
      ManagedBy   = "terraform"
      Environment = "shared"
    }
  }
}

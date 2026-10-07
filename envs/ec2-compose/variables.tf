variable "aws_region" {
  description = "AWS region for every resource of this environment."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name, used in resource names (reqsai-<environment>-*) and in the Environment tag."
  type        = string
  default     = "mvp"
}

variable "instance_type" {
  description = "EC2 instance type. t3.small (2 GiB) is the recommended default; t3.micro (1 GiB) works with the 'micro' memory profile and a bigger swap file. Graviton types (t4g.*) need linux/arm64 images."
  type        = string
  default     = "t3.small"
}

variable "availability_zone" {
  description = "Availability zone for the public subnet and the instance. Null picks the first zone that offers instance_type."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "CIDR block of the dedicated VPC. Only one /24 public subnet is carved out of it."
  type        = string
  default     = "10.20.0.0/16"
}

variable "ami_id" {
  description = "Explicit AMI id. Null resolves the latest Canonical Ubuntu 24.04 LTS AMI for the instance architecture."
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Size in GiB of the encrypted gp3 root volume that holds the OS, Docker images, the Postgres volume and the local backups."
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "root_volume_size must be at least 20 GiB."
  }
}

variable "cpu_credits" {
  description = "Credit option for burstable (T) instances: 'standard' never bills surplus CPU credits, 'unlimited' avoids throttling at the cost of surplus charges when the 24h average exceeds the baseline."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "unlimited"], var.cpu_credits)
    error_message = "cpu_credits must be 'standard' or 'unlimited'."
  }
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key installed for the 'ubuntu' user. Ansible connects with the matching private key, directly or tunnelled through SSM."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "admin_cidrs" {
  description = "CIDR blocks allowed to reach SSH (port 22). Empty keeps port 22 closed and Ansible reaches the host through SSM Session Manager."
  type        = list(string)
  default     = []
}

variable "enable_ssm" {
  description = "Attach AmazonSSMManagedInstanceCore to the instance role so the host is reachable through SSM Session Manager without opening port 22."
  type        = bool
  default     = true
}

variable "dns_zone_name" {
  description = "Existing public Route53 hosted zone (e.g. tamci.app). Empty skips Route53 and serves the app on <elastic-ip-with-dashes>.sslip.io."
  type        = string
  default     = ""
}

variable "dns_record_name" {
  description = "Label of the A record created inside dns_zone_name (e.g. 'mvp' -> mvp.tamci.app). Ignored when dns_zone_name is empty."
  type        = string
  default     = "mvp"
}

variable "enable_backup_bucket" {
  description = "Create a private S3 bucket for off-host copies of the daily pg_dump and grant the instance role write access to it."
  type        = bool
  default     = false
}

variable "backup_bucket_retention_days" {
  description = "Days after which backup objects in the S3 bucket expire."
  type        = number
  default     = 30
}

variable "enable_ecr_pull" {
  description = "Attach AmazonEC2ContainerRegistryReadOnly to the instance role, for pulling images from ECR instead of GHCR."
  type        = bool
  default     = false
}

variable "termination_protection" {
  description = "Enable EC2 API termination protection. The database lives on the root volume, so this guards it against an accidental destroy; set it to false and apply before tearing the environment down."
  type        = bool
  default     = true
}

variable "github_deploy_repository" {
  description = "GitHub repository (owner/name) whose deploy workflow may assume the deploy role through OIDC. Empty skips the OIDC provider and the role."
  type        = string
  default     = "Kntro-Soft/reqsai-infra"
}

variable "github_deploy_environment" {
  description = "GitHub Actions environment the deploy job must run in; only tokens with sub repo:<repository>:environment:<this> can assume the role."
  type        = string
  default     = "mvp"
}

variable "github_oidc_provider_arn" {
  description = "ARN of an existing token.actions.githubusercontent.com OIDC provider in the account. Empty creates one (an account holds a single provider per URL)."
  type        = string
  default     = ""
}

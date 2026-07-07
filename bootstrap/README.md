# bootstrap

Creates the S3 bucket and DynamoDB table that every other configuration in this repo
(`envs/dev`, `envs/staging`, `envs/prod`, ...) uses as its **remote backend** for Terraform state.

This is the one directory in the repo that intentionally does **not** use a remote backend itself —
it can't reference a backend it hasn't created yet. Its state stays **local**
(`bootstrap/terraform.tfstate`), applied once, by one person.

## Usage

```bash
cd bootstrap
terraform init
terraform plan
terraform apply
```

## Important

- `terraform.tfstate` here is **not** committed to git (see `.gitignore`). Back it up somewhere safe
  (a password manager, an encrypted note, S3 with a different bucket than the one this creates) —
  if you lose it, Terraform forgets these resources exist and you'd have to `terraform import` them
  again to manage them further. Losing the state file does **not** delete the bucket/table
  themselves (`prevent_destroy = true` on both).
- This should only need to run **once per AWS account**. Every other configuration just points its
  `backend "s3"` block at the outputs of this module (see `envs/dev/providers.tf`).
- `terraform.tfvars` (with your real bucket name) is git-ignored too — copy
  `terraform.tfvars.example` and fill in your AWS account id. Bucket names are globally unique
  across *all* AWS accounts, which is why it's parameterized instead of a fixed default.

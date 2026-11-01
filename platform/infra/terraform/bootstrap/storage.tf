# Terraform state and backup buckets: private, versioned, encrypted, TLS only (see ../modules/private-bucket).

module "state_bucket" {
  source = "../modules/private-bucket"

  bucket_name             = local.bucket_names.state
  noncurrent_version_days = 90
}

module "backup_bucket" {
  source = "../modules/private-bucket"

  bucket_name               = local.bucket_names.backups
  noncurrent_version_days   = 30
  expire_current_after_days = var.backup_retention_days
}

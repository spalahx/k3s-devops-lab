data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  tags = {
    Project   = var.project
    Env       = "bootstrap"
    Owner     = var.owner
    ManagedBy = "terraform"
  }

  # Both buckets are versioned. Noncurrent versions are kept for a limited time.
  buckets = {
    state   = { noncurrent_days = 90 }
    backups = { noncurrent_days = 30 }
  }

  bucket_names = {
    for key, _ in local.buckets : key => "${var.project}-${key}-${local.account_id}"
  }
}

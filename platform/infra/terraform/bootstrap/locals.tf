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

  bucket_names = {
    state   = "${var.project}-state-${local.account_id}"
    backups = "${var.project}-backups-${local.account_id}"
  }
}

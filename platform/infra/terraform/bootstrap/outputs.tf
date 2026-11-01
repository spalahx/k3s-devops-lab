output "state_bucket" {
  description = "Bucket for Terraform state (use it in backend.hcl)."
  value       = aws_s3_bucket.this["state"].id
}

output "backup_bucket" {
  description = "Bucket for backups."
  value       = aws_s3_bucket.this["backups"].id
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC identity provider."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "plan_role_arn" {
  description = "Role for pull request plans; set as AWS_PLAN_ROLE_ARN in GitHub."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Role for apply jobs in the protected Environment; set as AWS_APPLY_ROLE_ARN in GitHub."
  value       = aws_iam_role.apply.arn
}

output "ci_trust_subjects" {
  description = "OIDC subjects accepted by the CI roles."
  value       = local.subjects
}

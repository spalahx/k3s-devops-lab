# Runs without AWS credentials: the provider is mocked.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }

  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  region            = "us-east-1"
  owner             = "tester"
  github_repository = "example/lab"
  alert_email       = "alerts@example.com"
}

run "buckets_are_private_versioned_and_encrypted" {
  command = plan

  assert {
    condition = alltrue([
      for _, v in aws_s3_bucket_public_access_block.this :
      v.block_public_acls && v.block_public_policy && v.ignore_public_acls && v.restrict_public_buckets
    ])
    error_message = "Every bucket must block all public access."
  }

  assert {
    condition = alltrue([
      for _, v in aws_s3_bucket_versioning.this : v.versioning_configuration[0].status == "Enabled"
    ])
    error_message = "Every bucket must be versioned."
  }

  assert {
    condition     = aws_s3_bucket.this["state"].bucket == "k3s-devops-lab-state-123456789012"
    error_message = "State bucket name must include the project and the account id."
  }

  assert {
    condition     = length(aws_s3_bucket_policy.tls_only) == 2
    error_message = "Both buckets must have a TLS-only policy."
  }
}

run "ci_roles_are_bound_to_the_repository" {
  command = plan

  assert {
    condition     = output.ci_trust_subjects.plan == "repo:example/lab:pull_request"
    error_message = "The plan role must only trust pull requests of the repository."
  }

  assert {
    condition     = output.ci_trust_subjects.apply == "repo:example/lab:environment:aws-apply"
    error_message = "The apply role must only trust the protected Environment of the repository."
  }
}

run "budget_has_four_alerts" {
  command = plan

  assert {
    condition     = length(aws_budgets_budget.monthly.notification) == 4
    error_message = "Expect 50, 80, 100 percent actual and 100 percent forecasted alerts."
  }

  assert {
    condition     = aws_budgets_budget.monthly.limit_amount == "20"
    error_message = "Default monthly budget is 20 USD."
  }
}

run "rejects_a_malformed_repository" {
  command = plan

  variables {
    github_repository = "not-a-repository"
  }

  expect_failures = [var.github_repository]
}

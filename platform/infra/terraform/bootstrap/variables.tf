variable "region" {
  description = "AWS region for every resource. Pick the cheapest region your account allows and keep it (D-032)."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Name prefix for every resource."
  type        = string
  default     = "k3s-devops-lab"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,29}$", var.project))
    error_message = "project must be 3-30 characters: lowercase letters, digits and dashes, starting with a letter."
  }
}

variable "owner" {
  description = "Value of the Owner tag, for example your GitHub user name."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the CI roles, as owner/name."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/name."
  }
}

variable "apply_environment" {
  description = "Name of the GitHub Environment (with required reviewers) whose jobs may assume the apply role."
  type        = string
  default     = "aws-apply"
}

variable "alert_email" {
  description = "E-mail address for budget and cost anomaly alerts."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid e-mail address."
  }
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget in USD; alerts fire at 50, 80 and 100 percent of actual and 100 percent of forecasted cost."
  type        = number
  default     = 20

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd must be greater than zero."
  }
}

variable "backup_retention_days" {
  description = "Days after which current objects in the backup bucket expire."
  type        = number
  default     = 90

  validation {
    condition     = var.backup_retention_days >= 7
    error_message = "backup_retention_days must be at least 7."
  }
}

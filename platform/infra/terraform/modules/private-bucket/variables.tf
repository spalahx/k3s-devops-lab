variable "bucket_name" {
  description = "Globally unique bucket name."
  type        = string
}

variable "noncurrent_version_days" {
  description = "Days to keep old object versions."
  type        = number
  default     = 30
}

variable "expire_current_after_days" {
  description = "Days after which current objects expire; null keeps them forever."
  type        = number
  default     = null
}

# A private, versioned, encrypted bucket that accepts TLS requests only.
# SSE-S3 (AES256) is used instead of a customer managed KMS key to avoid the monthly key fee.

resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV_AWS_18:Access logging needs a second bucket; not worth it for a learning lab
  #checkov:skip=CKV_AWS_144:Cross-region replication doubles the cost; versioning and lifecycle are enough here
  #checkov:skip=CKV_AWS_145:SSE-S3 is chosen on purpose, a customer managed key costs a monthly fee
  #checkov:skip=CKV2_AWS_62:Nothing consumes S3 event notifications in this lab
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# trivy:ignore:AWS-0132 SSE-S3 is chosen on purpose: a customer managed key costs a monthly fee and adds nothing for a learning lab.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "housekeeping"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_days
    }
  }

  dynamic "rule" {
    for_each = var.expire_current_after_days == null ? [] : [var.expire_current_after_days]

    content {
      id     = "expire-current-objects"
      status = "Enabled"

      filter {}

      abort_incomplete_multipart_upload {
        days_after_initiation = 7
      }

      expiration {
        days = rule.value
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_policy" "tls_only" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}

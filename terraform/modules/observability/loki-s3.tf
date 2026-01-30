# -----------------------------------------------------------------------------
# Loki S3 Storage
# -----------------------------------------------------------------------------
# S3 bucket for Loki log storage using TSDB single-store mode.
# Both chunks and index are stored in S3 (no DynamoDB required).
#
# The bucket is protected from deletion (prevent_destroy) to preserve logs.
# To destroy: manually empty the bucket first, then remove the lifecycle rule.
#
# Requirements: 8.4
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "loki" {
  bucket = "${var.project_name}-loki-logs"

  tags = {
    Name    = "${var.project_name}-loki-logs"
    Service = "loki"
  }

  # Prevent accidental deletion of log data
  # To destroy: manually empty bucket, then comment out this block
  lifecycle {
    prevent_destroy = true
  }
}

# Disable versioning - logs are append-only
resource "aws_s3_bucket_versioning" "loki" {
  bucket = aws_s3_bucket.loki.id

  versioning_configuration {
    status = "Disabled"
  }
}

# Server-side encryption with SSE-S3
resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle policy for retention enforcement
# Objects are deleted after retention_days + 1 (buffer for compactor)
resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    expiration {
      days = var.loki_retention_days + 1
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "loki" {
  bucket = aws_s3_bucket.loki.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

################################################################################
# Lookup current AWS account ID — used to guarantee a unique bucket name
################################################################################
data "aws_caller_identity" "current" {}

locals {
  # e.g. "wiz-exercise-mongo-backups-123456789012"
  # Account ID is injected at plan time — no hardcoding needed
  s3_bucket_name = "${var.project_name}-mongo-backups-${data.aws_caller_identity.current.account_id}"
}

################################################################################
# S3 Bucket: MongoDB Backups
# INTENTIONAL WEAKNESSES:
#   - Public read access enabled
#   - Public listing enabled
#   - No versioning
#   - No encryption
################################################################################
resource "aws_s3_bucket" "mongodb_backups" {
  bucket        = local.s3_bucket_name
  force_destroy = true

  tags = {
    Name = "${var.project_name}-mongo-backups"
    Note = "Intentionally public for Wiz exercise"
  }
}

# INTENTIONAL WEAKNESS: Disable block public access so the bucket policy below
# can grant public read + list. ACLs are not used (disabled by AWS since 2023).
resource "aws_s3_bucket_public_access_block" "mongodb_backups" {
  bucket = aws_s3_bucket.mongodb_backups.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# INTENTIONAL WEAKNESS: Bucket policy allows public read and list
resource "aws_s3_bucket_policy" "mongodb_backups" {
  depends_on = [aws_s3_bucket_public_access_block.mongodb_backups]

  bucket = aws_s3_bucket.mongodb_backups.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadAndList"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.mongodb_backups.arn,
          "${aws_s3_bucket.mongodb_backups.arn}/*"
        ]
      }
    ]
  })
}

# Create a backups/ prefix placeholder
resource "aws_s3_object" "backups_prefix" {
  bucket  = aws_s3_bucket.mongodb_backups.id
  key     = "backups/.gitkeep"
  content = ""
}

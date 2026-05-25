################################################################################
# PREVENTATIVE CONTROL — S3 Block Public Access (account-level)
#
# Prevents any S3 bucket in the account from being made publicly accessible,
# overriding all bucket-level settings. This directly remediates the intentional
# public backup bucket misconfiguration present in this environment.
################################################################################
resource "aws_s3_account_public_access_block" "main" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

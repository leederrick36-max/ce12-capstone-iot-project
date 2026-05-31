# ----------------------------------------------------------------
# 1. STORAGE: S3 BUCKET FOR SENSOR DATA
# ----------------------------------------------------------------
resource "aws_s3_bucket" "simulation_data" {
  bucket        = "minipc-iot-simulation-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "simulation_data_controls" {
  bucket = aws_s3_bucket.simulation_data.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ----------------------------------------------------------------
# 2. BUCKET ACCESS PERMISSIONS
# ----------------------------------------------------------------
resource "aws_s3_bucket_policy" "allow_kvs_write" {
  bucket = aws_s3_bucket.simulation_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "KvsSignalingAndStorageAccess"
        Effect    = "Allow"
        Principal = { Service = "kinesisvideo.amazonaws.com" }
        Action    = ["s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
        Resource  = [aws_s3_bucket.simulation_data.arn, "${aws_s3_bucket.simulation_data.arn}/*"]
      }
    ]
  })
}


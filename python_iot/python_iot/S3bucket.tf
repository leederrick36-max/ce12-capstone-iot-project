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


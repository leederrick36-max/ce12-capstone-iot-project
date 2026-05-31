# ================================================================
# VIDEO: KINESIS VIDEO STREAM VIA AWSCC (NATIVE CORE SETUP)
# ================================================================

resource "awscc_kinesisvideo_stream" "video_stream" {
  name                    = "FHD_Security_Camera_Stream"
  data_retention_in_hours = 24
  media_type              = "video/h264"
}

# ================================================================
# AUTOMATED API OVERLAY VIA LOCAL-EXEC (FIXES THE UNSUPPORTED ARGUMENT)
# ================================================================

resource "null_resource" "enable_kvs_image_generation" {
  triggers = {
    stream_name = awscc_kinesisvideo_stream.video_stream.name
    bucket_id   = aws_s3_bucket.simulation_data.id
  }

  depends_on = [
    awscc_kinesisvideo_stream.video_stream,
    aws_s3_bucket.simulation_data
  ]

  provisioner "local-exec" {
    command = <<EOT
      aws kinesisvideo update-image-generation-configuration \
        --stream-name "${awscc_kinesisvideo_stream.video_stream.name}" \
        --image-generation-configuration '{
          "Status": "ENABLED",
          "ImageSelectorType": "PRODUCER_TIMESTAMP",
          "DestinationConfig": {
            "DestinationRegion": "ap-southeast-1",
            "Uri": "s3://${aws_s3_bucket.simulation_data.id}/thumbnails"
          },
          "SamplingInterval": 3000,
          "Format": "JPEG"
        }' --region ap-southeast-1
    EOT
  }
}

# ================================================================
# IDENTITY & ROLES: KVS STREAMING DELEGATION
# ================================================================

resource "aws_iam_role" "kvs_role" {
  name = "MiniPC_KVS_Role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "credentials.iot.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "kvs_policy" {
  name = "KvsStreamingPolicy"
  role = aws_iam_role.kvs_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kinesisvideo:PutMedia", "kinesisvideo:DescribeStream", "kinesisvideo:GetDataEndpoint"]
      Resource = awscc_kinesisvideo_stream.video_stream.arn
    }]
  })
}

resource "aws_iot_role_alias" "kvs_alias" {
  alias    = "KvsCameraRoleAlias"
  role_arn = aws_iam_role.kvs_role.arn
}

# ================================================================
# COMPLEMENTARY PERMISSIONS: S3 VIDEO ARCHIVING CAPABILITIES
# ================================================================

resource "aws_iam_role_policy" "kvs_s3_archiving" {
  name = "KvsS3ArchivingPolicy"
  role = aws_iam_role.kvs_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
        Resource = [aws_s3_bucket.simulation_data.arn, "${aws_s3_bucket.simulation_data.arn}/*"]
      }
    ]
  })
}

# ================================================================
# OPTION 2: FULL VIDEO SEGMENT ARCHIVING VIA AWS LAMBDA
# ================================================================

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "kvs_archiver" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "KVS_Video_Segment_Archiver"
  role             = aws_iam_role.kvs_lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      STREAM_NAME    = awscc_kinesisvideo_stream.video_stream.name
      S3_BUCKET_NAME = aws_s3_bucket.simulation_data.id
    }
  }
}

resource "aws_iam_role" "kvs_lambda_role" {
  name = "KVS_Lambda_Archiver_Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_combined_policy" {
  name = "KvsLambdaCombinedExecutionPolicy"
  role = aws_iam_role.kvs_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KVSStreamConsumerAccess"
        Effect = "Allow"
        Action = [
          "kinesisvideo:DescribeStream",
          "kinesisvideo:GetDataEndpoint",
          "kinesisvideo:GetMedia"
        ]
        Resource = awscc_kinesisvideo_stream.video_stream.arn
      },
      {
        Sid    = "S3BucketTargetAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.simulation_data.arn}/*"
      },
      {
        Sid    = "CloudWatchLoggingAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}
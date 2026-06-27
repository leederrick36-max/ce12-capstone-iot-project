# ==============================================================================
# 1. INDUSTRIAL REGISTRY: THING TYPE SPECIFICATION
# ==============================================================================
# FIXED: Declares the missing thing type that the fleet template references
resource "aws_iot_thing_type" "minipc_type" {
  name = "MiniPC_Hardware"
  properties {
    description = "Industrial Edge MiniPC Gateway Fleet Units"
  }
}

# ==============================================================================
# 2. IDENTITY & BOOTSTRAPPING: FLEET PROVISIONING CLAIM ASSETS
# ==============================================================================
resource "tls_private_key" "claim_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "claim_cert_tls" {
  private_key_pem = tls_private_key.claim_key.private_key_pem
  subject {
    common_name  = "Fleet_Provisioning_Claim"
    organization = "MiniPC_Fleet"
  }
  validity_period_hours = 8760
  allowed_uses          = ["digital_signature", "key_encipherment"]
}

resource "aws_iot_certificate" "claim_cert" {
  certificate_pem = tls_self_signed_cert.claim_cert_tls.cert_pem
  active          = true
}

# ==============================================================================
# 3. SECURITY LAYER: BOOTSTRAPPING & PERMANENT PERMISSIONS
# ==============================================================================
resource "aws_iot_policy" "claim_policy" {
  name = "ProvisioningClaimPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iot:Connect"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["iot:Publish", "iot:Receive"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/$aws/certificates/create/*",
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/$aws/provisioning-templates/MiniPC_Fleet_Template/provision/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["iot:Subscribe"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topicfilter/$aws/certificates/create/*",
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topicfilter/$aws/provisioning-templates/MiniPC_Fleet_Template/provision/*"
        ]
      }
    ]
  })
}

resource "aws_iot_policy_attachment" "claim_attach" {
  policy = aws_iot_policy.claim_policy.name
  target = aws_iot_certificate.claim_cert.arn
}

resource "aws_iot_policy" "permanent_fleet_policy" {
  name = "PermanentFleetPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iot:Connect", "iot:Publish", "iot:Subscribe", "iot:Receive"]
        Resource = "*"
      }
    ]
  })
}

# --- FLEET REGISTRATION DELEGATION AUTHORITY ---
resource "aws_iam_role" "provisioning_role" {
  name = "IoTProvisioningRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "iot.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "prov_attach" {
  role       = aws_iam_role.provisioning_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSIoTThingsRegistration"
}

# ==============================================================================
# 4. FLEET PROVISIONING TEMPLATE (Synchronized to device_runner.py Naming Model)
# ==============================================================================
resource "aws_iot_provisioning_template" "fleet_template" {
  name                  = "MiniPC_Fleet_Template"
  provisioning_role_arn = aws_iam_role.provisioning_role.arn
  enabled               = true

  template_body = jsonencode({
    Parameters = { SerialNumber = { Type = "String" }, DeviceModel = { Type = "String" } }
    Resources = {
      thing = {
        Type = "AWS::IoT::Thing"
        Properties = {
          ThingName     = { Ref : "SerialNumber" }
          ThingTypeName = "MiniPC_Hardware"
        }
      }
      certificate = {
        Type       = "AWS::IoT::Certificate"
        Properties = { CertificateId = { Ref : "AWS::IoT::Certificate::Id" }, Status = "Active" }
      }
      policy = {
        Type       = "AWS::IoT::Policy"
        Properties = { PolicyName = aws_iot_policy.permanent_fleet_policy.name }
      }
    }
  })

  # Forces Terraform to wait until the type exists in AWS before deploying the template
  depends_on = [aws_iot_thing_type.minipc_type]
}

# ==============================================================================
# 5. AWS IOT CORE RULES ENGINE (Telemetry Routing to S3 Bucket)
# ==============================================================================
resource "aws_iot_topic_rule" "sensor_to_s3" {
  name        = "StoreSensorData"
  enabled     = true
  sql         = "SELECT sensor_id, temp, timestamp FROM 'fleet/sensors/+'"
  sql_version = "2016-03-23"

  s3 {
    role_arn    = aws_iam_role.pipeline_role.arn
    bucket_name = aws_s3_bucket.simulation_data.id
    key         = "telemetry/sensor_$${sensor_id}/$${timestamp()}.json"
  }
}

# ==============================================================================
# 6. METADATA SECURITY: V2 DIAGNOSTIC LOGGING OPTIONS
# ==============================================================================
resource "aws_cloudwatch_log_group" "iot_system_logs" {
  name              = "AWSIotLogsV2"
  retention_in_days = 7
}

resource "aws_iam_role" "iot_logging_role" {
  name = "IoTLoggingToCloudWatchRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "iot.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "iot_logging_policy" {
  name = "IoTLoggingCloudWatchWritePolicy"
  role = aws_iam_role.iot_logging_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "logs:DescribeLogGroups"]
      Resource = "*"
    }]
  })
}

resource "aws_iot_logging_options" "account_wide_logging" {
  default_log_level = "INFO"
  role_arn          = aws_iam_role.iot_logging_role.arn
}

# ==============================================================================
# 7. LOCAL BOOTSTRAP EXPORTS (Writes files dynamically for your script startup)
# ==============================================================================
resource "local_file" "claim_key_file" {
  content  = tls_private_key.claim_key.private_key_pem
  filename = "claim.private.key"
}

resource "local_file" "claim_cert_file" {
  content  = tls_self_signed_cert.claim_cert_tls.cert_pem
  filename = "claim.cert.pem"
}
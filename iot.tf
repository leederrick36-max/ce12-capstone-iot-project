# ================================================================
# 1. IDENTITY: THE PROVISIONING CLAIM CERTIFICATE
# ================================================================

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

# ================================================================
# 2. POLICIES: CLAIM vs PERMANENT BOOTSTRAP CONTROL
# ================================================================

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
      },
      {
        Effect   = "Allow"
        Action   = "iot:AssumeRoleWithCertificate"
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rolealias/KvsCameraRoleAlias"
      }
    ]
  })
}

# ================================================================
# 3. ROLES: AWS REGISTRY PROVISIONING DELEGATION
# ================================================================

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

# ================================================================
# 4. FLEET PROVISIONING TEMPLATE Blueprint
# ================================================================

resource "aws_iot_provisioning_template" "fleet_template" {
  name                  = "MiniPC_Fleet_Template"
  provisioning_role_arn = aws_iam_role.provisioning_role.arn
  enabled               = true

  template_body = jsonencode({
    Parameters = { SerialNumber = { Type = "String" }, DeviceModel = { Type = "String" } }
    Resources = {
      thing = {
        Type       = "AWS::IoT::Thing"
        Properties = { ThingName = { "Fn::Join" : ["", ["Device_", { Ref : "SerialNumber" }]] } }
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
}

# ================================================================
# 5. RULES: DATA TELEMETRY ROUTER
# ================================================================

resource "aws_iam_role" "iot_s3_role" {
  name = "IoTToS3Role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "iot.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "iot_s3_policy" {
  role = aws_iam_role.iot_s3_role.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "s3:PutObject", Resource = "${aws_s3_bucket.simulation_data.arn}/*" }]
  })
}

resource "aws_iot_topic_rule" "sensor_to_s3" {
  name        = "StoreSensorData"
  enabled     = true
  sql         = "SELECT * FROM 'fleet/sensors/+'"
  sql_version = "2016-03-23"
  s3 {
    role_arn    = aws_iam_role.iot_s3_role.arn
    bucket_name = aws_s3_bucket.simulation_data.id
    key         = "sensor_data/$${topic()}/$${timestamp()}.json"
  }
}

# ----------------------------------------------------------------
# 3. OUTPUTS AND LOCAL FILES
# ----------------------------------------------------------------
resource "local_file" "claim_key_file" {
  content  = tls_private_key.claim_key.private_key_pem
  filename = "claim.private.key"
}

resource "local_file" "claim_cert_file" {
  content  = tls_self_signed_cert.claim_cert_tls.cert_pem
  filename = "claim.cert.pem"
}
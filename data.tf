# Data sources for account details
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iot_endpoint" "data" { endpoint_type = "iot:Data-ATS" }
data "aws_iot_endpoint" "creds" { endpoint_type = "iot:CredentialProvider" }
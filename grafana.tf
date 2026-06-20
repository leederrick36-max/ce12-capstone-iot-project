# 1. CloudWatch Data Source
resource "grafana_data_source" "aws_cloudwatch" {
  type = "cloudwatch"
  name = "AWS-CloudWatch"
  json_data_encoded = jsonencode({
    defaultRegion = "ap-southeast-1"
    authType      = "arn"
    assumeRoleArn = "arn:aws:iam::${var.aws_account_id}:role/GrafanaIntegrationRole"
  })
}

# 2. SiteWise Data Source
resource "grafana_data_source" "aws_sitewise" {
  type = "grafana-iot-sitewise-datasource"
  name = "AWS-IoT-SiteWise"
  json_data_encoded = jsonencode({
    defaultRegion = "ap-southeast-1"
    authType      = "grafana_assume_role"   # "arn"
    assumeRoleArn = "arn:aws:iam::${var.aws_account_id}:role/GrafanaIntegrationRole"
    externalId    = "1698059"
  })
}



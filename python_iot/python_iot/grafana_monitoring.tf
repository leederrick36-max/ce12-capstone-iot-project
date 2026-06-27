# ==============================================================================
# GRAFANA CLOUD INTEGRATION: GOVERNANCE & OBSERVABILITY ROLE
# ==============================================================================

resource "aws_iam_role" "grafana_role" {
  name = "GrafanaIntegrationRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      # Using the variables here
      Principal = { AWS = "arn:aws:iam::008923505280:root" }
      Action    = "sts:AssumeRole"
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": var.grafana_cloud_account_id
        }
      }
    }]
  })
}
resource "aws_iam_role_policy" "grafana_policy" {
  name = "GrafanaDataReadAccess"
  role = aws_iam_role.grafana_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:GetMetricWidgetImage",
          "iotsitewise:ListAssets",
          "iotsitewise:DescribeAsset",
          "iotsitewise:GetAssetPropertyValue",
          "iotsitewise:BatchGetAssetPropertyValue",
          "iotsitewise:ListAssetModels",
          "iotsitewise:ListAssetProperties",
          "iotsitewise:ListAssetRelationships",
          "iotsitewise:ListTimeSeries",
          "iotsitewise:GetAssetPropertyValueHistory",
          "iotsitewise:GetAssetPropertyAggregates",
          "iotsitewise:GetInterpolatedAssetPropertyValues",
          "iotsitewise:DescribeAssetModel",
          "iotsitewise:DescribeAssetProperty",
          "iotsitewise:DescribeTimeSeries",
          "logs:DescribeLogGroups", 
          "logs:StartQuery", 
          "logs:GetQueryResults", 
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StopQuery",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}
output "used_asset_model_id" {
  description = "The SiteWise asset model id used by Terraform (existing or newly created)."
  value       = var.existing_asset_model_id != "" ? var.existing_asset_model_id : awscc_iotsitewise_asset_model.gateway_model[0].asset_model_id
}

output "used_asset_id" {
  description = "The SiteWise asset id used by Terraform (existing or newly created)."
  value       = var.existing_asset_id != "" ? var.existing_asset_id : awscc_iotsitewise_asset.gateway_instance[0].asset_id
}

output "grafana_role_arn" {
  description = "The ARN of the IAM role used by Grafana Cloud"
  value       = aws_iam_role.grafana_role.arn
}
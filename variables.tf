variable "existing_asset_model_id" {
  description = "If set, Terraform will use this existing SiteWise asset model id instead of creating a new one. Leave empty to create a new model."
  type        = string
  default     = ""
}

variable "existing_asset_id" {
  description = "If set, Terraform will use this existing SiteWise asset id instead of creating a new asset. Leave empty to create a new asset."
  type        = string
  default     = ""
}


variable "aws_account_id" {
  description = "The 12-digit AWS Account ID"
  type        = string
  sensitive   = true
}

variable "grafana_cloud_account_id" {
  description = "The unique Grafana Cloud Organization/Account ID"
  type        = string
  sensitive   = true
}

variable "grafana_api_token" {
  type        = string
  description = "API token for Grafana provider authentication"
  sensitive   = true
}
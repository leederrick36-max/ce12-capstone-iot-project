output "iot_data_endpoint" { value = data.aws_iot_endpoint.data.endpoint_address }
output "iot_credential_endpoint" { value = data.aws_iot_endpoint.creds.endpoint_address }
output "s3_bucket_name" { value = aws_s3_bucket.simulation_data.id }
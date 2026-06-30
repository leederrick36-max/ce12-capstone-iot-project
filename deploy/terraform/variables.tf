variable "aws_region" {
  description = "AWS region the device's IoT/S3 infra already lives in"
  type        = string
  default     = "ap-southeast-1"
}

variable "s3_bucket_name" {
  description = "Existing S3 bucket the device uploads video clips to"
  type        = string
  default     = "minipc-iot-simulation-255945442255"
}

variable "ecr_repository_name" {
  description = "Name for the new ECR repository holding the device_runner image"
  type        = string
  default     = "minipc-device-runner"
}

variable "image_tag" {
  description = "Tag of the device_runner image already pushed to ECR. Push at least once (see deploy README) before the first full apply."
  type        = string
  default     = "latest"
}

variable "vpc_id" {
  description = "VPC the task's security group is created in"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets the Fargate task runs in. Must reach the internet (IoT Core, S3, SSM) via either a public IP + Internet Gateway, or a NAT gateway."
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Set true if subnet_ids are public subnets with no NAT gateway in front of them"
  type        = bool
  default     = true
}

variable "schedule_expression" {
  description = "When to kick off the daily batch run. Default = 01:00 UTC = 09:00 Singapore time"
  type        = string
  default     = "cron(0 1 * * ? *)"
}

variable "run_duration_seconds" {
  description = "How long device_runner.py runs before self-stopping (passed through as RUN_DURATION_SECONDS env var)"
  type        = number
  default     = 28800 # 8 hours
}

variable "task_cpu" {
  description = "Fargate task vCPU units (256/512/1024/...)"
  type        = string
  default     = "512"
}

variable "task_memory" {
  description = "Fargate task memory in MiB"
  type        = string
  default     = "1024"
}

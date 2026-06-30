terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# ECR - image repository for the containerized device_runner
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "device_runner" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ---------------------------------------------------------------------------
# CloudWatch Logs
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "device_runner" {
  name              = "/ecs/${var.ecr_repository_name}"
  retention_in_days = 14
}

# ---------------------------------------------------------------------------
# SSM Parameters - placeholders only. Terraform creates/owns the parameter
# *resources*, but never their real secret value. Seed the actual cert/key/CA
# content once via `aws ssm put-parameter --overwrite` (see deploy README) so
# private key material never lives in Terraform state or a .tfvars file.
# ---------------------------------------------------------------------------
resource "aws_ssm_parameter" "perm_cert" {
  name  = "/minipc/perm_cert"
  type  = "SecureString"
  value = "REPLACE_ME"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "perm_key" {
  name  = "/minipc/perm_key"
  type  = "SecureString"
  value = "REPLACE_ME"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "root_ca" {
  name  = "/minipc/root_ca"
  type  = "SecureString"
  value = "REPLACE_ME"

  lifecycle {
    ignore_changes = [value]
  }
}

# ---------------------------------------------------------------------------
# IAM - ECS task execution role (pulls image from ECR, writes logs)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.ecr_repository_name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------------------------------------------------------------------------
# IAM - task role (the running container's own AWS permissions)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.ecr_repository_name}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_role_policy" {
  name = "${var.ecr_repository_name}-task-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadDeviceCerts"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = [
          aws_ssm_parameter.perm_cert.arn,
          aws_ssm_parameter.perm_key.arn,
          aws_ssm_parameter.root_ca.arn,
        ]
      },
      {
        Sid      = "UploadVideoClips"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "arn:aws:s3:::${var.s3_bucket_name}/video_streams/*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Security group - outbound-only (IoT Core MQTT/8883/443, S3 + SSM HTTPS/443)
# ---------------------------------------------------------------------------
resource "aws_security_group" "device_runner_task" {
  name        = "${var.ecr_repository_name}-task-sg"
  description = "Outbound-only SG for the device_runner Fargate task"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------
# ECS cluster + Fargate task definition
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "device_runner" {
  name = "${var.ecr_repository_name}-cluster"
}

resource "aws_ecs_task_definition" "device_runner" {
  family                   = var.ecr_repository_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn             = aws_iam_role.ecs_task_role.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "device-runner"
      image     = "${aws_ecr_repository.device_runner.repository_url}:${var.image_tag}"
      essential = true
      environment = [
        { name = "AWS_REGION_NAME", value = var.aws_region },
        { name = "HEADLESS", value = "true" },
        { name = "VIDEO_SOURCE", value = "synthetic" },
        { name = "RUN_DURATION_SECONDS", value = tostring(var.run_duration_seconds) },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.device_runner.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "device-runner"
        }
      }
    }
  ])
}

# ---------------------------------------------------------------------------
# EventBridge Scheduler - kicks off one Fargate RunTask daily. The task
# stops itself after RUN_DURATION_SECONDS (device_runner.py's own watchdog),
# so there's no separate "stop" rule needed - this only handles "start".
# ---------------------------------------------------------------------------
resource "aws_iam_role" "scheduler_invocation_role" {
  name = "${var.ecr_repository_name}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scheduler_invocation_policy" {
  name = "${var.ecr_repository_name}-scheduler-policy"
  role = aws_iam_role.scheduler_invocation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RunDeviceRunnerTask"
        Effect   = "Allow"
        Action   = ["ecs:RunTask"]
        # Trim the ":<revision>" suffix so the permission (and the schedule
        # target below) always resolves to whatever the latest revision is.
        Resource = [trimsuffix(aws_ecs_task_definition.device_runner.arn, ":${aws_ecs_task_definition.device_runner.revision}")]
      },
      {
        Sid      = "PassRolesToECS"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [
          aws_iam_role.ecs_execution_role.arn,
          aws_iam_role.ecs_task_role.arn,
        ]
      }
    ]
  })
}

resource "aws_scheduler_schedule" "daily_device_runner" {
  name = "${var.ecr_repository_name}-daily"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = var.schedule_expression

  target {
    arn      = aws_ecs_cluster.device_runner.arn
    role_arn = aws_iam_role.scheduler_invocation_role.arn

    ecs_parameters {
      task_definition_arn = trimsuffix(aws_ecs_task_definition.device_runner.arn, ":${aws_ecs_task_definition.device_runner.revision}")
      launch_type          = "FARGATE"

      network_configuration {
        assign_public_ip = var.assign_public_ip
        security_groups  = [aws_security_group.device_runner_task.id]
        subnets          = var.subnet_ids
      }
    }

    retry_policy {
      maximum_event_age_in_seconds = 300
      maximum_retry_attempts       = 2
    }
  }
}

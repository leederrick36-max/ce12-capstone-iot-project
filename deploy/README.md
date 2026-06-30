# Running device_runner.py as a daily 8-hour Fargate batch job

## What this is

`device_runner.py` now supports headless/unattended operation (`HEADLESS=true`,
`VIDEO_SOURCE=synthetic`, `RUN_DURATION_SECONDS=28800`). These files package
that into a container and schedule it to run once a day for 8 hours on AWS
ECS Fargate — no servers to patch, and it stops itself (and stops billing)
when the run duration elapses.

Files:
- `../Dockerfile`, `../requirements.txt`, `../entrypoint.sh`, `../fetch_certs.py` — the container image
- `terraform/` — ECR repo, ECS cluster + Fargate task definition, IAM roles, EventBridge Scheduler rule

## One-time setup

### 1. Seed the device certificate into SSM Parameter Store

The container fetches `perm.cert.pem`, `perm.private.key`, and
`AmazonRootCA1.pem` from SSM at startup instead of having them baked into the
image. Push the same files already sitting in this repo (from the prior
local provisioning run) up to SSM once:

```bash
aws ssm put-parameter --name /minipc/perm_cert --type SecureString --overwrite \
  --value "$(cat ../perm.cert.pem)"
aws ssm put-parameter --name /minipc/perm_key --type SecureString --overwrite \
  --value "$(cat ../perm.private.key)"
aws ssm put-parameter --name /minipc/root_ca --type SecureString --overwrite \
  --value "$(cat ../AmazonRootCA1.pem)"
```

(Terraform creates these three parameters as placeholders so IAM has
something to reference, but deliberately never manages their *value* —
that way the private key never sits in Terraform state or a `.tfvars` file.)

### 2. Deploy the infrastructure

```bash
cd terraform
terraform init
terraform apply \
  -var="vpc_id=<your-vpc-id>" \
  -var='subnet_ids=["<subnet-1>","<subnet-2>"]'
```

Adjust `assign_public_ip` to `false` if your subnets route outbound traffic
through a NAT gateway instead of being public subnets with an Internet
Gateway. Either way the task needs a path to the internet — it talks to AWS
IoT Core, S3, and SSM over HTTPS/MQTT.

### 3. Build and push the image

```bash
cd ..
ECR_URL=$(cd deploy/terraform && terraform output -raw ecr_repository_url)
aws ecr get-login-password | docker login --username AWS --password-stdin "${ECR_URL%/*}"
docker build --platform linux/amd64 -t "$ECR_URL:latest" .
docker push "$ECR_URL:latest"
```

The task definition pins `runtime_platform.cpu_architecture = "X86_64"`
(`terraform/main.tf`), so `--platform linux/amd64` is required on the build -
without it, building on an Apple Silicon Mac produces an arm64 image and
Fargate fails to pull it with `CannotPullContainerError: ... does not contain
descriptor matching platform 'linux/amd64'`.

The task definition already points at `<ecr_repo>:latest`, so nothing else
needs to change — the next scheduled run (or a manual test run, below) will
pull this image.

## Testing without waiting for the schedule

```bash
cd deploy/terraform
CLUSTER=$(terraform output -raw ecs_cluster_name)
TASK_DEF=$(terraform output -raw ecs_task_definition_arn)

aws ecs run-task \
  --cluster "$CLUSTER" \
  --task-definition "$TASK_DEF" \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[<subnet-id>],securityGroups=[<sg-id>],assignPublicIp=ENABLED}"
```

Watch it run in CloudWatch Logs under `/ecs/minipc-device-runner`. Telemetry
should start appearing in SiteWise within ~30s; the first video clip uploads
to `s3://minipc-iot-simulation-255945442255/video_streams/` after ~10s.

## Changing the schedule or run length

Both are Terraform variables — re-apply after changing:
- `schedule_expression` — when the daily run starts (default 01:00 UTC / 09:00 SGT)
- `run_duration_seconds` — how long it runs before self-stopping (default 28800 = 8h)

## Swapping synthetic frames for a real recorded clip

Set the task definition's `VIDEO_SOURCE` env var to a file path instead of
`synthetic`, and `COPY` that video file into the image in the Dockerfile.
`device_runner.py` will loop it continuously for the run duration.

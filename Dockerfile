# device_runner.py, containerized for unattended runs (no camera, no display).
# Intended target: AWS ECS Fargate, triggered on a daily schedule for an
# 8-hour batch window (see deploy/terraform).

FROM python:3.12-slim

# opencv-python-headless still needs a couple of shared libs on Debian slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY device_runner.py fetch_certs.py entrypoint.sh ./
RUN chmod +x entrypoint.sh

# Container defaults: headless (no GUI), procedurally generated video feed
# (no camera/file dependency), self-stop after 8 hours. Override any of
# these per-task via the ECS task definition's environment block.
ENV HEADLESS=true
ENV VIDEO_SOURCE=synthetic
ENV RUN_DURATION_SECONDS=28800
ENV AWS_REGION_NAME=ap-southeast-1

ENTRYPOINT ["./entrypoint.sh"]

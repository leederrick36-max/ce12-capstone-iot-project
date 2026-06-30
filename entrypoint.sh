#!/bin/sh
# Container entrypoint: pull cert material from SSM first, then run the agent.
# Splitting this into two steps (instead of doing it inside device_runner.py)
# keeps device_runner.py identical for local/Windows runs and container runs.
set -e

echo "[ENTRYPOINT] Fetching device certificates from SSM Parameter Store..."
python fetch_certs.py

echo "[ENTRYPOINT] Starting device_runner.py..."
exec python device_runner.py

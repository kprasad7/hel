#!/bin/bash
# Vendors the runpod_callback Lambda's one real third-party dependency
# (cramjam, for Snappy-compressing the Prometheus remote_write payload) into
# a deployable package directory. Must run BEFORE `terraform apply`/`plan`
# against infra/aws — Terraform just zips whatever's already in
# services/runpod_callback/build, it doesn't build it (see git history for
# why: a null_resource + local-exec approach broke the moment Terraform
# state moved to a different machine, e.g. a CI runner, since local-exec
# side effects on disk aren't tracked by Terraform state across machines).
set -euo pipefail

cd "$(dirname "$0")/.."

SRC_DIR="services/runpod_callback/build"
rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR/common"

cp services/runpod_callback/handler.py "$SRC_DIR/handler.py"
cp services/common/dynamo.py "$SRC_DIR/common/dynamo.py"
cp services/common/models.py "$SRC_DIR/common/models.py"
cp services/common/remote_write.py "$SRC_DIR/common/remote_write.py"
: > "$SRC_DIR/common/__init__.py"

pip install --platform manylinux2014_x86_64 --implementation cp --python-version 3.12 \
  --only-binary=:all: --target "$SRC_DIR" \
  -r services/runpod_callback/requirements.txt

echo "Built $SRC_DIR"

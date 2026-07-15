#!/bin/bash
# RBGJB Step 02: Register QEMU for cross-platform builds
# Builder: gcr.io/cloud-builders/docker

set -euo pipefail

# Register QEMU for cross-platform builds (arm64, arm/v7)
docker run --privileged --rm "${ZRBF_TOOL_BINFMT}" --install arm64,arm

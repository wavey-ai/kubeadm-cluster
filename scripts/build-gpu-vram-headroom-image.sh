#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/wavey-ai/gpu-vram-headroom:main}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker build \
  -t "$IMAGE" \
  "${ROOT_DIR}/images/gpu-vram-headroom"

docker push "$IMAGE"

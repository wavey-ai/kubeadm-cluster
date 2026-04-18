#!/usr/bin/env bash
set -euo pipefail

: "${NODE_NAME:?set NODE_NAME}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-15}"

query_gpu_field() {
  local field="$1"
  chroot /host /usr/bin/nvidia-smi \
    --query-gpu="${field}" \
    --format=csv,noheader,nounits | head -n1 | tr -d '[:space:]'
}

bool_label() {
  local free_mib="$1"
  local threshold_mib="$2"
  if (( free_mib >= threshold_mib )); then
    printf 'true'
  else
    printf 'false'
  fi
}

while true; do
  total_mib="$(query_gpu_field memory.total)"
  used_mib="$(query_gpu_field memory.used)"
  free_mib="$(query_gpu_field memory.free)"
  gpu_uuid="$(query_gpu_field uuid)"

  kubectl patch node "$NODE_NAME" --type merge -p "$(cat <<EOF
{
  "metadata": {
    "annotations": {
      "wavey.ai/gpu-vram-total-mib": "${total_mib}",
      "wavey.ai/gpu-vram-used-mib": "${used_mib}",
      "wavey.ai/gpu-vram-free-mib": "${free_mib}",
      "wavey.ai/gpu-uuid": "${gpu_uuid}"
    },
    "labels": {
      "wavey.ai/gpu-vram-free-ge-2048mib": "$(bool_label "$free_mib" 2048)",
      "wavey.ai/gpu-vram-free-ge-3072mib": "$(bool_label "$free_mib" 3072)",
      "wavey.ai/gpu-vram-free-ge-4096mib": "$(bool_label "$free_mib" 4096)",
      "wavey.ai/gpu-vram-free-ge-6144mib": "$(bool_label "$free_mib" 6144)",
      "wavey.ai/gpu-vram-free-ge-8192mib": "$(bool_label "$free_mib" 8192)",
      "wavey.ai/gpu-vram-free-ge-12288mib": "$(bool_label "$free_mib" 12288)",
      "wavey.ai/gpu-vram-free-ge-16384mib": "$(bool_label "$free_mib" 16384)"
    }
  }
}
EOF
)" >/dev/null

  sleep "$POLL_INTERVAL_SECONDS"
done

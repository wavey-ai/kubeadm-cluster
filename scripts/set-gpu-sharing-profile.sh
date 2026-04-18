#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <node-name> <default|mps-4|mps-8>" >&2
  exit 1
fi

node_name="$1"
profile="$2"

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

case "$profile" in
  default)
    kubectl label node "$node_name" nvidia.com/device-plugin.config=default --overwrite
    kubectl label node "$node_name" nvidia.com/mps.capable- || true
    ;;
  mps-4|mps-8)
    kubectl label node "$node_name" \
      nvidia.com/device-plugin.config="$profile" \
      nvidia.com/mps.capable=true \
      --overwrite
    ;;
  *)
    echo "unsupported profile: $profile" >&2
    exit 1
    ;;
esac

echo "updated ${node_name} to GPU sharing profile ${profile}"

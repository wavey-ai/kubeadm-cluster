#!/usr/bin/env bash
set -euo pipefail

MANIFESTS_DIR="${MANIFESTS_DIR:-/root/manifests}"
FLANNEL_VERSION="${FLANNEL_VERSION:-v0.28.2}"
HAPROXY_INGRESS_CHART_VERSION="${HAPROXY_INGRESS_CHART_VERSION:-1.49.0}"
NVIDIA_DEVICE_PLUGIN_CHART_VERSION="${NVIDIA_DEVICE_PLUGIN_CHART_VERSION:-0.17.3}"

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <cpu-node-name> <gpu-node-name>" >&2
  exit 1
fi

cpu_node="$1"
gpu_node="$2"

export KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"

kubectl label node "${cpu_node}" wavey.ai/ingress=true wavey.ai/node-role=cpu --overwrite
kubectl label node "${gpu_node}" wavey.ai/gpu=true wavey.ai/node-role=gpu nvidia.com/gpu.present=true --overwrite

kubectl apply -f "https://github.com/flannel-io/flannel/releases/download/${FLANNEL_VERSION}/kube-flannel.yml"
kubectl wait --for=condition=Ready nodes --all --timeout=10m

helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo add haproxytech https://haproxytech.github.io/helm-charts
helm repo update

helm upgrade --install nvidia-device-plugin nvdp/nvidia-device-plugin \
  --namespace nvidia-device-plugin \
  --create-namespace \
  --version "${NVIDIA_DEVICE_PLUGIN_CHART_VERSION}" \
  -f "${MANIFESTS_DIR}/nvidia-device-plugin/values.yaml" \
  --wait \
  --timeout 10m

helm upgrade --install haproxy-ingress haproxytech/kubernetes-ingress \
  --namespace haproxy-controller \
  --create-namespace \
  --version "${HAPROXY_INGRESS_CHART_VERSION}" \
  -f "${MANIFESTS_DIR}/haproxy/values.yaml" \
  --wait \
  --timeout 10m

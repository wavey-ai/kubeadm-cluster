#!/usr/bin/env bash
set -euo pipefail

MANIFESTS_DIR="${MANIFESTS_DIR:-/root/manifests}"
HEADLAMP_NAMESPACE="${HEADLAMP_NAMESPACE:-headlamp}"
HEADLAMP_CHART_VERSION="${HEADLAMP_CHART_VERSION:-0.41.0}"
HEADLAMP_BASIC_AUTH_USER="${HEADLAMP_BASIC_AUTH_USER:-admin}"
HEADLAMP_BASIC_AUTH_HASH="${HEADLAMP_BASIC_AUTH_HASH:-}"
HEADLAMP_TLS_CRT_B64="${HEADLAMP_TLS_CRT_B64:-}"
HEADLAMP_TLS_KEY_B64="${HEADLAMP_TLS_KEY_B64:-}"

if [[ -z "${HEADLAMP_BASIC_AUTH_HASH}" ]]; then
  echo "HEADLAMP_BASIC_AUTH_HASH is required" >&2
  exit 1
fi

if [[ -z "${HEADLAMP_TLS_CRT_B64}" || -z "${HEADLAMP_TLS_KEY_B64}" ]]; then
  echo "HEADLAMP_TLS_CRT_B64 and HEADLAMP_TLS_KEY_B64 are required" >&2
  exit 1
fi

export KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

printf '%s' "${HEADLAMP_TLS_CRT_B64}" | base64 -d > "${tmp_dir}/tls.crt"
printf '%s' "${HEADLAMP_TLS_KEY_B64}" | base64 -d > "${tmp_dir}/tls.key"

kubectl create namespace "${HEADLAMP_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${HEADLAMP_NAMESPACE}" create secret generic headlamp-basic-auth \
  --from-literal="${HEADLAMP_BASIC_AUTH_USER}=${HEADLAMP_BASIC_AUTH_HASH}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${HEADLAMP_NAMESPACE}" create secret tls headlamp-tls \
  --cert="${tmp_dir}/tls.crt" \
  --key="${tmp_dir}/tls.key" \
  --dry-run=client -o yaml | kubectl apply -f -

helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm repo update

helm upgrade --install headlamp headlamp/headlamp \
  --namespace "${HEADLAMP_NAMESPACE}" \
  --version "${HEADLAMP_CHART_VERSION}" \
  -f "${MANIFESTS_DIR}/headlamp/values.yaml" \
  --wait \
  --timeout 10m

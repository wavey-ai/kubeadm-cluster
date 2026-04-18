#!/usr/bin/env bash
set -euo pipefail

MANIFESTS_DIR="${MANIFESTS_DIR:-/root/manifests}"
HEADLAMP_NAMESPACE="${HEADLAMP_NAMESPACE:-headlamp}"
HEADLAMP_CHART_VERSION="${HEADLAMP_CHART_VERSION:-0.41.0}"
HEADLAMP_TLS_CRT_B64="${HEADLAMP_TLS_CRT_B64:-}"
HEADLAMP_TLS_KEY_B64="${HEADLAMP_TLS_KEY_B64:-}"
HEADLAMP_OIDC_SECRET_NAME="${HEADLAMP_OIDC_SECRET_NAME:-headlamp-oidc}"
HEADLAMP_OIDC_CLIENT_ID="${HEADLAMP_OIDC_CLIENT_ID:-}"
HEADLAMP_OIDC_CLIENT_SECRET="${HEADLAMP_OIDC_CLIENT_SECRET:-}"
HEADLAMP_OIDC_ISSUER_URL="${HEADLAMP_OIDC_ISSUER_URL:-}"
HEADLAMP_OIDC_CALLBACK_URL="${HEADLAMP_OIDC_CALLBACK_URL:-https://k8s-us-ord.wavey.io/oidc-callback}"
HEADLAMP_OIDC_SCOPES="${HEADLAMP_OIDC_SCOPES:-openid,email,profile}"
HEADLAMP_OIDC_VALIDATOR_CLIENT_ID="${HEADLAMP_OIDC_VALIDATOR_CLIENT_ID:-${HEADLAMP_OIDC_CLIENT_ID}}"
HEADLAMP_OIDC_VALIDATOR_ISSUER_URL="${HEADLAMP_OIDC_VALIDATOR_ISSUER_URL:-${HEADLAMP_OIDC_ISSUER_URL}}"
HEADLAMP_OIDC_USE_PKCE="${HEADLAMP_OIDC_USE_PKCE:-true}"
HEADLAMP_OIDC_ADMIN_GROUP="${HEADLAMP_OIDC_ADMIN_GROUP:-headlamp:admins}"

if [[ -z "${HEADLAMP_OIDC_CLIENT_ID}" || -z "${HEADLAMP_OIDC_CLIENT_SECRET}" || -z "${HEADLAMP_OIDC_ISSUER_URL}" ]]; then
  echo "HEADLAMP_OIDC_CLIENT_ID, HEADLAMP_OIDC_CLIENT_SECRET, and HEADLAMP_OIDC_ISSUER_URL are required" >&2
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

kubectl -n "${HEADLAMP_NAMESPACE}" delete secret headlamp-basic-auth --ignore-not-found

kubectl -n "${HEADLAMP_NAMESPACE}" create secret generic "${HEADLAMP_OIDC_SECRET_NAME}" \
  --from-literal=OIDC_CLIENT_ID="${HEADLAMP_OIDC_CLIENT_ID}" \
  --from-literal=OIDC_CLIENT_SECRET="${HEADLAMP_OIDC_CLIENT_SECRET}" \
  --from-literal=OIDC_ISSUER_URL="${HEADLAMP_OIDC_ISSUER_URL}" \
  --from-literal=OIDC_SCOPES="${HEADLAMP_OIDC_SCOPES}" \
  --from-literal=OIDC_CALLBACK_URL="${HEADLAMP_OIDC_CALLBACK_URL}" \
  --from-literal=OIDC_VALIDATOR_CLIENT_ID="${HEADLAMP_OIDC_VALIDATOR_CLIENT_ID}" \
  --from-literal=OIDC_VALIDATOR_ISSUER_URL="${HEADLAMP_OIDC_VALIDATOR_ISSUER_URL}" \
  --from-literal=OIDC_USE_PKCE="${HEADLAMP_OIDC_USE_PKCE}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${HEADLAMP_NAMESPACE}" create secret tls headlamp-tls \
  --cert="${tmp_dir}/tls.crt" \
  --key="${tmp_dir}/tls.key" \
  --dry-run=client -o yaml | kubectl apply -f -

if [[ -n "${HEADLAMP_OIDC_ADMIN_GROUP}" ]]; then
  cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: headlamp-oidc-admins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: Group
    name: ${HEADLAMP_OIDC_ADMIN_GROUP}
    apiGroup: rbac.authorization.k8s.io
EOF
fi

helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm repo update

helm upgrade --install headlamp headlamp/headlamp \
  --namespace "${HEADLAMP_NAMESPACE}" \
  --version "${HEADLAMP_CHART_VERSION}" \
  -f "${MANIFESTS_DIR}/headlamp/values.yaml" \
  --wait \
  --timeout 10m

if [[ -f "${MANIFESTS_DIR}/headlamp/login-service.yaml" ]]; then
  kubectl apply -f "${MANIFESTS_DIR}/headlamp/login-service.yaml"
fi

if [[ -f "${MANIFESTS_DIR}/headlamp/login-ingress.yaml" ]]; then
  kubectl apply -f "${MANIFESTS_DIR}/headlamp/login-ingress.yaml"
fi

#!/usr/bin/env bash
set -euo pipefail

KUBE_APISERVER_MANIFEST="${KUBE_APISERVER_MANIFEST:-/etc/kubernetes/manifests/kube-apiserver.yaml}"
OIDC_ISSUER_URL="${OIDC_ISSUER_URL:-}"
OIDC_CLIENT_ID="${OIDC_CLIENT_ID:-}"
OIDC_USERNAME_CLAIM="${OIDC_USERNAME_CLAIM:-email}"
OIDC_USERNAME_PREFIX="${OIDC_USERNAME_PREFIX:--}"
OIDC_GROUPS_CLAIM="${OIDC_GROUPS_CLAIM:-groups}"
OIDC_GROUPS_PREFIX="${OIDC_GROUPS_PREFIX:--}"
OIDC_SIGNING_ALGS="${OIDC_SIGNING_ALGS:-ES256}"

if [[ -z "${OIDC_ISSUER_URL}" || -z "${OIDC_CLIENT_ID}" ]]; then
  echo "OIDC_ISSUER_URL and OIDC_CLIENT_ID are required" >&2
  exit 1
fi

if [[ ! -f "${KUBE_APISERVER_MANIFEST}" ]]; then
  echo "missing kube-apiserver manifest: ${KUBE_APISERVER_MANIFEST}" >&2
  exit 1
fi

backup="${KUBE_APISERVER_MANIFEST}.$(date +%Y%m%d%H%M%S).bak"
cp "${KUBE_APISERVER_MANIFEST}" "${backup}"

tmp_manifest="$(mktemp)"
if ! awk \
  -v oidc_issuer_url="${OIDC_ISSUER_URL}" \
  -v oidc_client_id="${OIDC_CLIENT_ID}" \
  -v oidc_username_claim="${OIDC_USERNAME_CLAIM}" \
  -v oidc_username_prefix="${OIDC_USERNAME_PREFIX}" \
  -v oidc_groups_claim="${OIDC_GROUPS_CLAIM}" \
  -v oidc_groups_prefix="${OIDC_GROUPS_PREFIX}" \
  -v oidc_signing_algs="${OIDC_SIGNING_ALGS}" '
  BEGIN {
    inserted = 0
  }
  /^[[:space:]]*- --oidc-/ {
    next
  }
  {
    print $0
    if ($0 ~ /^[[:space:]]*- --secure-port=6443$/) {
      print "    - --oidc-issuer-url=" oidc_issuer_url
      print "    - --oidc-client-id=" oidc_client_id
      print "    - --oidc-username-claim=" oidc_username_claim
      print "    - --oidc-username-prefix=" oidc_username_prefix
      print "    - --oidc-groups-claim=" oidc_groups_claim
      print "    - --oidc-groups-prefix=" oidc_groups_prefix
      print "    - --oidc-signing-algs=" oidc_signing_algs
      inserted = 1
    }
  }
  END {
    if (!inserted) {
      exit 42
    }
  }
' "${KUBE_APISERVER_MANIFEST}" > "${tmp_manifest}"; then
  rm -f "${tmp_manifest}"
  echo "could not find kube-apiserver secure-port flag to anchor OIDC insertion" >&2
  exit 1
fi

install -m 600 "${tmp_manifest}" "${KUBE_APISERVER_MANIFEST}"
rm -f "${tmp_manifest}"

echo "updated ${KUBE_APISERVER_MANIFEST} (backup: ${backup})"

for _ in $(seq 1 60); do
  if kubectl --kubeconfig=/root/.kube/config get --raw=/readyz >/dev/null 2>&1; then
    echo "kube-apiserver is ready"
    exit 0
  fi
  sleep 2
done

echo "kube-apiserver did not become ready in time" >&2
exit 1

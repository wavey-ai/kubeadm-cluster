#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform"
TMP_DIR="${ROOT_DIR}/rendered"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require_cmd terraform
require_cmd jq
require_cmd ssh
require_cmd scp

mkdir -p "${TMP_DIR}"

cp_public="$(terraform -chdir="${TF_DIR}" output -json control_plane | jq -r '.public_ip')"
cp_private="$(terraform -chdir="${TF_DIR}" output -json control_plane | jq -r '.private_ip')"
cp_label="$(terraform -chdir="${TF_DIR}" output -json control_plane | jq -r '.label')"
cpu_public="$(terraform -chdir="${TF_DIR}" output -json cpu_worker | jq -r '.public_ip')"
cpu_private="$(terraform -chdir="${TF_DIR}" output -json cpu_worker | jq -r '.private_ip')"
cpu_label="$(terraform -chdir="${TF_DIR}" output -json cpu_worker | jq -r '.label')"
gpu_public="$(terraform -chdir="${TF_DIR}" output -json gpu_worker | jq -r '.public_ip')"
gpu_label="$(terraform -chdir="${TF_DIR}" output -json gpu_worker | jq -r '.label')"
gpu_worker_image="$(terraform -chdir="${TF_DIR}" output -raw gpu_worker_image)"
gpu_worker_bootstrap_mode="$(terraform -chdir="${TF_DIR}" output -raw gpu_worker_bootstrap_mode)"
pod_cidr="$(terraform -chdir="${TF_DIR}" output -raw pod_cidr)"
service_cidr="$(terraform -chdir="${TF_DIR}" output -raw service_cidr)"
local_registry_port="${LOCAL_REGISTRY_PORT:-5000}"
oidc_issuer_url="${OIDC_ISSUER_URL:-}"
oidc_client_id="${OIDC_CLIENT_ID:-}"
oidc_username_claim="${OIDC_USERNAME_CLAIM:-email}"
oidc_username_prefix="${OIDC_USERNAME_PREFIX:--}"
oidc_groups_claim="${OIDC_GROUPS_CLAIM:-groups}"
oidc_groups_prefix="${OIDC_GROUPS_PREFIX:--}"
oidc_signing_algs="${OIDC_SIGNING_ALGS:-ES256}"

copy_scripts() {
  local host="$1"
  scp -o StrictHostKeyChecking=accept-new \
    "${ROOT_DIR}/scripts/install-arch-base.sh" \
    "${ROOT_DIR}/scripts/configure-containerd-local-registry.sh" \
    "${ROOT_DIR}/scripts/install-gpu-node.sh" \
    "${ROOT_DIR}/scripts/install-cluster-addons.sh" \
    "${ROOT_DIR}/scripts/install-headlamp.sh" \
    root@"${host}":/root/
}

wait_ssh() {
  local host="$1"
  for _ in $(seq 1 60); do
    if ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 root@"${host}" "echo ready" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  echo "host not reachable over ssh: ${host}" >&2
  exit 1
}

ensure_kernel_modules_present() {
  local host="$1"
  if ! ssh -o StrictHostKeyChecking=accept-new root@"${host}" 'test -d "/lib/modules/$(uname -r)"'; then
    reboot_and_wait "${host}"
  fi
}

reboot_and_wait() {
  local host="$1"
  ssh root@"${host}" "systemctl reboot" >/dev/null 2>&1 || true
  sleep 10
  wait_ssh "${host}"
}

run_remote_step() {
  local host="$1"
  shift

  if ssh root@"${host}" "$@"; then
    return 0
  fi

  wait_ssh "${host}"
  ssh root@"${host}" "$@"
}

for host in "${cp_public}" "${cpu_public}" "${gpu_public}"; do
  wait_ssh "${host}"
  ensure_kernel_modules_present "${host}"
  copy_scripts "${host}"
done

run_remote_step "${cp_public}" "WAVEY_LOCAL_REGISTRY_HOST=${cpu_private} WAVEY_LOCAL_REGISTRY_PORT=${local_registry_port} bash /root/install-arch-base.sh control-plane ${cp_label}"
run_remote_step "${cpu_public}" "WAVEY_LOCAL_REGISTRY_HOST=${cpu_private} WAVEY_LOCAL_REGISTRY_PORT=${local_registry_port} bash /root/install-arch-base.sh cpu-worker ${cpu_label}"
gpu_arch_base_prefix=""
if [[ "${gpu_worker_bootstrap_mode}" == "prebaked" ]]; then
  gpu_arch_base_prefix="WAVEY_SKIP_FULL_UPGRADE=1 "
fi
run_remote_step "${gpu_public}" "WAVEY_LOCAL_REGISTRY_HOST=${cpu_private} WAVEY_LOCAL_REGISTRY_PORT=${local_registry_port} ${gpu_arch_base_prefix}bash /root/install-arch-base.sh gpu-worker ${gpu_label}"

run_remote_step "${gpu_public}" "bash /root/install-gpu-node.sh ${gpu_worker_bootstrap_mode}"
if [[ "${gpu_worker_bootstrap_mode}" == "full" ]]; then
  reboot_and_wait "${gpu_public}"
fi

cat > "${TMP_DIR}/kubeadm-init.yaml" <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${cp_private}
  bindPort: 6443
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
networking:
  podSubnet: ${pod_cidr}
  serviceSubnet: ${service_cidr}
apiServer:
  certSANs:
    - ${cp_public}
EOF

if [[ -n "${oidc_issuer_url}" && -n "${oidc_client_id}" ]]; then
  cat >> "${TMP_DIR}/kubeadm-init.yaml" <<EOF
  extraArgs:
    oidc-issuer-url: ${oidc_issuer_url}
    oidc-client-id: ${oidc_client_id}
    oidc-username-claim: ${oidc_username_claim}
    oidc-username-prefix: "${oidc_username_prefix}"
    oidc-groups-claim: ${oidc_groups_claim}
    oidc-groups-prefix: "${oidc_groups_prefix}"
    oidc-signing-algs: ${oidc_signing_algs}
EOF
fi

scp -o StrictHostKeyChecking=accept-new "${TMP_DIR}/kubeadm-init.yaml" root@"${cp_public}":/root/kubeadm-init.yaml
run_remote_step "${cp_public}" "kubeadm init --config=/root/kubeadm-init.yaml" | tee "${TMP_DIR}/kubeadm-init.log"
ssh root@"${cp_public}" "mkdir -p /root/.kube && cp /etc/kubernetes/admin.conf /root/.kube/config"
run_remote_step "${cp_public}" "kubeadm token create --print-join-command" > "${TMP_DIR}/join.sh"
chmod +x "${TMP_DIR}/join.sh"

join_cmd="$(cat "${TMP_DIR}/join.sh")"
run_remote_step "${cpu_public}" "${join_cmd}"
run_remote_step "${gpu_public}" "${join_cmd}"

scp -o StrictHostKeyChecking=accept-new -r \
  "${ROOT_DIR}/manifests" \
  root@"${cp_public}":/root/manifests
run_remote_step "${cp_public}" "bash /root/install-cluster-addons.sh ${cpu_label} ${gpu_label}"

scp -o StrictHostKeyChecking=accept-new \
  root@"${cp_public}":/etc/kubernetes/admin.conf \
  "${TMP_DIR}/admin.conf"
sed "s#${cp_private}:6443#${cp_public}:6443#g" "${TMP_DIR}/admin.conf" > "${TMP_DIR}/kubeconfig"

echo "Cluster bootstrap complete."
echo "Control plane label: ${cp_label}"
echo "Control plane: ${cp_public}"
echo "CPU worker: ${cpu_public}"
echo "GPU worker: ${gpu_public}"
echo "GPU worker image: ${gpu_worker_image}"
echo "GPU worker bootstrap mode: ${gpu_worker_bootstrap_mode}"
echo "Local registry mirror: ${cpu_private}:${local_registry_port}"
echo "Local kubeconfig: ${TMP_DIR}/kubeconfig"

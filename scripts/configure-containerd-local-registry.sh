#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <registry-host> [registry-port]" >&2
  exit 1
fi

registry_host="$1"
registry_port="${2:-5000}"
registry_addr="${registry_host}:${registry_port}"
certs_dir="/etc/containerd/certs.d"
config_file="/etc/containerd/config.toml"

mkdir -p \
  "${certs_dir}" \
  "${certs_dir}/ghcr.io" \
  "${certs_dir}/${registry_addr}"

cat >"${certs_dir}/ghcr.io/hosts.toml" <<EOF
server = "https://ghcr.io"

[host."http://${registry_addr}"]
  capabilities = ["pull", "resolve"]
  skip_verify = true

[host."https://ghcr.io"]
  capabilities = ["pull", "resolve"]
EOF

cat >"${certs_dir}/${registry_addr}/hosts.toml" <<EOF
server = "http://${registry_addr}"

[host."http://${registry_addr}"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
EOF

sed -i \
  -e "s|config_path = ''|config_path = '${certs_dir}'|" \
  -e "s|config_path = \"\"|config_path = \"${certs_dir}\"|" \
  "${config_file}"

if systemctl is-active --quiet containerd; then
  systemctl restart containerd
fi

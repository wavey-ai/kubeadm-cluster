#!/usr/bin/env bash
set -euo pipefail

role="${1:-generic}"

private_ipv4() {
  ip -4 -o addr show scope global \
    | awk '{print $4}' \
    | cut -d/ -f1 \
    | awk '/^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)/ { print; exit }'
}

node_ip="$(private_ipv4 || true)"
if [[ -z "${node_ip}" ]]; then
  echo "failed to detect private IPv4 address" >&2
  exit 1
fi

swapoff -a || true
sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab

cat >/etc/modules-load.d/wavey-k8s.conf <<'EOF'
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/99-wavey-k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
vm.max_map_count = 262144
EOF

sysctl --system

pacman -Sy --noconfirm archlinux-keyring
pacman -S --needed --noconfirm \
  base-devel \
  ca-certificates \
  containerd \
  conntrack-tools \
  cni-plugins \
  curl \
  ethtool \
  git \
  helm \
  htop \
  iptables \
  jq \
  kubeadm \
  kubectl \
  kubelet \
  nftables \
  openssh \
  rsync \
  socat \
  tar

mkdir -p /etc/containerd /etc/default
cat >/etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
cat >/etc/default/kubelet <<EOF
KUBELET_EXTRA_ARGS=--node-ip=${node_ip}
EOF

systemctl enable --now systemd-timesyncd
systemctl enable --now containerd
systemctl enable kubelet

echo "${role}" >/etc/wavey-k8s-role

#!/usr/bin/env bash
set -euo pipefail

role="${1:-generic}"
node_name="${2:-}"
skip_full_upgrade="${WAVEY_SKIP_FULL_UPGRADE:-0}"

cat >/etc/pacman.d/mirrorlist <<'EOF'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.theash.xyz/arch/$repo/os/$arch
Server = https://america.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
EOF

private_ipv4() {
  ip -4 -o addr show scope global \
    | awk '{print $4}' \
    | cut -d/ -f1 \
    | awk '/^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)/ { print; exit }'
}

load_required_module() {
  local module="$1"

  if modprobe "${module}" >/dev/null 2>&1; then
    return 0
  fi

  case "${module}" in
    overlay)
      grep -qw overlay /proc/filesystems && return 0
      ;;
    br_netfilter)
      sysctl net.bridge.bridge-nf-call-iptables >/dev/null 2>&1 && return 0
      ;;
  esac

  echo "required kernel module unavailable: ${module}" >&2
  exit 1
}

node_ip="$(private_ipv4 || true)"
if [[ -z "${node_ip}" ]]; then
  echo "failed to detect private IPv4 address" >&2
  exit 1
fi

if [[ -n "${node_name}" ]]; then
  hostnamectl set-hostname "${node_name}"
  cat >/etc/hosts <<EOF
127.0.0.1 localhost
::1 localhost
${node_ip} ${node_name}
EOF
fi

swapoff -a || true
sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab

cat >/etc/modules-load.d/wavey-k8s.conf <<'EOF'
overlay
br_netfilter
EOF

load_required_module overlay
load_required_module br_netfilter

cat >/etc/sysctl.d/99-wavey-k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
vm.max_map_count = 262144
EOF

sysctl --system

pacman -Sy --noconfirm archlinux-keyring
if [[ "${skip_full_upgrade}" != "1" ]]; then
  rm -rf /usr/lib/firmware/nvidia
  pacman -Syu --noconfirm
fi
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
  libseccomp \
  nftables \
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
systemctl disable --now sshd.socket || true
systemctl enable --now sshd.service
systemctl restart sshd.service || true
systemctl enable --now containerd
systemctl enable kubelet

echo "${role}" >/etc/wavey-k8s-role

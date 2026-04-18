#!/usr/bin/env bash
set -euo pipefail

cat >/etc/pacman.d/mirrorlist <<'EOF'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.theash.xyz/arch/$repo/os/$arch
Server = https://america.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
EOF

pacman -Sy --noconfirm archlinux-keyring
rm -rf /usr/lib/firmware/nvidia
pacman -S --needed --noconfirm \
  binutils \
  cuda \
  dkms \
  linux \
  linux-headers \
  nvidia-container-toolkit \
  nvidia-open-dkms \
  nvidia-utils

mkdir -p /etc/systemd/system/nvidia-persistenced.service.d
cat >/etc/systemd/system/nvidia-persistenced.service.d/override.conf <<'EOF'
[Unit]
ConditionPathExists=/dev/nvidiactl
After=multi-user.target

[Service]
ExecStart=
ExecStart=/usr/bin/nvidia-persistenced --user root
Restart=on-failure
RestartSec=2
EOF

systemctl daemon-reload
systemctl enable --now nvidia-persistenced || true
nvidia-ctk runtime configure --runtime=containerd --set-as-default
systemctl restart containerd

if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi -pm 1 || true
  nvidia-smi || true
fi

if command -v nvidia-cuda-mps-control >/dev/null 2>&1; then
  echo "MPS runtime is available on this host"
fi

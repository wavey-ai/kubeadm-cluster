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

systemctl enable nvidia-persistenced || true
nvidia-ctk runtime configure --runtime=containerd --set-as-default
systemctl restart containerd

if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi || true
fi

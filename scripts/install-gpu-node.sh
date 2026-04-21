#!/usr/bin/env bash
set -euo pipefail

mode="${1:-full}"

die() {
  echo "$*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || {
    die "missing required command for GPU bootstrap mode '${mode}': ${cmd}"
  }
}

configure_arch_mirrors() {
  cat >/etc/pacman.d/mirrorlist <<'EOF'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.theash.xyz/arch/$repo/os/$arch
Server = https://america.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
EOF
}

install_gpu_stack() {
  configure_arch_mirrors
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
}

verify_prebaked_gpu_stack() {
  require_cmd modprobe
  require_cmd nvidia-ctk
  require_cmd nvidia-smi

  modprobe nvidia || true
  modprobe nvidia_uvm || true
  modprobe nvidia_modeset || true

  if [[ ! -e /dev/nvidiactl ]]; then
    die "prebaked GPU image is missing /dev/nvidiactl; verify the NVIDIA driver is installed and loaded before cluster bootstrap"
  fi
}

configure_persistenced() {
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
}

configure_containerd_runtime() {
  require_cmd nvidia-ctk
  nvidia-ctk runtime configure --runtime=containerd --set-as-default
  systemctl restart containerd
}

case "${mode}" in
  full)
    install_gpu_stack
    ;;
  prebaked)
    verify_prebaked_gpu_stack
    ;;
  *)
    die "unsupported GPU bootstrap mode: ${mode}"
    ;;
esac

configure_persistenced
configure_containerd_runtime

echo "${mode}" >/etc/wavey-gpu-bootstrap-mode

if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi -pm 1 || true
  nvidia-smi || true
fi

if command -v nvidia-cuda-mps-control >/dev/null 2>&1; then
  echo "MPS runtime is available on this host"
fi

if [[ -d /opt/tensorrt ]]; then
  echo "TensorRT host runtime detected at /opt/tensorrt"
fi

if [[ -d /opt/onnxruntime-trt ]]; then
  echo "ONNX Runtime TensorRT host bundle detected at /opt/onnxruntime-trt"
fi

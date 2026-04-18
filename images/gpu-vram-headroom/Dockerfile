FROM archlinux:base

RUN pacman -Sy --noconfirm archlinux-keyring && \
    pacman -S --needed --noconfirm \
      bash \
      ca-certificates \
      coreutils \
      kubectl && \
    pacman -Scc --noconfirm

COPY operator.sh /usr/local/bin/gpu-vram-headroom

RUN chmod +x /usr/local/bin/gpu-vram-headroom

ENTRYPOINT ["/usr/local/bin/gpu-vram-headroom"]

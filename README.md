# kubeadm-cluster

Minimal all-Arch self-managed Kubernetes on Linode for Wavey workloads.

Current target shape:

- `1 x` control plane: `g8-dedicated-4-2`
- `1 x` CPU worker: `g8-dedicated-4-2`
- `1 x` GPU worker: `g2-gpu-rtx4000a1-s`

This repo owns:

- Linode infrastructure via Terraform
- Arch host bootstrap for Kubernetes nodes
- kubeadm cluster bring-up
- GPU node preparation for NVIDIA workloads
- per-node NVIDIA sharing profiles, including MPS
- GPU VRAM headroom labeling for scheduler-facing placement
- HAProxy ingress on the CPU worker
- local OCI registry on the CPU worker for Wavey images
- NVIDIA device plugin installation on the GPU worker

It does not own application code.

## Layout

- `terraform/`: Linode instances, firewalls, and outputs
- `scripts/`: reproducible host bootstrap and cluster bring-up
- `cloud-init/`: reserved for future first-boot host customization
- `manifests/`: cluster add-ons such as HAProxy ingress
- `docs/`: architecture and operational notes

## Contract

1. Fill in `terraform/terraform.tfvars`
2. `make terraform-init`
3. `make terraform-apply`
4. `make bootstrap`

The first phase provisions and boots a minimal kubeadm cluster. The bootstrap phase:

- upgrades and prepares all Arch nodes
- configures the NVIDIA runtime on the GPU node
- either installs the NVIDIA/CUDA stack on the GPU node or validates a prebaked GPU image
- initializes kubeadm
- joins the CPU and GPU workers
- installs Flannel
- installs the local registry on the CPU worker
- installs the NVIDIA device plugin
- installs the GPU VRAM headroom operator
- installs HAProxy ingress as a DaemonSet bound to the CPU worker host ports

## Node OS

Control plane and CPU workers use `var.image`, which defaults to `linode/arch`.

The GPU worker uses:

- `var.image` by default
- `var.gpu_worker_image` when you want a dedicated prebaked GPU image

That is intentional:

- control plane: Arch
- CPU worker: Arch
- GPU worker: Arch

This increases operational risk relative to a slower-moving distro, but it keeps the entire stack aligned with the chosen host baseline.

## Custom GPU Images

The repo supports a prebaked GPU worker image for CUDA, TensorRT, and ONNX Runtime host stacks.

Terraform knobs:

- `gpu_worker_image`: optional private Linode image slug for the GPU worker
- `gpu_worker_bootstrap_mode = "full"`: install the NVIDIA/CUDA stack from packages on first boot
- `gpu_worker_bootstrap_mode = "prebaked"`: assume the image already contains that stack and only verify it plus wire the NVIDIA container runtime into containerd

Typical flow:

1. Build and validate a GPU host image out of band.
2. Cut a private Linode image from that host with [`scripts/create-linode-image.sh`](scripts/create-linode-image.sh).
3. Set `gpu_worker_image` and `gpu_worker_bootstrap_mode = "prebaked"` in `terraform.tfvars`.
4. Run `make terraform-apply` and `make bootstrap`.

In prebaked mode the cluster bootstrap still runs the normal Kubernetes host preparation from `install-arch-base.sh`; it only skips reinstalling the NVIDIA/CUDA packages on the GPU worker.

## Local Registry

The cluster runs a single internal registry on the CPU worker at `http://<cpu-private-ip>:5000`.

Bootstrap wires containerd on every node to consult that registry first for `ghcr.io` image pulls. The registry is meant to hold Wavey images that have been seeded or pushed there already; it is not a transparent proxy for arbitrary registries.

Current behavior:

- `ghcr.io` lookups check the CPU worker registry first
- if the image is present locally, nodes pull it without going back to GHCR
- if the image is not present locally, containerd falls back to `ghcr.io`

This removes fresh-node dependence on GHCR once the required Wavey images have been seeded into the local registry.

## Pinned Add-ons

- Flannel: `v0.28.2`
- NVIDIA device plugin chart: `0.17.3`
- HAProxy ingress chart: `1.49.0`

## GPU Sharing Profiles

The NVIDIA device plugin is installed with four per-node profiles:

- `default`
- `mps-2`
- `mps-4`
- `mps-8`

Use [`scripts/set-gpu-sharing-profile.sh`](scripts/set-gpu-sharing-profile.sh) to switch a node:

```bash
KUBECONFIG=~/.kube/config ./scripts/set-gpu-sharing-profile.sh wavey-kubeadm-gpu-01 mps-2
```

That works by setting `nvidia.com/device-plugin.config` on the target node. MPS is opt-in per node; the cluster does not force every GPU node into shared mode by default. Shared profiles keep the advertised resource name as `nvidia.com/gpu`, so workloads do not need a separate `.shared` resource key.

## GPU VRAM Headroom Labels

The `gpu-vram-headroom` DaemonSet runs on GPU nodes and patches live headroom labels onto each node:

- `wavey.ai/gpu-vram-free-ge-2048mib`
- `wavey.ai/gpu-vram-free-ge-3072mib`
- `wavey.ai/gpu-vram-free-ge-4096mib`
- `wavey.ai/gpu-vram-free-ge-6144mib`
- `wavey.ai/gpu-vram-free-ge-8192mib`
- `wavey.ai/gpu-vram-free-ge-12288mib`
- `wavey.ai/gpu-vram-free-ge-16384mib`

It also writes exact values as node annotations:

- `wavey.ai/gpu-vram-total-mib`
- `wavey.ai/gpu-vram-used-mib`
- `wavey.ai/gpu-vram-free-mib`
- `wavey.ai/gpu-uuid`

GPU workloads can use those labels in node affinity to require sufficient free VRAM headroom before they land on a node.

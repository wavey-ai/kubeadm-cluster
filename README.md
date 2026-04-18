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
- NVIDIA device plugin installation on the GPU worker

It does not own application code.

## Layout

- `terraform/`: Linode instances, firewalls, and outputs
- `scripts/`: reproducible host bootstrap and cluster bring-up
- `cloud-init/`: reserved for future custom-image bootstrapping
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
- installs CUDA userland and MPS-capable tooling on the GPU node
- initializes kubeadm
- joins the CPU and GPU workers
- installs Flannel
- installs the NVIDIA device plugin
- installs the GPU VRAM headroom operator
- installs HAProxy ingress as a DaemonSet bound to the CPU worker host ports

## Node OS

All nodes use `linode/arch`.

That is intentional:

- control plane: Arch
- CPU worker: Arch
- GPU worker: Arch

This increases operational risk relative to a slower-moving distro, but it keeps the entire stack aligned with the chosen host baseline.

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

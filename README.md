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
- initializes kubeadm
- joins the CPU and GPU workers
- installs Flannel
- installs the NVIDIA device plugin
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

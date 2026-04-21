# Architecture

## Minimal Topology

- control plane node
  - public IP
  - private IP
  - runs kube-apiserver, etcd, scheduler, controller-manager
- CPU worker node
  - public IP
  - private IP
  - intended for ingress and CPU-side app services
- GPU worker node
  - public IP
  - private IP
  - intended for GPU workloads only

## Networking

- public ingress lands directly on the CPU worker public IP
- HAProxy ingress binds `80/443` via host ports on the CPU worker
- east-west traffic uses Linode private IPs
- control plane API is exposed only as much as kubeadm requires

## GPU Strategy

The GPU node supports two bootstrap modes:

- `full`
  - installs Arch kernel headers
  - installs the NVIDIA driver
  - installs CUDA userland
  - installs the NVIDIA container toolkit
- `prebaked`
  - assumes the GPU image already contains the NVIDIA and CUDA stack
  - verifies the host runtime is present
  - rewires containerd to use the NVIDIA runtime without reinstalling packages

The node is prepared for standard full-GPU scheduling:

- the host runtime is configured for NVIDIA containers
- the cluster bootstrap installs the NVIDIA device plugin
- no MPS sharing or custom GPU scheduler is assumed in this repo

## Labels

- control plane: no special scheduling labels
- CPU worker:
  - `wavey.ai/ingress=true`
  - `wavey.ai/node-role=cpu`
- GPU worker:
  - `wavey.ai/gpu=true`
  - `wavey.ai/node-role=gpu`
  - `nvidia.com/gpu.present=true`

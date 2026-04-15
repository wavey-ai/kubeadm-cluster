variable "linode_token" {
  description = "Linode API token. Leave empty to use LINODE_TOKEN from the environment."
  type        = string
  default     = ""
  sensitive   = true
}

variable "cluster_name" {
  description = "Cluster name prefix."
  type        = string
  default     = "wavey-kubeadm"
}

variable "region" {
  description = "Linode region."
  type        = string
}

variable "image" {
  description = "Linode image slug."
  type        = string
  default     = "linode/arch"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key for created hosts."
  type        = string
}

variable "admin_ipv4_cidrs" {
  description = "IPv4 CIDRs allowed to SSH and reach the kube API."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags."
  type        = list(string)
  default     = ["wavey", "kubeadm"]
}

variable "control_plane_type" {
  description = "Linode type for the control plane."
  type        = string
  default     = "g8-dedicated-4-2"
}

variable "cpu_worker_type" {
  description = "Linode type for the CPU worker."
  type        = string
  default     = "g8-dedicated-4-2"
}

variable "gpu_worker_type" {
  description = "Linode type for the GPU worker."
  type        = string
  default     = "g2-gpu-rtx4000a1-s"
}

variable "pod_cidr" {
  description = "Pod CIDR for kubeadm init."
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "Service CIDR for kubeadm init."
  type        = string
  default     = "10.96.0.0/12"
}

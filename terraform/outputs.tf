output "root_password" {
  description = "Generated root password for newly created hosts."
  value       = random_password.root_pass.result
  sensitive   = true
}

output "control_plane" {
  value = {
    label      = linode_instance.control_plane.label
    public_ip  = tolist(linode_instance.control_plane.ipv4)[0]
    private_ip = linode_instance.control_plane.private_ip_address
  }
}

output "cpu_worker" {
  value = {
    label      = linode_instance.cpu_worker.label
    public_ip  = tolist(linode_instance.cpu_worker.ipv4)[0]
    private_ip = linode_instance.cpu_worker.private_ip_address
  }
}

output "gpu_worker" {
  value = {
    label      = linode_instance.gpu_worker.label
    public_ip  = tolist(linode_instance.gpu_worker.ipv4)[0]
    private_ip = linode_instance.gpu_worker.private_ip_address
  }
}

output "pod_cidr" {
  value = var.pod_cidr
}

output "service_cidr" {
  value = var.service_cidr
}

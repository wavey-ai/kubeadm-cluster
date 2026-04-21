provider "linode" {
  token = var.linode_token != "" ? var.linode_token : null
}

locals {
  common_tags      = concat(var.tags, ["cluster:${var.cluster_name}"])
  ssh_public_key   = trimspace(file(var.ssh_public_key_path))
  gpu_worker_image = trimspace(var.gpu_worker_image) != "" ? trimspace(var.gpu_worker_image) : var.image
  private_cidrs = [
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
  ]
}

resource "random_password" "root_pass" {
  length           = 24
  special          = true
  override_special = "_%@"
}

resource "linode_instance" "control_plane" {
  label           = "${var.cluster_name}-cp-01"
  region          = var.region
  image           = var.image
  type            = var.control_plane_type
  root_pass       = random_password.root_pass.result
  authorized_keys = [local.ssh_public_key]
  private_ip      = true
  booted          = true
  backups_enabled = false
  tags            = concat(local.common_tags, ["role:control-plane"])
}

resource "linode_instance" "cpu_worker" {
  label           = "${var.cluster_name}-cpu-01"
  region          = var.region
  image           = var.image
  type            = var.cpu_worker_type
  root_pass       = random_password.root_pass.result
  authorized_keys = [local.ssh_public_key]
  private_ip      = true
  booted          = true
  backups_enabled = false
  tags            = concat(local.common_tags, ["role:cpu"])
}

resource "linode_instance" "gpu_worker" {
  label           = "${var.cluster_name}-gpu-01"
  region          = var.region
  image           = local.gpu_worker_image
  type            = var.gpu_worker_type
  root_pass       = random_password.root_pass.result
  authorized_keys = [local.ssh_public_key]
  private_ip      = true
  booted          = true
  backups_enabled = false
  tags            = concat(local.common_tags, ["role:gpu"])
}

resource "linode_firewall" "control_plane" {
  label   = "${var.cluster_name}-cp-fw"
  tags    = concat(local.common_tags, ["firewall:control-plane"])
  linodes = [linode_instance.control_plane.id]

  inbound {
    label    = "allow-ssh-admin"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22"
    ipv4     = var.admin_ipv4_cidrs
  }

  inbound {
    label    = "allow-kubeapi-admin"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "6443"
    ipv4     = concat(var.admin_ipv4_cidrs, local.private_cidrs)
  }

  inbound {
    label    = "allow-private-control-plane"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "1-65535"
    ipv4     = local.private_cidrs
  }

  inbound {
    label    = "allow-private-udp"
    action   = "ACCEPT"
    protocol = "UDP"
    ports    = "1-65535"
    ipv4     = local.private_cidrs
  }

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"
}

resource "linode_firewall" "cpu_worker" {
  label   = "${var.cluster_name}-cpu-fw"
  tags    = concat(local.common_tags, ["firewall:cpu"])
  linodes = [linode_instance.cpu_worker.id]

  inbound {
    label    = "allow-ssh-admin"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22"
    ipv4     = var.admin_ipv4_cidrs
  }

  inbound {
    label    = "allow-public-http"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "80"
    ipv4     = ["0.0.0.0/0"]
  }

  inbound {
    label    = "allow-public-https"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "443"
    ipv4     = ["0.0.0.0/0"]
  }

  inbound {
    label    = "allow-private-tcp"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "1-65535"
    ipv4     = local.private_cidrs
  }

  inbound {
    label    = "allow-private-udp"
    action   = "ACCEPT"
    protocol = "UDP"
    ports    = "1-65535"
    ipv4     = local.private_cidrs
  }

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"
}

resource "linode_firewall" "gpu_worker" {
  label   = "${var.cluster_name}-gpu-fw"
  tags    = concat(local.common_tags, ["firewall:gpu"])
  linodes = [linode_instance.gpu_worker.id]

  inbound {
    label    = "allow-ssh-admin"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22"
    ipv4     = var.admin_ipv4_cidrs
  }

  inbound {
    label    = "allow-private-tcp"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "1-65535"
    ipv4     = local.private_cidrs
  }

  inbound {
    label    = "allow-private-udp"
    action   = "ACCEPT"
    protocol = "UDP"
    ports    = "1-65535"
    ipv4     = local.private_cidrs
  }

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"
}

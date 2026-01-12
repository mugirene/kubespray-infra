############################
# vSphere connection
############################
variable "vsphere_user" {
  type = string
}

variable "vsphere_password" {
  type      = string
  sensitive = true
}

variable "vsphere_server" {
  type = string
}

############################
# vCenter inventory
############################
variable "datacenter" {
  type = string
}

variable "cluster" {
  type = string
}

variable "datastore" {
  type = string
}

variable "network" {
  type = string
}

variable "folder" {
  type    = string
  default = "k8s"
}

############################
# Ubuntu ISO
############################
variable "ubuntu_iso_path" {
  type        = string
  description = "[DR-V7KGEN1-DS3] ISO/ubuntu-24.04.3-live-server-amd64.iso"
}

############################
# Kubernetes
############################
variable "k8s_vip" {
  type    = string
  default = "************************"
}

############################
# SSH access
############################
variable "ssh_public_key" {
  type        = string
  description = "SSH public key injected into user"
}

############################
# Ubuntu user password
############################
variable "ubuntu_password_hash" {
  type        = string
  sensitive   = true
  description = "SHA-512 hash generated with"
}

############################
# Network configuration
############################
variable "gateway" {
  type    = string
  default = "*******************"
}

variable "prefix" {
  type    = number
  default = 24
}

variable "dns" {
  type    = list(string)
  default = ["****************", "********************"]
}

############################
# VM sizing - Control Plane
############################
variable "control_cpu" {
  type    = number
  default = 3
}

variable "control_memory_mb" {
  type    = number
  default = 8192
}

variable "control_disk_gb" {
  type    = number
  default = 50
}

############################
# VM sizing - Workers
############################
variable "worker_cpu" {
  type    = number
  default = 3
}

variable "worker_memory_mb" {
  type    = number
  default = 8192
}

variable "worker_disk_gb" {
  type    = number
  default = 80
}


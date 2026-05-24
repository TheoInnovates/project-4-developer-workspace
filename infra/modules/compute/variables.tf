variable "compartment_ocid" {
  description = "Compartment OCID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet OCID to launch the instance in"
  type        = string
}

variable "instance_ocpus" {
  description = "Number of OCPUs"
  type        = number
}

variable "instance_memory_gb" {
  description = "Memory in GB"
  type        = number
}

variable "boot_volume_gb" {
  description = "Boot volume size in GB"
  type        = number
}

variable "ssh_public_key" {
  description = "SSH public key"
  type        = string
}

variable "cloud_init_userdata" {
  description = "Rendered cloud-init userdata (base64-encoded)"
  type        = string
}

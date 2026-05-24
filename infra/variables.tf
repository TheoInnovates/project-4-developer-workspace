variable "tenancy_ocid" {
  description = "OCI tenancy OCID"
  type        = string
}

variable "user_ocid" {
  description = "OCI user OCID"
  type        = string
}

variable "fingerprint" {
  description = "OCI API key fingerprint"
  type        = string
}

variable "private_key_path" {
  description = "Path to OCI API private key"
  type        = string
  default     = "~/.oci/oci_api_key.pem"
}

variable "region" {
  description = "OCI region"
  type        = string
  default     = "us-ashburn-1"
}

variable "compartment_ocid" {
  description = "OCI compartment OCID (use tenancy OCID for root compartment)"
  type        = string
}

variable "instance_ocpus" {
  description = "Number of OCPUs for the A1.Flex instance"
  type        = number
  default     = 4
}

variable "instance_memory_gb" {
  description = "Memory in GB for the A1.Flex instance"
  type        = number
  default     = 24
}

variable "boot_volume_gb" {
  description = "Boot volume size in GB"
  type        = number
  default     = 100
}

variable "ssh_public_key" {
  description = "SSH public key for instance access (fallback if Tailscale SSH is unavailable)"
  type        = string
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key (reusable, from Settings > Keys)"
  type        = string
  sensitive   = true
}

variable "github_repo_url" {
  description = "GitHub repo URL to clone onto the instance"
  type        = string
}

variable "tls_mode" {
  description = "TLS certificate mode: self-signed (generate on cloud-init) or external (import separately)"
  type        = string
  default     = "self-signed"
  validation {
    condition     = contains(["self-signed", "external"], var.tls_mode)
    error_message = "tls_mode must be 'self-signed' or 'external'."
  }
}

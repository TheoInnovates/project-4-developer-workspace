module "networking" {
  source           = "./modules/networking"
  compartment_ocid = var.compartment_ocid
}

module "compute" {
  source             = "./modules/compute"
  compartment_ocid   = var.compartment_ocid
  subnet_id          = module.networking.subnet_id
  instance_ocpus     = var.instance_ocpus
  instance_memory_gb = var.instance_memory_gb
  boot_volume_gb     = var.boot_volume_gb
  ssh_public_key     = var.ssh_public_key

  cloud_init_userdata = base64encode(templatefile("${path.module}/cloud-init/userdata.yaml.tftpl", {
    tailscale_auth_key = var.tailscale_auth_key
    github_repo_url    = var.github_repo_url
    tls_mode           = var.tls_mode
  }))
}

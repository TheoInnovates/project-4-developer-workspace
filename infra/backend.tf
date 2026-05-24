# Local backend for now. Migrate to OCI Object Storage later if needed.
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

# PVE-target Vault config. Identical to vault/config.hcl except for the seal
# stanza, which delegates the unseal key to AWS KMS so Vault comes back
# automatically after a restart, a VM reboot, or an HA failover to another node.
#
# Kept separate from vault/config.hcl on purpose: the Spark stack is still the
# migration rollback and has no KMS credentials — an awskms seal there would
# fail to start.
#
# Credentials are supplied as AWS_* environment variables in the container
# (IAM user vault-unseal, permitted only Encrypt/Decrypt/DescribeKey on this
# single key). The key id itself is not a secret.

ui = true

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

storage "file" {
  path = "/vault/data"
}

seal "awskms" {
  region     = "us-east-1"
  kms_key_id = "30ded68a-3527-4d81-b1ad-25979bb54331"
}

disable_mlock = true

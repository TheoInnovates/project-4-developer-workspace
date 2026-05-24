output "instance_id" {
  description = "Instance OCID"
  value       = oci_core_instance.devstack.id
}

output "public_ip" {
  description = "Public IP (for reference only — no ports are open)"
  value       = oci_core_instance.devstack.public_ip
}

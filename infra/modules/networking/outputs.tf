output "subnet_id" {
  description = "Subnet OCID for compute instances"
  value       = oci_core_subnet.devstack.id
}

output "vcn_id" {
  description = "VCN OCID"
  value       = oci_core_vcn.devstack.id
}

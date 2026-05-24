resource "oci_core_vcn" "devstack" {
  compartment_id = var.compartment_ocid
  display_name   = "devstack-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = "devstack"
}

resource "oci_core_internet_gateway" "devstack" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.devstack.id
  display_name   = "devstack-igw"
  enabled        = true
}

resource "oci_core_route_table" "devstack" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.devstack.id
  display_name   = "devstack-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.devstack.id
  }
}

resource "oci_core_security_list" "devstack" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.devstack.id
  display_name   = "devstack-seclist"

  # Zero ingress rules — all access is via Tailscale (outbound NAT traversal)

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    description = "Allow all outbound (Docker pulls, Tailscale relay, updates)"
  }
}

resource "oci_core_subnet" "devstack" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.devstack.id
  display_name               = "devstack-subnet"
  cidr_block                 = "10.0.1.0/24"
  dns_label                  = "sub1"
  route_table_id             = oci_core_route_table.devstack.id
  security_list_ids          = [oci_core_security_list.devstack.id]
  prohibit_public_ip_on_vnic = false # Public IP for outbound NAT, but no ingress rules
}

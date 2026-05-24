output "instance_public_ip" {
  description = "Public IP (reference only — no ports are open via security list)"
  value       = module.compute.public_ip
}

output "tailscale_ssh_command" {
  description = "SSH into the instance via Tailscale"
  value       = "tailscale ssh ubuntu@devstack"
}

output "dashboard_url" {
  description = "Homepage dashboard URL (after hosts file setup)"
  value       = "https://home.devstack"
}

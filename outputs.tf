output "name_prefix" {
  value = var.name_prefix
}

output "app_instance_id" {
  value = aws_instance.app.id
}

output "app_ip_address" {
  value = aws_eip.app.public_ip
}

output "app_ipv6_address" {
  value = aws_instance.app.ipv6_addresses[0]
}

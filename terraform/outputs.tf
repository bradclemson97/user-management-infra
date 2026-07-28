output "public_ip" {
  description = "Elastic IP — create an A record: app.bradleyclemson.com -> this IP"
  value       = aws_eip.app.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_eip.app.public_ip}"
}

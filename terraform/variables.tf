variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-2"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
}

variable "project" {
  description = "Project tag applied to all resources"
  type        = string
  default     = "user-management"
}

variable "your_ip_cidr" {
  description = "Your IP address in CIDR notation for SSH access (e.g. 1.2.3.4/32). Defaults to open — restrict this in production."
  type        = string
  default     = "0.0.0.0/0"
}

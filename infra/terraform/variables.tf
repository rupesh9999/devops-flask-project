variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Name prefix applied to taggable AWS resources"
  type        = string
  default     = "devops-flask"
}

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "flask_instance_type" {
  description = "EC2 instance type for the Flask application"
  type        = string
  default     = "t3.micro"
}

variable "mysql_instance_type" {
  description = "EC2 instance type for the MySQL server"
  type        = string
  default     = "t3.micro"
}

variable "flask_allowed_cidr" {
  description = "CIDR allowed to access the Flask application over HTTPS"
  type        = string
  default     = "0.0.0.0/0"
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to SSH into instances (use trusted IPs only)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name used for SSH access"
  type        = string
}

variable "domain_name" {
  description = "Fully qualified domain name mapped to the Flask instance public IP"
  type        = string
  default     = ""
}

variable "acme_email" {
  description = "Email address used to register with Let's Encrypt"
  type        = string
  default     = ""
}

variable "app_repo_url" {
  description = "Git repository URL containing the Flask application"
  type        = string
}

variable "db_username" {
  description = "Username for the application database user"
  type        = string
  default     = "appuser"
}

variable "db_password" {
  description = "Password for the application database user"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Name of the application database"
  type        = string
  default     = "appdb"
}

variable "db_allowed_host_pattern" {
  description = "MySQL host pattern for the application user (e.g., 10.0.1.% to allow public subnet)"
  type        = string
  default     = "10.0.1.%"
}

variable "ip_allowlist" {
  description = "Comma-separated list of CIDRs allowed through Nginx reverse proxy (empty for allow all)"
  type        = string
  default     = ""
}

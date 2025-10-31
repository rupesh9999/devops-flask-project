output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "public_instance_public_ip" {
  description = "Public IP address of the Flask EC2 instance"
  value       = aws_instance.flask.public_ip
}

output "private_instance_private_ip" {
  description = "Private IP address of the MySQL EC2 instance"
  value       = aws_instance.mysql.private_ip
}

output "flask_security_group_id" {
  description = "Security group ID for the Flask instance"
  value       = aws_security_group.sg_flask.id
}

output "db_security_group_id" {
  description = "Security group ID for the MySQL instance"
  value       = aws_security_group.sg_db.id
}

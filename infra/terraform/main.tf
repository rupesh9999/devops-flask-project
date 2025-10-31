locals {
  project_tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

data "aws_availability_zones" "available" {}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.project_tags, {
    Name = "${var.project_name}-${var.environment}-vpc"
  })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.project_tags, {
    Name = "${var.project_name}-${var.environment}-igw"
  })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = merge(local.project_tags, {
    Name = "${var.project_name}-${var.environment}-public"
  })
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(local.project_tags, {
    Name = "${var.project_name}-${var.environment}-private"
  })
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.project_tags, {
    Name = "${var.project_name}-${var.environment}-nat-eip"
  })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = merge(local.project_tags, {
    Name = "${var.project_name}-${var.environment}-nat"
  })

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(local.project_tags, {
    Name = "${var.project_name}-${var.environment}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = merge(local.project_tags, {
    Name = "${var.project_name}-${var.environment}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "sg_flask" {
  name        = "${var.project_name}-${var.environment}-flask"
  description = "Security group for Flask EC2"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.flask_allowed_cidr]
  }

  ingress {
    description = "HTTP for Certbot"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.project_tags, {
    Name = "${var.project_name}-${var.environment}-sg-flask"
  })
}

resource "aws_security_group" "sg_db" {
  name        = "${var.project_name}-${var.environment}-db"
  description = "Security group for MySQL EC2"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from Flask SG"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_flask.id]
  }

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.project_tags, {
    Name = "${var.project_name}-${var.environment}-sg-db"
  })
}

resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.project_tags, {
    Name = "${var.project_name}-${var.environment}-ec2-role"
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "template_file" "flask_userdata" {
  template = file("${path.module}/../../scripts/ec2_user_data_flask.sh")

  vars = {
    repo_url      = var.app_repo_url
    domain_name   = var.domain_name
    acme_email    = var.acme_email
    db_name       = var.db_name
    db_username   = var.db_username
    db_password   = var.db_password
    db_host       = aws_instance.mysql.private_ip
    environment   = var.environment
    project_name  = var.project_name
    ip_allowlist  = var.ip_allowlist
  }
}

data "template_file" "mysql_userdata" {
  template = file("${path.module}/../../scripts/ec2_user_data_mysql.sh")

  vars = {
    db_name                  = var.db_name
    db_username              = var.db_username
    db_password              = var.db_password
    db_allowed_host_pattern  = var.db_allowed_host_pattern
  }
}

resource "aws_instance" "flask" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.flask_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.sg_flask.id]
  key_name               = var.key_pair_name
  associate_public_ip_address = true
  user_data              = data.template_file.flask_userdata.rendered
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  tags = merge(local.project_tags, {
    Name = "${var.project_name}-${var.environment}-flask"
  })
}

resource "aws_instance" "mysql" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.mysql_instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.sg_db.id]
  key_name               = var.key_pair_name
  associate_public_ip_address = false
  user_data              = data.template_file.mysql_userdata.rendered
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  tags = merge(local.project_tags, {
    Name = "${var.project_name}-${var.environment}-mysql"
  })
}

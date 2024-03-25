terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "=3.42.0"
    }
  }
}

provider "aws" {
  region  = var.region
}

resource "aws_vpc" "mpn" {
  cidr_block           = var.address_space
  enable_dns_hostnames = true

  tags = {
    name = "${var.prefix}-vpc-${var.region}"
    environment = "Production"
  }
}

resource "aws_subnet" "mpn" {
  vpc_id     = aws_vpc.mpn.id
  cidr_block = var.subnet_prefix

  tags = {
    name = "${var.prefix}-subnet"
  }
}

resource "aws_security_group" "mpn" {
  name = "${var.prefix}-security-group"

  vpc_id = aws_vpc.mpn.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.my_own_public_ip
  }

  ingress {
    from_port   = 5500
    to_port     = 5501
    protocol    = "tcp"
    cidr_blocks = var.my_own_public_ip
  }

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.my_own_public_ip
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.my_own_public_ip
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
    prefix_list_ids = []
  }

  tags = {
    Name = "${var.prefix}-security-group"
  }
}

resource "aws_internet_gateway" "mpn" {
  vpc_id = aws_vpc.mpn.id

  tags = {
    Name = "${var.prefix}-internet-gateway"
  }
}

resource "aws_route_table" "mpn" {
  vpc_id = aws_vpc.mpn.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mpn.id
  }
}

resource "aws_route_table_association" "mpn" {
  subnet_id      = aws_subnet.mpn.id
  route_table_id = aws_route_table.mpn.id
}

data "aws_ami" "amazon-linux-2023" {
  most_recent = true

  filter {
    name = "name"
    values = ["al2023-ami-2023*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

resource "aws_eip" "mpn" {
  instance = aws_instance.mpn.id
  vpc      = true
}

resource "aws_eip_association" "mpn" {
  instance_id   = aws_instance.mpn.id
  allocation_id = aws_eip.mpn.id
}

resource "aws_instance" "mpn" {
  ami                         = data.aws_ami.amazon-linux-2023.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.mpn.key_name
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.mpn.id
  vpc_security_group_ids      = [aws_security_group.mpn.id]

  tags = {
    Name = "${var.prefix}-mpn-instance"
  }
}

# We're using a little trick here so we can run the provisioner without
# destroying the VM. Do not do this in production.

# If you need ongoing management (Day N) of your virtual machines a tool such
# as Chef or Puppet is a better choice. These tools track the state of
# individual files and can keep them in the correct configuration.

resource "null_resource" "configure-requisites" {
  depends_on = [aws_eip_association.mpn]

  triggers = {
    build_number = timestamp()
  }

  provisioner "file" {
    source      = "files/"
    destination = "/home/ec2-user/"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.mpn.private_key_pem
      host        = aws_eip.mpn.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum update",
      "sleep 15",
      "sudo yum -y install git",
      "sudo yum -y install docker",
      "sudo systemctl start docker"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.mpn.private_key_pem
      host        = aws_eip.mpn.public_ip
    }
  }
}

resource "tls_private_key" "mpn" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

locals {
  private_key_filename = "${var.prefix}-ssh-key.pem"
}

resource "aws_key_pair" "mpn" {
  key_name   = local.private_key_filename
  public_key = tls_private_key.mpn.public_key_openssh

  provisioner "local-exec" { # Create a "myKey.pem" to your computer!!
    command = "echo '${tls_private_key.mpn.private_key_pem}' > '${var.private_key_path}'"
  }
}

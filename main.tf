terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

# SECURITY GROUP
resource "aws_security_group" "grafana_sg_terraform" {
  name        = "grafana-sg"
  description = "Allow SSH and Grafana HTTP access"
  vpc_id      = "vpc-0262c7a50445ece52"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Grafana UI"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 INSTANCE WITH DOCKER COMPOSE GRAFANA
resource "aws_instance" "grafana_ec2" {
  ami                         = "ami-0faab6bdbac9486fb"
  instance_type               = "t3.micro"
  key_name                    = "graphana_key"
  subnet_id                   = "subnet-040215eb6e71489b6"
  vpc_security_group_ids      = [aws_security_group.grafana_sg_terraform.id]
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io docker-compose
              systemctl start docker
              systemctl enable docker
              mkdir -p /home/ubuntu/grafana
              cat <<EOL > /home/ubuntu/grafana/docker-compose.yml
              version: '3'
              services:
                grafana:
                  image: grafana/grafana
                  ports:
                    - "3000:3000"
                  restart: always
              EOL
              cd /home/ubuntu/grafana
              docker-compose up -d
              EOF

  tags = {
    Name = "Grafana-EC2"
  }
}

# LAUNCH TEMPLATE WITH DETAILED MONITORING ENABLED
resource "aws_launch_template" "asg_template" {
  name_prefix   = "asg-spot-template-"
  image_id      = "ami-0faab6bdbac9486fb"
  instance_type = "t3.micro"
  key_name      = "graphana_key"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.grafana_sg_terraform.id]
  }

  instance_market_options {
    market_type = "spot"
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "asg-spot-instance"
    }
  }
}

# AUTO SCALING GROUP 1
resource "aws_autoscaling_group" "asg" {
  name                = "grafana-asg"
  desired_capacity    = 2
  max_size            = 4
  min_size            = 1
  vpc_zone_identifier = ["subnet-040215eb6e71489b6"]

  launch_template {
    id      = aws_launch_template.asg_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "asg-instance"
    propagate_at_launch = true
  }
}

# AUTO SCALING GROUP 2
resource "aws_autoscaling_group" "asg2" {
  name                = "grafana-asg2"
  desired_capacity    = 4
  max_size            = 8
  min_size            = 2
  vpc_zone_identifier = ["subnet-040215eb6e71489b6"]

  launch_template {
    id      = aws_launch_template.asg_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "asg-instance2"
    propagate_at_launch = true
  }
}

# IAM ROLE FOR LAMBDAs
resource "aws_iam_role" "lambda_exec_role_T" {
  name = "lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# IAM POLICY FOR LAMBDAs
resource "aws_iam_policy" "lambda_policy_T" {
  name        = "lambda-asg-policy"
  description = "Allow Lambda to describe ASG and write logs"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "autoscaling:DescribeAutoScalingGroups"
        ],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

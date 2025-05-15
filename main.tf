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
resource "aws_security_group" "grafana_sg" {
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
  ami                    = "ami-08962a4068733a2b6"
  instance_type          = "t3.micro"
  key_name               = "graphana_key"
  subnet_id              = "subnet-040215eb6e71489b6"
  vpc_security_group_ids = [aws_security_group.grafana_sg.id]
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

# LAUNCH TEMPLATE FOR ASG WITH SPOT INSTANCES
resource "aws_launch_template" "asg_template" {
  name_prefix   = "asg-spot-template-"
  image_id      = "ami-08962a4068733a2b6"
  instance_type = "t3.micro"
  key_name      = "graphana_key"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.grafana_sg.id]
  }

  instance_market_options {
    market_type = "spot"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "asg-spot-instance"
    }
  }
}

# AUTO SCALING GROUP
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

# IAM ROLE FOR LAMBDAs
resource "aws_iam_role" "lambda_exec_role" {
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
resource "aws_iam_policy" "lambda_policy" {
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

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# LAMBDA: GET INSTANCE IDS
resource "aws_lambda_function" "asg_instance_ids" {
  function_name = "GetASGInstanceIds"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.9"
  code          = <<-EOF
import boto3, json
asg = boto3.client('autoscaling')
def lambda_handler(event, context):
    name = event.get('queryStringParameters',{}).get('asg')
    if not name:
        return {'statusCode':400,'body':json.dumps({'error':'Missing asg param'})}
    resp = asg.describe_auto_scaling_groups(AutoScalingGroupNames=[name])
    ids = [i['InstanceId'] for g in resp['AutoScalingGroups'] for i in g['Instances'] if i['LifecycleState']=='InService']
    return {'statusCode':200,'body':json.dumps(ids),'headers':{'Content-Type':'application/json'}}
EOF
}

# LAMBDA: LIST ASG NAMES
resource "aws_lambda_function" "asg_list" {
  function_name = "ListASGNames"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.9"
  code          = <<-EOF
  import boto3, json
asg = boto3.client('autoscaling')
def lambda_handler(event, context):
    resp = asg.describe_auto_scaling_groups()
    names = [g['AutoScalingGroupName'] for g in resp['AutoScalingGroups']]
    return {'statusCode':200,'headers':{'Content-Type':'application/json'},'body':json.dumps(names)}
EOF
}

# LAMBDA FUNCTION URLS
resource "aws_lambda_function_url" "ids_url" {
  function_name      = aws_lambda_function.asg_instance_ids.function_name
  authorization_type = "NONE"
}
resource "aws_lambda_function_url" "list_url" {
  function_name      = aws_lambda_function.asg_list.function_name
  authorization_type = "NONE"
}

output "grafana_ec2_url" {
  value = "http://${aws_instance.grafana_ec2.public_ip}:3000"
}
output "asg_ids_url" {
  value = aws_lambda_function_url.ids_url.function_url
}
output "asg_list_url" {
  value = aws_lambda_function_url.list_url.function_url
}

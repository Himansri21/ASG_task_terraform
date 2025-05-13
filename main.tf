provider "aws" {
  region = "eu-central-1"
}

resource "aws_autoscaling_group" "example" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = ["subnet-0123456789abcdef0"] # Replace with your subnet

  launch_template {
    id      = "lt-09c4bf34fffc56cd8"
    version = "$Latest"
  }
}


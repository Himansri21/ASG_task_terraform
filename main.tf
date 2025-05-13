provider "aws" {
  region = "eu-central-1"
}

resource "aws_autoscaling_group" "Task-ASG-graphana-terraform" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = ["subnet-040215eb6e71489b6"] 

  launch_template {
    id      = "lt-09c4bf34fffc56cd8"
    version = "$Latest"
  }
}


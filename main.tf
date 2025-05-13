provider "aws" {
  region = "eu-central-1"
}

resource "aws_autoscaling_group" "Task-ASG-graphana-terraform" {
  desired_capacity     = 5
  max_size             = 10
  min_size             = 2
  vpc_zone_identifier  = ["subnet-040215eb6e71489b6"] 

  launch_template {
    id      = "lt-00cf5b0aa8be470b6"
    version = "$Latest"
  }
}


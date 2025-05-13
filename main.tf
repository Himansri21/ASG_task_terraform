provider "aws" {
  region = "us-east-1"
}

resource "aws_launch_template" "example" {
  name_prefix   = "example-launch-template"
  image_id      = "ami-0c55b159cbfafe1f0" # Replace with a valid AMI
  instance_type = "t2.micro"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "example" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = ["subnet-0123456789abcdef0"] # Replace with your subnet

  launch_template {
    id      = aws_launch_template.example.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "example-asg"
    propagate_at_launch = true
  }
}

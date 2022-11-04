provider "aws" {
        region = "us-east-2"
        profile = "ldamarala"
}

resource "aws_instance" "example" {
    ami = "ami-01e1ce6bc38615e75"
    instance_type = "t2.micro"
    vpc_security_group_ids = [aws_security_group.instance.id]
    user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF
#  The user_data_replace_on_change parameter is set to true 
#  so that when you change the user_data parameter and run apply
#  Terraform will terminate the original instance and launch a totally new one

    user_data_replace_on_change = true

    tags = {
      Name = "terraform-example"
    }
}

resource "aws_security_group" "instance" {
  name = "terraform-example-instance-sg"

  ingress{
    from_port = var.server_port
    to_port   = var.server_port
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  } 

  lifecycle {
    create_before_destroy = true
  }
}

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type = number
  default = 8080
}

output "public_ip" {
   value = aws_instance.example.public_ip
   description = "The public IP address of the web server"
}

resource "aws_launch_configuration" "example" {
    image_id = "ami-01e1ce6bc38615e75" 
    instance_type = "t2.micro"

    user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF

   # Required when using a launch configuration with an ASG.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "example" {
   launch_configuration = aws_launch_configuration.example.name
   vpc_zone_identifier =  data.aws_subnets.default.ids

   target_group_arns = [aws_lb_target_group.asg.arn]
   health_check_type = "ELB"
   min_size = 1
   max_size = 5

   tag{
    key = "Name"
    value = "terraform-asg-example"
    propagate_at_launch = true
   } 
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_lb" "example" {
  name               = "terraform-asg-example"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups = [aws_security_group.alb.id]
} 
# To define a listener for this ALB using the aws_lb_listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = 80
  protocol          = "HTTP"

  # By default, return a simple 404 page
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  } 
}

resource "aws_security_group" "alb" {
   name = "terraform-example-alb"
   
  # Allow inbound HTTP requests
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound requests
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# create a target group for your ASG using the aws_lb_target_group resource
resource "aws_lb_target_group" "asg" {
  name     = "terraform-asg-example"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}
# creating listener rules using the aws_lb_listener_rule
resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

output "alb_dns_name" {
  value       = aws_lb.example.dns_name
  description = "The domain name of the load balancer"
}
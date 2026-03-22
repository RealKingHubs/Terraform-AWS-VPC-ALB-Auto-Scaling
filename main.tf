
#=======VPC and Subnets========
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  instance_tenancy     = "default"
  enable_dns_hostnames = true

  tags = {
    Name = "personal-lab-vpc"
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true # Required for public subnets

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "private-subnet-${count.index + 1}"
  }
}


#====== Routing and Internet Access ======== 
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IGW.id
  }
}

resource "aws_route_table_association" "public_subnet_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table" "private_route_table" {
  count  = 2
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "private-route-table-${count.index + 1}"
  }
}

resource "aws_route_table_association" "private_subnet_assoc" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_route_table[count.index].id

}

resource "aws_internet_gateway" "IGW" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "personal-lab-igw"
  }
}

#ElasticIP and NAT gateway

resource "aws_eip" "nat" {
  count      = 2
  domain     = "vpc"
  depends_on = [aws_internet_gateway.IGW]

  tags = {
    Name = "personal-lab-nat-eip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "main" {
  count             = 2
  allocation_id     = aws_eip.nat[count.index].id
  subnet_id         = aws_subnet.public[count.index].id
  connectivity_type = "public"

  tags = {
    Name = "personal-lab-nat-gateway-${count.index + 1}"
  }
}


#Security group for EC2 instances
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Security group for ALB in personal lab"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Security group for bastion host in personal lab"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.bastion]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web_sg" {
  name        = "web-sg"
  description = "Security group for web servers in personal lab"
  vpc_id      = aws_vpc.main.id


  #Traffic from ALB
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  #SSH from Bastion
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }
  # Allow Bastion to test the web service
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#key pair for EC2 instances
resource "aws_key_pair" "my_lab_key" {
  key_name   = "mykey"
  public_key = file("~/.ssh/mykey.pub") # Path to your public key
}

# Launch Template for Private Instances (Apache)
resource "aws_launch_template" "webservers" {
  name          = "personal-lab-webserver-template"
  image_id      = var.ami
  instance_type = var.instance_type
  key_name      = aws_key_pair.my_lab_key.key_name
  user_data     = filebase64("${path.module}/userdata.tpl")

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.web_sg.id]
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }


  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "Web-servers"
  }
}

#Auto Scaling Group for Apache Web Servers
resource "aws_autoscaling_group" "web_asg" {
  name             = "web-asg"
  max_size         = 5
  min_size         = 2
  desired_capacity = 2
  launch_template {
    id      = aws_launch_template.webservers.id
    version = "$Latest"
  }
  vpc_zone_identifier       = aws_subnet.private[*].id
  health_check_type         = "ELB"
  health_check_grace_period = 300
  target_group_arns         = [aws_lb_target_group.web_tg.arn]


  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
    }
  }

}

# Create Bastion Host in Public Subnet
resource "aws_instance" "bastion" {
  ami                    = var.ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name               = aws_key_pair.my_lab_key.key_name

  tags = {
    Name = "bastion-host"
  }

}

# Create Application Load Balancer
resource "aws_lb" "web_alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }

}

# Create Target Group for Web Servers
resource "aws_lb_target_group" "web_tg" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

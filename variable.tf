variable "region" {
  description = "Region we deploy resources"
  type        = string
  default     = "us-east-1"
}
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "azs" {
  description = "Availability Zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

#EC2 instance variables
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ami" {
  description = "AMI ID for the EC2 instance"
  type        = string
  default     = "ami-02dfbd4ff395f2a1b"
}


variable "bastion" {
  type    = string
  default = "YOUR/IP"
}
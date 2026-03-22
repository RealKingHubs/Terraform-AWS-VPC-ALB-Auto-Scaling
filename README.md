# Personal Lab — Production-Grade AWS VPC Infrastructure

[![Terraform](https://img.shields.io/badge/Terraform->=1.3.0-7B42BC?logo=terraform)](https://developer.hashicorp.com/terraform)
[![AWS](https://img.shields.io/badge/AWS-VPC%20%7C%20EC2%20%7C%20ALB%20%7C%20ASG-FF9900?logo=amazonaws)](https://aws.amazon.com)
[![License](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

A production-grade AWS VPC environment built entirely with Terraform. This is not a tutorial follow-along — every resource, every security rule, and every architectural decision in this project was deliberately chosen. The infrastructure implements true multi-AZ high availability, private compute with no direct internet exposure, enforced IMDSv2 on all instances, and remote state management backed by S3 and DynamoDB.

<img width="1893" height="947" alt="Screenshot 2026-03-22 094633" src="https://github.com/user-attachments/assets/98786813-c02e-4bae-a6bd-5301d9cc0383" />


Built by **Odo Kingsley Uchenna** as part of a deep-dive into AWS networking and Terraform Infrastructure as Code.

---

## Architecture
<img width="928" height="1145" alt="image_9e2a489a" src="https://github.com/user-attachments/assets/559d8c80-7f48-4020-8e33-b0b9d0f7668a" />

   


### Traffic Paths

**User HTTP traffic:** Internet → IGW → ALB (`alb-sg`) → Web servers (`web-sg` port 80 from `alb-sg`)

**Engineer SSH access:** Your IP only → IGW → Bastion (`bastion-sg`) → Web servers (`web-sg` port 22 from `bastion-sg`)

**Private instance outbound:** Web server → Private Route Table → NAT Gateway (same AZ) → IGW → Internet

---

## Why This Architecture

Every decision in this project has a reason behind it. These are not defaults — they are deliberate choices.

**Per-AZ NAT Gateways** — A single NAT Gateway is a hidden single point of failure. If the AZ hosting it goes down, every private instance in every other AZ loses outbound internet access even though those instances are still running. This project deploys one NAT Gateway per AZ (`personal-lab-nat-gateway-1` and `personal-lab-nat-gateway-2`), each with its own Elastic IP, so each AZ is fully self-sufficient.

**ELB health checks over EC2 health checks** — The EC2 health check only verifies that an instance is powered on. It cannot detect a crashed Apache process. ELB health checks ask "is this instance actually responding to HTTP requests?" — which is the only question that actually matters for application availability.

**IMDSv2 enforced** — `http_tokens = required` on every instance prevents SSRF attacks from reaching the instance metadata service at `169.254.169.254`. This is a zero-cost security hardening measure that should be standard on every EC2 instance.

**Security group chaining** — `web-sg` references `alb-sg` and `bastion-sg` by security group ID rather than by IP range. This means only traffic that has actually passed through the ALB or bastion can reach the web servers — not just traffic that claims to come from a particular IP address.

**`min_healthy_percentage = 100` on instance refresh** — During a rolling update with only two instances, a value of 50% means one instance is taken down before its replacement is confirmed healthy. That leaves a single point of failure during deployments. 100% ensures a replacement is healthy before the old instance is terminated.

**`depends_on` on the ASG** — Terraform's dependency graph does not capture timing requirements. Even when the NAT Gateway resource is created, there is a delay before it is fully available. If instances launch before that, the `userdata` script that installs Apache makes outbound calls that fail silently — the instance boots without Apache, fails its health checks, and the ALB returns 502. The `depends_on = [aws_nat_gateway.main]` block forces Terraform to wait.

---

## Project Structure

```
.
├── mainfile.tf                  # All infrastructure resources
│                            # VPC, subnets, IGW, NAT gateways, route tables,
│                            # security groups, key pair, launch template,
│                            # ASG, bastion host, ALB, target group, listener
├── variables.tf             # Input variable declarations
├── outputs.tf               # ALB DNS name, VPC ID, subnet IDs
├── backend.tf               # Remote state: S3 bucket + DynamoDB table
├── userdata.tpl             # Bootstrap script — installs and starts Apache
│
└── backend-setup/
    └── main.tf              # Creates the S3 bucket and DynamoDB lock table
                             # Run this first, separately, before the main project
```

---

## Prerequisites

- Terraform >= 1.3.0 — [Install](https://developer.hashicorp.com/terraform/downloads)
- AWS CLI configured with credentials that have VPC, EC2, ELB, and IAM permissions — [Install](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- SSH key pair at `~/.ssh/mykey` (private) and `~/.ssh/mykey.pub` (public)

Generate a key pair if you do not have one:

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/mykey
```

---

## Deployment

### Step 1 — Provision the remote state backend

The S3 bucket and DynamoDB table must exist before the main project can be initialized. They live in a separate folder so they can be managed independently.

```bash
cd backend-setup/
terraform init
terraform apply
```
<img width="1414" height="736" alt="image_f735f9cf" src="https://github.com/user-attachments/assets/6acc3378-018f-461a-a403-0b5e33121a61" />


This creates `personal-lab-terraform-state` (S3 bucket with versioning and AES256 encryption) and `personal-lab-terraform-locks` (DynamoDB table for state locking).

### Step 2 — Configure your variables

Create a `terraform.tfvars` file in the project root:

```hcl
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]
azs                  = ["us-east-1a", "us-east-1b"]
ami                  = "ami-0c02fb55956c7d316"   # Amazon Linux 2 — us-east-1
instance_type        = "t2.micro"
bastion              = "YOUR_IP_ADDRESS/32"       # Your IP only — do not use 0.0.0.0/0
```

Or use variable.tf like I did

To find your current IP:

```bash
curl ifconfig.me
```

### Step 3 — Initialize the main project

```bash
cd ../
terraform init
```

Terraform detects the S3 backend configuration and asks:

```
Do you want to copy existing state to the new backend? yes
```

Type `yes`. Your state file is now stored remotely in S3 and every subsequent `terraform apply` will acquire a DynamoDB lock before making changes.

### Step 4 — Review and apply

```bash
terraform plan    # Review every resource before creating anything
terraform apply   # Provision all infrastructure
```

Terraform will create the following resources in order: VPC, subnets, Internet Gateway, Elastic IPs, NAT Gateways, route tables, security groups, key pair, launch template, bastion host, ALB, target group, listener, and Auto Scaling Group.

### Step 5 — Verify the application is running

```bash
terraform output alb_dns_name
```

Open the DNS name in your browser. You should see the Apache default page. If you do not see it immediately, wait 2-3 minutes — the ASG instances need time to complete their `userdata` bootstrap before the ALB marks them healthy.

### Step 6 — SSH access

```bash
# Connect to the bastion host
ssh -i ~/.ssh/mykey ec2-user@<BASTION_PUBLIC_IP>

# From inside the bastion, connect to a private web server
ssh -i ~/.ssh/mykey ec2-user@<PRIVATE_INSTANCE_IP>

# Verify Apache is running on the private instance
curl localhost
```

To confirm the security boundary is working, try SSHing directly to a private instance from your local machine — the connection will time out, which is the expected and correct behaviour.

---

## Security Design

<img width="1621" height="640" alt="image_a8428062" src="https://github.com/user-attachments/assets/72a215d7-a6cb-4444-8ff3-4784bafcc90e" />

| Component | Security Group | Inbound Rule | Reasoning |
|---|---|---|---|
| Application Load Balancer | `alb-sg` | Port 80 from `0.0.0.0/0` | Public-facing entry point for all user traffic |
| Bastion Host | `bastion-sg` | Port 22 from `var.bastion` (your IP only) | SSH restricted to a single trusted IP — not the internet |
| Web Servers | `web-sg` | Port 80 from `alb-sg` | Only ALB-routed traffic reaches the application |
| Web Servers | `web-sg` | Port 22 from `bastion-sg` | SSH only via bastion — never directly from internet |
| Web Servers | `web-sg` | Port 80 from `bastion-sg` | Allows bastion to test the web service directly |

The web servers have no inbound rules referencing `0.0.0.0/0`. There is no combination of ports or protocols that allows a direct connection from the internet to a web server.

---

## Remote State Management

| Resource | AWS Name | Purpose |
|---|---|---|
| S3 Bucket | `personal-lab-terraform-state` | Stores `terraform.tfstate` — versioned, encrypted at rest, public access blocked |
| DynamoDB Table | `personal-lab-terraform-locks` | State locking — prevents concurrent `terraform apply` runs from corrupting state |

The S3 bucket has `prevent_destroy = true` and will not be deleted by `terraform destroy`. To tear down the backend completely:

```bash
# 1. Remove the backend block from backend.tf, then migrate state back to local
terraform init -migrate-state

# 2. Remove prevent_destroy from the bucket in backend-setup/main.tf, then apply
cd backend-setup/ && terraform apply

# 3. Empty the bucket (required — AWS rejects deletion of non-empty buckets)
aws s3 rm s3://personal-lab-terraform-state --recursive

# 4. Destroy the backend resources
terraform destroy
```

---

## Teardown

To destroy all infrastructure:

```bash
terraform destroy
```

This will terminate the ASG instances, delete the ALB, NAT Gateways, subnets, security groups, and VPC. The S3 state bucket is excluded from destruction by `prevent_destroy = true` — see the remote state teardown section above to remove it.

---

## What I Would Add Next

- **HTTPS** — ALB listener on port 443 with an ACM-managed TLS certificate and HTTP-to-HTTPS redirect on port 80
- **Database tier** — Private subnet group with RDS (PostgreSQL or MySQL) and its own security group accepting traffic only from `web-sg`
- **CloudWatch alarms** — CPU utilization threshold, unhealthy host count on the target group, and ASG scaling activity notifications
- **AWS WAF** — Web Application Firewall attached to the ALB for Layer 7 protection against common web exploits
- **VPC Flow Logs** — Network traffic logging to S3 or CloudWatch for auditing and incident investigation

---

## Author

**Odo Kingsley Uchenna**
Cloud / DevOps Engineer
[LinkdIN](https://www.linkedin.com/in/kingsley-odo-8b81a6369/)

> Built as part of a deep-dive into AWS networking and Terraform IaC. The full write-up covering the architecture decisions, the challenges encountered, and the debugging process is available on [Medium](https://medium.com/@RealKingHubs/building-a-production-grade-aws-vpc-with-terraform-what-i-learned-what-broke-and-why-i-made-the-c65242cd8338) and [Hashnode](https://realkinghubs-blog.hashnode.dev/building-a-production-grade-aws-auto-scaling-alb-and-vpc-with-terraform-high-availability-secure-access-and-remote-state-management).

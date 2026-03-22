# AWS Production-Grade VPC Infrastructure with Terraform

**Author:** Odo Kingsley Uchenna

A fully automated, production-style AWS VPC environment provisioned with Terraform. This project implements network isolation, high availability, secure access control, and remote state management following real-world cloud engineering best practices.

---

## Architecture Overview
<img width="516" height="494" alt="Screenshot 2026-03-17 175632" src="https://github.com/user-attachments/assets/84c78dd3-02d7-4b64-aeed-12a05fe77d0d" />
<img width="750" height="536" alt="Screenshot 2026-03-17 094711" src="https://github.com/user-attachments/assets/c12bb179-0580-4242-acca-4b0bff7f639a" />


```
                        Internet
                           │
                    Internet Gateway
                           │
              ┌────────────────────────┐
              │   Application Load     │
              │   Balancer (HTTP :80)  │
              └────────────────────────┘
                    │            │
        ┌───────────┘            └───────────┐
        │                                    │
  ┌─────────────┐                    ┌─────────────┐
  │  AZ-1       │                    │  AZ-2       │
  │  Public     │                    │  Public     │
  │  Subnet     │                    │  Subnet     │
  │             │                    │             │
  │ NAT GW 1    │                    │ NAT GW 2    │
  │ Bastion     │                    │             │
  └─────────────┘                    └─────────────┘
        │                                    │
  ┌─────────────┐                    ┌─────────────┐
  │  AZ-1       │                    │  AZ-2       │
  │  Private    │                    │  Private    │
  │  Subnet     │                    │  Subnet     │
  │             │                    │             │
  │ Web Server  │                    │ Web Server  │
  │ (Apache)    │                    │ (Apache)    │
  └─────────────┘                    └─────────────┘
        └──────────── ASG ────────────────┘
```

---

## Features

- **VPC with public and private subnet tiers** across two Availability Zones
- **Redundant NAT Gateways** — one per AZ for true high availability
- **Application Load Balancer** distributing HTTP traffic across private web servers
- **Auto Scaling Group** maintaining a minimum of two Apache web servers at all times
- **Bastion Host** as the single controlled SSH entry point
- **Principle of Least Privilege** enforced via security group chaining
- **IMDSv2 enforced** on all EC2 instances via Launch Template metadata options
- **Remote Terraform state** stored in S3 with DynamoDB locking

---

## Project Structure

```
.
├── mainfile.tf              # VPC, subnets, NAT gateways, routing, security groups,
│                        # compute, and load balancer resources
├── variables.tf         # Input variable declarations
├── outputs.tf           # Output values (ALB DNS name, VPC ID, etc.)
├── backend.tf           # Remote state configuration (S3 + DynamoDB)
├── userdata.tpl         # Bootstrap script to install and start Apache
└── backend-setup/
    └── main.tf          # Creates the S3 bucket and DynamoDB table for remote state
```
![Uploading Screenshot 2026-03-17 094711.png…]()

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.3.0
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured with appropriate credentials
- An SSH key pair generated locally at `~/.ssh/mykey` and `~/.ssh/mykey.pub`

---

## Usage

### Step 1 — Set up remote state backend

This must be done before initializing the main project. The S3 bucket and DynamoDB table must exist before Terraform can use them.

```bash
cd backend-setup/
terraform init
terraform apply
```

### Step 2 — Configure your variables

Create a `terraform.tfvars` file in the root of the project:

```hcl
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]
azs                  = ["us-east-1a", "us-east-1b"]
ami                  = "ami-0c02fb55956c7d316"   # Amazon Linux 2 (us-east-1)
instance_type        = "t2.micro"
bastion              = "YOUR_IP_ADDRESS/32"       # Replace with your actual IP
```

### Step 3 — Initialize and apply the main project

```bash
terraform init      # Terraform will detect the S3 backend and migrate state
terraform plan      # Review the execution plan
terraform apply     # Provision all infrastructure
```

### Step 4 — Access the application

After a successful apply, Terraform will output the ALB DNS name. Open it in your browser to confirm the Apache default page is loading.

```bash
terraform output alb_dns_name
```

### Step 5 — SSH access via Bastion

```bash
# SSH into the bastion host
ssh -i ~/.ssh/mykey ec2-user@<BASTION_PUBLIC_IP>

# From the bastion, hop into a private web server
ssh -i ~/.ssh/mykey ec2-user@<PRIVATE_WEB_SERVER_IP>
```

---

## Security Design

| Security Group | Inbound Rules | Purpose |
|---|---|---|
| `alb-sg` | Port 80 from `0.0.0.0/0` | Accepts all public HTTP traffic |
| `bastion-sg` | Port 22 from your IP only | Restricts SSH to a single trusted IP |
| `web-sg` | Port 80 from `alb-sg`, Port 22 from `bastion-sg` | Web servers never directly exposed |

The web servers have no inbound rules from the open internet. The only way to reach them is through the ALB (HTTP) or through the bastion (SSH).

---

## Remote State Management

Terraform state is stored remotely in S3 and locked with DynamoDB to support team workflows and prevent concurrent state corruption.

| Resource | Name | Purpose |
|---|---|---|
| S3 Bucket | `personal-lab-terraform-state` | Stores `terraform.tfstate` with versioning and encryption |
| DynamoDB Table | `personal-lab-terraform-locks` | Provides state locking during apply operations |

### Destroying the remote state backend

If you need to tear down the backend entirely, follow this order precisely:

```bash
# 1. Migrate state back to local (remove backend block from backend.tf first)
terraform init -migrate-state

# 2. Remove prevent_destroy from the S3 bucket resource in backend-setup/main.tf
#    then apply to update
cd backend-setup/
terraform apply

# 3. Empty the S3 bucket (required before deletion)
aws s3 rm s3://personal-lab-terraform-state --recursive

# 4. Destroy the backend resources
terraform destroy
```

---

## Teardown

To destroy all infrastructure provisioned by this project:

```bash
terraform destroy
```

Note: The S3 state bucket has `prevent_destroy = true` and will not be deleted by this command. See the remote state teardown section above for full instructions.

---

## What I Would Add Next

- HTTPS listener on the ALB using AWS Certificate Manager (ACM)
- A private database subnet tier with RDS
- CloudWatch alarms for CPU utilization and ASG scaling events
- AWS WAF attached to the ALB for web application firewall protection
- VPC Flow Logs for network traffic auditing

---

## Author

**Odo Kingsley Uchenna**
Cloud/DevOps Engineer

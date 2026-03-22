

terraform {
  backend "s3" {
    bucket         = "personal-lab-terraform-state-2026"
    key            = "personal-lab/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "personal-lab-terraform-locks"
    encrypt        = true
  }
}

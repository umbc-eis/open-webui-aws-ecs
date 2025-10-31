# Backend configuration for remote state storage
#
# INSTRUCTIONS FOR SETUP:
# 1. First, create the S3 bucket and DynamoDB table (see bootstrap/ directory)
# 2. Create a backend.hcl file (not tracked in git) with your specific values:
#
#    Example backend.hcl:
#    bucket         = "your-org-prod-openwebui-state-YYYYMMDD"
#    key            = "open-webui-fargate/terraform.tfstate"
#    region         = "us-east-1"
#    dynamodb_table = "terraform-state-lock"
#    encrypt        = true
#
# 3. Initialize Terraform with the backend config:
#    terraform init -backend-config=backend.hcl
#
# 4. To migrate existing state:
#    terraform init -migrate-state -backend-config=backend.hcl
#
# NOTE: Each team member/environment should have their own backend.hcl file
# The backend.hcl file should NOT be committed to version control

terraform {
  backend "s3" {
    # Backend configuration will be provided via backend.hcl file
    # Run: terraform init -backend-config=backend.hcl
  }
}

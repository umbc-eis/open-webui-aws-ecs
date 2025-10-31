# Backend configuration for remote state storage
#
# INSTRUCTIONS:
# 1. First, create the S3 bucket and DynamoDB table (see bootstrap/ directory)
# 2. Copy this file to backend.tf: cp backend.tf.example backend.tf
# 3. Update the bucket name and dynamodb_table name below
# 4. Run: terraform init -migrate-state
# 5. Commit backend.tf to version control

terraform {
	backend "s3" {
  		bucket         = "umbc-prod-openwebui-genai-state-20251031"
  		key            = "open-webui-fargate/terraform.tfstate"
  		region         = "us-east-1"
  		dynamodb_table = "terraform-state-lock"
  		encrypt        = true
	}
}

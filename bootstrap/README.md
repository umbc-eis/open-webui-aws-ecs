# Terraform State Infrastructure Bootstrap

This directory contains Terraform configuration to create the infrastructure needed for remote state storage:
- **S3 Bucket**: Stores your Terraform state files with encryption and versioning
- **DynamoDB Table**: Provides state locking to prevent concurrent modifications

## Why Remote State?

Using remote state storage provides:
- **Collaboration**: Team members can share state
- **Safety**: State locking prevents conflicts
- **Versioning**: S3 versioning allows state recovery
- **Security**: Encryption at rest for sensitive data

## Prerequisites

- AWS CLI configured with appropriate credentials
- Permissions to create S3 buckets and DynamoDB tables
- Terraform installed (>= 1.0)

## Setup Instructions

### Step 1: Configure Variables

Create your configuration file:
```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set a **globally unique** bucket name:
```hcl
region = "us-east-1"  # Match your project region
state_bucket_name = "your-company-openwebui-tfstate-20241030"  # MUST BE UNIQUE
dynamodb_table_name = "terraform-state-lock"
```

**Important**: S3 bucket names must be globally unique across ALL AWS accounts. Consider including:
- Your organization name
- Project identifier
- Date (YYYYMMDD)

### Step 2: Initialize and Apply

```bash
terraform init
terraform plan
terraform apply
```

Review the plan carefully, then type `yes` to create the resources.

### Step 3: Note the Outputs

After successful apply, Terraform will display:
```
Outputs:

backend_config = <<-EOT
  Add this to your main.tf terraform block:

  backend "s3" {
    bucket         = "your-actual-bucket-name"
    key            = "open-webui-fargate/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
EOT
```

**Save these values** - you'll need them for the next step.

### Step 4: Configure Backend in Main Project

Go back to the project root:
```bash
cd ..
```

Copy and edit the backend configuration:
```bash
cp backend.tf.example backend.tf
```

Edit `backend.tf` and update with your actual bucket and table names from Step 3.

### Step 5: Migrate State

Initialize Terraform with the new backend:
```bash
terraform init -migrate-state
```

Terraform will ask: `Do you want to copy existing state to the new backend?`
Type `yes` to migrate your local state to S3.

### Step 6: Verify Migration

Check that state is now remote:
```bash
terraform state list
```

Your local `terraform.tfstate` file should now be empty or very small (just a backend pointer).

### Step 7: Commit Backend Configuration

```bash
git add backend.tf bootstrap/
git commit -m "Configure remote state with S3 backend"
git push
```

## State Management

### Viewing State
```bash
terraform state list                    # List all resources
terraform state show <resource>         # Show specific resource details
```

### Manual State Operations (Advanced)
```bash
# Pull current state
terraform state pull > state.json

# Push state (use with caution!)
terraform state push state.json
```

### State Locking

The DynamoDB table automatically locks state during operations. If a lock gets stuck:
```bash
terraform force-unlock <lock-id>
```

## Security Notes

1. **S3 Bucket**: Configured with:
   - Encryption at rest (AES256)
   - Versioning enabled (90-day retention)
   - Public access blocked
   - Lifecycle policies for cleanup

2. **DynamoDB Table**: Uses on-demand billing (cost-effective for small teams)

3. **Access Control**: Use IAM policies to restrict access to the bucket and table

## Costs

This setup incurs minimal AWS costs:
- **S3**: ~$0.023/GB/month (state files are typically <1MB)
- **S3 Versioning**: Additional cost for old versions
- **DynamoDB**: Pay-per-request (~$0.25 per million requests)
- **Typical monthly cost**: <$1

## Troubleshooting

### Error: Bucket name already exists
S3 bucket names are globally unique. Choose a different name in `terraform.tfvars`.

### Error: Failed to acquire state lock
Someone else is running Terraform, or a previous operation crashed:
1. Wait for the other operation to complete, OR
2. Use `terraform force-unlock <lock-id>` if you're certain no one else is working

### Migration failed
If state migration fails:
1. Keep your local `terraform.tfstate` file as backup
2. Manually copy it to S3: `aws s3 cp terraform.tfstate s3://your-bucket/open-webui-fargate/terraform.tfstate`
3. Run `terraform init -reconfigure`

## Cleanup

To remove the state infrastructure (not recommended for production):
```bash
cd bootstrap
terraform destroy
```

**Warning**: Only do this if you've migrated all state elsewhere or no longer need it!
# Terraform State Infrastructure Bootstrap

One-time setup that creates the **S3 bucket** used for remote Terraform state for the main project.

The main backend (`../backend.tf`) uses **S3-native locking** (`use_lockfile = true`), so no DynamoDB table is required. This bootstrap module currently still creates a `terraform-state-lock` DynamoDB table for historical reasons — it is **unused** and slated for removal in a follow-up. You can ignore it.

## Why remote state

- **Collaboration** — multiple operators share one source of truth.
- **Locking** — S3-native conditional writes prevent concurrent applies from corrupting state.
- **Versioning** — every write keeps a previous version for 90 days (S3 lifecycle); recovery is a `terraform state pull` away.
- **Encryption** — AES-256 at rest, public access blocked.

## Prerequisites

- AWS CLI configured with permissions to create S3 buckets (and DynamoDB tables, until that resource is removed).
- Terraform ≥ 1.0.

## Setup

### 1. Configure

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
region            = "us-east-1"
state_bucket_name = "your-org-openwebui-tfstate-20260623"  # MUST be globally unique
```

S3 bucket names are globally unique across all AWS accounts. Include org name + project + date.

### 2. Apply

```bash
terraform init
terraform plan
terraform apply
```

### 3. Note the output

After apply, Terraform prints a `backend_config` output with the values to paste into `../backend.hcl`:

```
backend_config = <<-EOT

    Add this to your backend.hcl file:

    bucket  = "your-actual-bucket-name"
    key     = "open-webui-fargate/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
EOT
```

### 4. Configure the main project's backend

```bash
cd ..
cp backend.hcl.example backend.hcl
# Edit backend.hcl with the values from the previous step
```

`backend.tf` is already committed and points at S3 with `use_lockfile = true`; only `backend.hcl` needs to be created (and is gitignored).

### 5. Initialize the main project

```bash
terraform init -backend-config=backend.hcl
```

If you have existing local state to migrate up:

```bash
terraform init -backend-config=backend.hcl -migrate-state
```

Terraform asks `Do you want to copy existing state to the new backend?` — answer `yes`.

## State management

```bash
terraform state list                 # list resources
terraform state show <addr>          # show one
terraform state pull > state.json    # dump
terraform force-unlock <lock-id>     # break a stuck lock (use carefully)
```

With S3-native locking, locks live as `.tflock` objects alongside the state object. If you need to break one manually, delete the `.tflock` object in S3 only after confirming no apply is actually running.

## What this module creates

- `aws_s3_bucket.terraform_state` — versioning enabled, AES-256 encryption, public access blocked, 90-day non-current version expiration, 7-day multipart-upload abort.
- `aws_dynamodb_table.terraform_locks` — **unused**, kept for now to avoid an unexpected destroy during the locking-mode transition. Will be removed.

## Costs

- **S3**: ~$0.023/GB-mo. State files are typically <1 MB; total <$1/mo.
- **DynamoDB** (unused): pay-per-request, idle ≈ $0.
- **Total**: well under $1/mo.

## Troubleshooting

**`BucketAlreadyExists`** — bucket names are global. Pick something more specific.

**`Failed to acquire state lock`** — another apply is running, or a previous one crashed without releasing the lock. With S3-native locking the lock object lives at `<key>.tflock`; check S3 for that object's age before force-unlocking.

**Migration failed** — local `terraform.tfstate` is still on disk. You can manually upload it:
```bash
aws s3 cp terraform.tfstate s3://your-bucket/open-webui-fargate/terraform.tfstate
terraform init -reconfigure -backend-config=backend.hcl
```

## Tearing it down

Don't, unless you've migrated state elsewhere first. If you really mean it:

```bash
cd bootstrap
terraform destroy
```

This will fail if the bucket contains objects (versioning keeps them around). Empty it manually first or add `force_destroy = true` to the bucket resource temporarily.

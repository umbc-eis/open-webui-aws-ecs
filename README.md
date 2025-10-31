# Open WebUI on AWS Fargate

Deploy [Open WebUI](https://github.com/open-webui/open-webui) - a feature-rich, self-hosted AI interface - on AWS using ECS Fargate with Terraform infrastructure-as-code.

## Overview

This Terraform configuration deploys a production-ready Open WebUI instance with:
- **Scalable compute**: ECS Fargate tasks with configurable CPU/memory
- **Persistent storage**: RDS PostgreSQL for data + EFS for files
- **High availability**: Multi-AZ deployment with Application Load Balancer
- **Secure access**: HTTPS with ACM certificates + IP allowlist + WAF protection
- **SSO integration**: AWS Cognito OAuth support
- **Automated setup**: Lambda function for admin user initialization

## Architecture

```
Internet
    │
    ↓
  [WAF] ← AWS Managed Rules (OWASP, IP reputation, etc.)
    │
    ↓
  [ALB] ← IP Allowlist (configurable)
    │
    ↓ HTTPS/HTTP
  [ECS Fargate Service]
    ├─→ [RDS PostgreSQL] (database)
    ├─→ [EFS] (file storage)
    └─→ [Secrets Manager] (credentials)

  [Lambda] → Admin initialization
  [Route53] → DNS management
```

### Components

| Component | Purpose |
|-----------|---------|
| **AWS WAF** | Web application firewall with managed rule groups for OWASP Top 10, IP reputation, and exploit protection |
| **ECS Fargate** | Runs Open WebUI containers (scalable, serverless) |
| **Application Load Balancer** | Public-facing HTTPS endpoint with SSL/TLS |
| **RDS PostgreSQL** | Persistent database for conversations, settings, users |
| **EFS** | Shared file storage for uploaded files and models |
| **Lambda** | Automatically creates admin user on first deployment |
| **Secrets Manager** | Stores admin credentials and OAuth secrets |
| **Route53** | DNS management for custom domain |
| **ACM** | SSL/TLS certificate management |
| **VPC Security Groups** | Network-level security with IP allowlisting |

## Features

### Security
- ✅ **AWS WAF**: Protection against OWASP Top 10, SQL injection, XSS, and known malicious IPs
- ✅ **IP Allowlist**: Restrict access to specific IPs/ranges (configurable)
- ✅ **HTTPS**: SSL/TLS encryption with ACM certificates
- ✅ **AWS Cognito SSO**: Single sign-on with OAuth 2.0
- ✅ **Secrets Management**: Credentials stored in AWS Secrets Manager
- ✅ **VPC Isolation**: Private subnets for compute, public for load balancer
- ✅ **Encryption**: Database and file storage encrypted at rest

### High Availability
- ✅ **Multi-AZ**: Spans multiple availability zones
- ✅ **Auto-scaling**: Configurable task count
- ✅ **Health checks**: Automatic unhealthy task replacement
- ✅ **Load balancing**: Even distribution of traffic

### Configurability
- ✅ **OAuth/SSO**: Disable local auth, force SSO login
- ✅ **User roles**: Configure default user permissions
- ✅ **API access**: Enable/disable API key authentication
- ✅ **Signup control**: Enable/disable new user registration
- ✅ **Direct connections**: Allow users to add their own LLM providers

## Prerequisites

### Required
1. **AWS Account** with appropriate permissions:
   - VPC, ECS, RDS, EFS, Lambda, ALB, Route53, ACM, Secrets Manager

2. **Terraform** >= 1.0
   ```bash
   brew install terraform  # macOS
   ```

3. **AWS CLI** configured with credentials
   ```bash
   aws configure
   ```

4. **Existing AWS Infrastructure**:
   - VPC with public and private subnets
   - Route53 hosted zone (for custom domain)
   - ACM certificate (for HTTPS)

### Optional
- AWS Cognito User Pool (for SSO integration)

## Quick Start

### 1. Clone and Configure

```bash
git clone <your-repo-url>
cd open-webui-aws-fargate
```

### 2. Set Up Remote State (First Time Only)

**If this is a new deployment**, you need to create the S3 bucket for Terraform state:

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with a globally unique bucket name
terraform init
terraform apply
cd ..
```

See [bootstrap/README.md](bootstrap/README.md) for detailed instructions.

### 3. Configure Backend

Create your backend configuration file (not tracked in git):

```bash
cp backend.hcl.example backend.hcl
```

Edit `backend.hcl` with your S3 bucket name from step 2:

```hcl
bucket         = "your-org-environment-openwebui-state-YYYYMMDD"
key            = "open-webui-fargate/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "terraform-state-lock"
encrypt        = true
```

**For Team Members**: If joining an existing project, get the `backend.hcl` values from your team lead or AWS Console.

### 4. Create Configuration

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
# AWS Configuration
region = "us-east-1"
azs    = ["us-east-1a", "us-east-1b"]

# Network (use your existing VPC)
vpc_id         = "vpc-xxxxx"
vpc_cidr_block = "10.0.0.0/16"
ecs_subnet_ids = ["subnet-xxxxx", "subnet-xxxxx"]  # Private subnets
alb_subnet_ids = ["subnet-xxxxx", "subnet-xxxxx"]  # Public subnets

# Domain & SSL
open_webui_domain              = "openwebui.example.com"
open_webui_domain_route53_zone = "Z1234567890ABC"
open_webui_domain_ssl_cert_arn = "arn:aws:acm:us-east-1:..."

# Security - IMPORTANT!
# Default blocks all access. Set your IP address(es):
allowed_ingress_cidrs = ["YOUR.IP.ADDRESS/32"]
# For public access: ["0.0.0.0/0"]
# Multiple IPs: ["1.2.3.4/32", "5.6.7.0/24"]

# Admin User
admin_name  = "Admin User"
admin_email = "admin@example.com"
```

### 5. Deploy

```bash
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Deployment takes ~10-15 minutes. The Lambda function will automatically:
1. Wait for the service to be healthy
2. Create the initial admin user
3. Store credentials in Secrets Manager

### 4. Get Admin Credentials

```bash
terraform output admin_credentials_command
```

Run the output command to retrieve the admin password:
```bash
aws secretsmanager get-secret-value --secret-id openwebui-admin-credentials --query SecretString --output text | jq -r '.password'
```

### 5. Access Open WebUI

Visit your configured domain (e.g., `https://openwebui.example.com`) and log in with:
- Email: (from `admin_email` variable)
- Password: (from Secrets Manager)

## Configuration Guide

### IP Allowlist Security

**Default**: `["127.0.0.1/32"]` - blocks all external access

Configure `allowed_ingress_cidrs` in [terraform.tfvars](terraform.tfvars):

```hcl
# Single IP
allowed_ingress_cidrs = ["203.0.113.10/32"]

# Multiple IPs/ranges
allowed_ingress_cidrs = ["203.0.113.10/32", "198.51.100.0/24"]

# Office network
allowed_ingress_cidrs = ["YOUR.OFFICE.IP/28"]

# Public access (not recommended)
allowed_ingress_cidrs = ["0.0.0.0/0"]
```

After changing, apply the update:
```bash
terraform apply -target=module.open_webui_service.aws_vpc_security_group_ingress_rule.open_webui_alb_ingress_https
terraform apply -target=module.open_webui_service.aws_vpc_security_group_ingress_rule.open_webui_alb_ingress_http
```

### AWS Cognito SSO Setup

1. **Create Cognito User Pool** (if not already done)
2. **Configure App Client**:
   - Create an app client with client secret
   - Set callback URL: `https://your-domain.com/oauth/callback`
   - Enable OAuth 2.0 flows

3. **Update terraform.tfvars**:
```hcl
enable_oauth_signup       = true
oauth_provider_name       = "Company SSO"
cognito_user_pool_id      = "us-east-1_ABC123"
cognito_app_client_id     = "your-client-id"
cognito_app_client_secret = "your-client-secret"
oauth_allowed_domains     = "company.com"
disable_local_auth        = true   # Optional: disable password login
force_oauth_login         = true   # Optional: force SSO
```

### Resource Sizing

Adjust in [terraform.tfvars](terraform.tfvars):

```hcl
# Small (development)
open_webui_task_cpu   = 512   # 0.5 vCPU
open_webui_task_mem   = 1024  # 1 GB
open_webui_task_count = 1

# Medium (production)
open_webui_task_cpu   = 1024  # 1 vCPU
open_webui_task_mem   = 2048  # 2 GB
open_webui_task_count = 2

# Large (high traffic)
open_webui_task_cpu   = 2048  # 2 vCPU
open_webui_task_mem   = 4096  # 4 GB
open_webui_task_count = 3
```

### AWS WAF Configuration

**Default**: WAF is enabled with AWS Managed Rule Groups

The WAF configuration includes:
1. **Amazon IP Reputation List** - Blocks known malicious IPs
2. **Common Rule Set** - OWASP Top 10 protection
3. **Known Bad Inputs** - Exploit pattern blocking
4. **Linux Rule Set** - Linux-specific protections
5. **PHP Rule Set** - PHP vulnerability protection

#### Enable/Disable WAF

In [terraform.tfvars](terraform.tfvars):

```hcl
# Enable WAF (recommended for production)
enable_waf = true

# Optional: Enable WAF logging to CloudWatch
waf_enable_logging     = true
waf_log_retention_days = 7  # Days to keep logs
```

#### Importing Existing WAF

If you manually created a WAF, see [WAF_IMPORT.md](WAF_IMPORT.md) for step-by-step import instructions.

#### Monitoring WAF Activity

**View blocked requests in AWS Console:**
- Navigate to **WAF & Shield** → **Web ACLs** → **openwebui-waf**
- Click **Overview** tab to see request metrics
- Click **Sampled requests** tab to see blocked traffic

**CloudWatch Metrics:**
```bash
# View WAF metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/WAFV2 \
  --metric-name BlockedRequests \
  --dimensions Name=Rule,Value=ALL Name=WebACL,Value=openwebui-waf \
  --statistics Sum \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300
```

**WAF Logs (if enabled):**
```bash
aws logs tail /aws/wafv2/openwebui --follow
```

## Remote State Setup (Recommended)

For team collaboration and state safety, configure remote state storage:

See [bootstrap/README.md](bootstrap/README.md) for detailed instructions.

**Quick summary**:
```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with unique bucket name
terraform init && terraform apply

cd ..
cp backend.tf.example backend.tf
# Edit backend.tf with bucket/table names from bootstrap output
terraform init -migrate-state
```

## Operations

### Viewing Logs

**ECS Task Logs**:
```bash
aws logs tail /ecs/openwebui-service --follow
```

**Lambda Initialization Logs**:
```bash
aws logs tail /aws/lambda/openwebui-admin-init --follow
```

### Scaling

Update `open_webui_task_count` in terraform.tfvars:
```hcl
open_webui_task_count = 5  # Scale to 5 tasks
```

Apply changes:
```bash
terraform apply -target=module.open_webui_service.aws_ecs_service.open_webui
```

### Updating Open WebUI Version

Update the image tag in terraform.tfvars:
```hcl
open_webui_image_url = "ghcr.io/open-webui/open-webui:v0.2.0"
```

Apply and force new deployment:
```bash
terraform apply
aws ecs update-service --cluster openwebui-cluster --service openwebui-service --force-new-deployment
```

### Destroying Infrastructure

**Warning**: This will delete all data including databases and files!

```bash
terraform destroy
```

To preserve data, first:
1. Take RDS snapshot
2. Backup EFS data
3. Export important conversations/settings

## Troubleshooting

### Issue: Cannot access Open WebUI (403/timeout)

**Solution**: Check IP allowlist configuration
```bash
# Get your current IP
curl ifconfig.me

# Verify security group rules
aws ec2 describe-security-groups --group-ids <alb-sg-id>
```

Update `allowed_ingress_cidrs` in terraform.tfvars and reapply.

### Issue: Admin user not created

**Solution**: Check Lambda logs
```bash
aws logs tail /aws/lambda/openwebui-admin-init --follow
```

Manually trigger Lambda:
```bash
aws lambda invoke --function-name openwebui-admin-init response.json
cat response.json
```

### Issue: Service won't start / unhealthy

**Solution**: Check ECS task logs
```bash
# Get task ARN
aws ecs list-tasks --cluster openwebui-cluster --service openwebui-service

# Get task details
aws ecs describe-tasks --cluster openwebui-cluster --tasks <task-arn>

# View logs
aws logs tail /ecs/openwebui-service --follow
```

Common causes:
- Database connection issues (check RDS security group)
- EFS mount issues (check EFS mount targets)
- Out of memory (increase `open_webui_task_mem`)

### Issue: OAuth/SSO not working

**Solution**: Verify Cognito configuration
1. Check callback URL matches: `https://your-domain.com/oauth/callback`
2. Verify client secret is correct
3. Check CloudWatch logs for OAuth errors
4. Ensure Cognito User Pool is in same region

## Security Best Practices

1. **IP Allowlist**: Always restrict `allowed_ingress_cidrs` to known IPs
2. **Secrets Rotation**: Regularly rotate admin credentials in Secrets Manager
3. **Monitoring**: Enable CloudTrail and CloudWatch alarms
4. **Backups**: Enable automated RDS snapshots and EFS backups
5. **Updates**: Keep Open WebUI and Terraform providers updated
6. **IAM**: Use least-privilege IAM roles
7. **SSL/TLS**: Ensure ACM certificate is valid and auto-renewing

## Cost Estimates

Approximate monthly costs (us-east-1, low traffic):

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| ECS Fargate | 1 task (1 vCPU, 2GB) | ~$30 |
| RDS PostgreSQL | db.t3.micro | ~$15 |
| EFS | 1GB storage | ~$0.30 |
| ALB | 1 ALB | ~$16 |
| AWS WAF | Web ACL + 5 rule groups | ~$11 |
| Data Transfer | 10GB | ~$1 |
| **Total** | | **~$73/month** |

Scale up (3 tasks, db.t3.small): **~$141/month**

**Note**: WAF costs ~$11/month base ($5 for Web ACL + ~$6 for managed rule groups). Additional charges apply per million requests ($0.60/million).

## Files Structure

```
.
├── main.tf                    # Root module configuration
├── variables.tf               # Input variables
├── outputs.tf                 # Output values
├── terraform.tfvars.example   # Configuration template
├── backend.tf.example         # Remote state template
├── WAF_IMPORT.md              # Guide for importing existing WAF
├── bootstrap/                 # Remote state infrastructure
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── README.md
└── modules/
    └── open-webui-service/    # Main service module
        ├── ecs-related.tf     # ECS cluster, service, task definition
        ├── efs-related.tf     # EFS file system and mount targets
        ├── rds-related.tf     # RDS PostgreSQL database
        ├── pub-alb-related.tf # ALB, security groups, Route53
        ├── waf-related.tf     # WAF Web ACL and managed rules
        ├── lambda-admin-init.tf  # Admin user initialization
        ├── locals.tf          # Local variables
        ├── variables.tf       # Module inputs
        └── outputs.tf         # Module outputs
```

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This infrastructure code is provided as-is for educational and production use.

Open WebUI is licensed under the MIT License. See the [Open WebUI repository](https://github.com/open-webui/open-webui) for details.

## Support

- **Open WebUI Issues**: https://github.com/open-webui/open-webui/issues
- **AWS Documentation**: https://docs.aws.amazon.com/
- **Terraform Docs**: https://www.terraform.io/docs

## Acknowledgments

- [Open WebUI](https://github.com/open-webui/open-webui) - Amazing self-hosted AI interface
- AWS for the robust cloud infrastructure
- HashiCorp Terraform for infrastructure-as-code

---

**Built with** [Claude Code](https://claude.com/claude-code)
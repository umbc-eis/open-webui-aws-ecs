# Importing Existing WAF into Terraform

This guide explains how to import your manually-created "OpenWebUI-WAF" into Terraform management.

## Overview

You currently have a manually configured WAF Web ACL named "OpenWebUI-WAF" with the following AWS Managed Rule Groups:
1. **Amazon IP Reputation List** - Blocks known malicious IPs
2. **Common Rule Set (OWASP Top 10)** - Web vulnerability protection with custom overrides
3. **Known Bad Inputs** - Blocks exploit patterns
4. **Linux Rule Set** - Linux-specific protections
5. **PHP Rule Set** - PHP-specific protections

The Terraform configuration has been created to match your existing setup exactly.

## Prerequisites

- Terraform initialized in your project
- AWS CLI configured with appropriate permissions
- Your existing WAF is named "OpenWebUI-WAF" with ID: `6122ca7b-2310-4197-8015-f3deafb8a766`

## Import Steps

### Step 1: Update Your Configuration

Ensure your `terraform.tfvars` includes WAF configuration:

```hcl
# Enable WAF (default is true)
enable_waf = true

# Optional: Enable WAF logging
waf_enable_logging     = false
waf_log_retention_days = 7
```

### Step 2: Initialize Terraform

Run terraform init to ensure the new WAF resources are recognized:

```bash
terraform init
```

### Step 3: Import the WAF Web ACL

Import your existing WAF Web ACL into Terraform state:

```bash
terraform import 'module.open_webui_service.aws_wafv2_web_acl.openwebui[0]' \
  '6122ca7b-2310-4197-8015-f3deafb8a766/OpenWebUI-WAF/REGIONAL'
```

**Format**: `<ID>/<Name>/<Scope>`
- ID: `6122ca7b-2310-4197-8015-f3deafb8a766`
- Name: `OpenWebUI-WAF`
- Scope: `REGIONAL`

### Step 4: Import the WAF-ALB Association

Check if your WAF is already associated with the ALB:

```bash
# Get your ALB ARN
aws elbv2 describe-load-balancers --region us-east-1 \
  --query 'LoadBalancers[?contains(LoadBalancerName, `openwebui`)].LoadBalancerArn' \
  --output text
```

Then import the association (replace `<ALB-ARN>` with actual ARN):

```bash
terraform import 'module.open_webui_service.aws_wafv2_web_acl_association.openwebui_alb[0]' \
  'arn:aws:wafv2:us-east-1:970547376696:regional/webacl/OpenWebUI-WAF/6122ca7b-2310-4197-8015-f3deafb8a766,<ALB-ARN>'
```

**Note**: If this fails with "resource not found", the association doesn't exist yet and Terraform will create it automatically.

### Step 5: Verify Import

Run a plan to verify the import was successful:

```bash
terraform plan
```

Expected output:
- **If WAF logging is disabled** (default): Should show "No changes" or only plan to create logging resources
- **If import successful**: No changes to the WAF Web ACL itself
- **If association didn't exist**: Plan will show creation of the WAF-ALB association

### Step 6: Apply Any Remaining Changes

If Terraform wants to create the WAF-ALB association or logging resources:

```bash
terraform apply
```

Review the plan carefully and type `yes` to apply.

## Verification

After import, verify everything is working:

### 1. Check Terraform State

```bash
# List WAF resources in state
terraform state list | grep waf

# Show WAF details
terraform state show 'module.open_webui_service.aws_wafv2_web_acl.openwebui[0]'
```

### 2. Verify in AWS Console

- Navigate to **WAF & Shield** → **Web ACLs**
- Select **OpenWebUI-WAF**
- Check that it shows all 5 rules with correct priorities
- Verify it's associated with your ALB

### 3. Test WAF Protection

```bash
# Test that legitimate traffic works
curl -I https://your-openwebui-domain.com

# Test that malicious patterns are blocked (optional)
curl -I "https://your-openwebui-domain.com/?test=<script>alert(1)</script>"
```

## Important Notes

### Resource Naming

After import, Terraform will manage the WAF with the name pattern `${var.prefix}-waf` (default: `openwebui-waf`). Your existing WAF is named `OpenWebUI-WAF`.

**Options:**
1. **Keep existing name**: Override the prefix in your module variables
2. **Let Terraform rename**: On next apply, Terraform will rename to match configuration

To keep the existing name, add to `terraform.tfvars`:
```hcl
# This is in the module variables (would need to be added)
# For now, just be aware the name will change from "OpenWebUI-WAF" to "openwebui-waf"
```

### Rule Overrides

Your current configuration has 4 rule overrides in the Common Rule Set set to "Count" mode:
- `NoUserAgent_HEADER`
- `SizeRestrictions_BODY`
- `GenericLFI_BODY`
- `CrossSiteScripting_BODY`

These are already configured in the Terraform code to match your existing setup.

### CloudWatch Metrics

All rules have CloudWatch metrics enabled with the same metric names as your current configuration. No changes are needed.

## Troubleshooting

### Import Fails: "Resource Not Found"

**Problem**: WAF Web ACL import returns error

**Solution**: Verify the WAF ID, name, and scope:
```bash
aws wafv2 list-web-acls --scope REGIONAL --region us-east-1
aws wafv2 get-web-acl --scope REGIONAL --region us-east-1 \
  --name OpenWebUI-WAF --id 6122ca7b-2310-4197-8015-f3deafb8a766
```

### Import Succeeds but Plan Shows Changes

**Problem**: `terraform plan` shows modifications to the WAF

**Possible causes**:
1. **Name mismatch**: Terraform wants to use `openwebui-waf` instead of `OpenWebUI-WAF`
2. **Tag differences**: Terraform adds tags like `ManagedBy = "terraform"`
3. **Description differences**: Current description is "As named", Terraform uses different text

**Solution**: Review the plan carefully. If changes are only cosmetic (tags, description), apply them:
```bash
terraform apply
```

### Association Already Exists Error

**Problem**: Import of association says it already exists

**Solution**: This is expected! Just skip the association import step. Terraform import will handle it on next plan/apply.

### Can't Find ALB ARN

**Problem**: Don't know your ALB ARN for association import

**Solution**: Get it from Terraform outputs:
```bash
terraform output -json | jq -r '.alb.value.arn'
```

Or from AWS CLI:
```bash
aws elbv2 describe-load-balancers --region us-east-1 \
  --query 'LoadBalancers[?contains(LoadBalancerName, `openwebui`)].LoadBalancerArn' \
  --output text
```

## Next Steps

After successful import:

1. **Enable WAF Logging** (optional but recommended):
   ```hcl
   waf_enable_logging = true
   ```
   Then run `terraform apply`

2. **Monitor WAF Activity**:
   - AWS Console: **WAF & Shield** → **OpenWebUI-WAF** → **Overview**
   - CloudWatch Metrics: Check metrics for each rule group

3. **Review Blocked Requests**:
   - AWS Console: **WAF & Shield** → **OpenWebUI-WAF** → **Sampled requests**
   - Adjust rule overrides if needed

4. **Commit Changes**:
   ```bash
   git add modules/open-webui-service/waf-related.tf
   git add variables.tf main.tf
   git commit -m "Add WAF configuration and import existing WAF"
   ```

## WAF Cost Estimate

Current configuration cost (approximate):
- **Web ACL**: $5.00/month
- **Rules** (5 managed rule groups): ~$6.00/month (varies by rule group)
- **Requests**: $0.60 per million requests
- **Logging** (if enabled): CloudWatch Logs pricing

**Total**: ~$11-15/month base + request costs

## Additional Resources

- [AWS WAF Pricing](https://aws.amazon.com/waf/pricing/)
- [AWS Managed Rules](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups.html)
- [Terraform WAFv2 Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl)
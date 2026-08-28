# Open WebUI on AWS Fargate

Deploy [Open WebUI](https://github.com/open-webui/open-webui) on AWS using ECS Fargate, Aurora Serverless v2, and a custom container image with extra Python libraries layered on top of the upstream image. Terraform-managed end to end.

## Overview

| Component | Role |
|---|---|
| **ECS Fargate (ARM64)** | Runs the Open WebUI container; configurable CPU/memory/task-count |
| **Aurora Serverless v2 (PostgreSQL)** | App data, conversations, users — and the **pgvector** store for RAG embeddings |
| **EFS** | Shared file storage mounted into every task |
| **ECR (`openwebui-umbc`)** | Custom image: upstream Open WebUI + `reportlab` for the document-generation tools |
| **Application Load Balancer** | Internet-facing HTTPS endpoint (TLS via ACM) |
| **AWS WAF v2** | Managed rule groups (OWASP, IP reputation, known-bad-inputs, Linux, PHP) — primary public-internet gate |
| **AWS Cognito (optional)** | OAuth/OIDC SSO; can be set to fully replace local auth |
| **Lambda** | One-shot admin user bootstrap on first deploy |
| **Secrets Manager** | DB master password, admin credentials, WEBUI_SECRET_KEY, Cognito client secret |
| **Route53 + ACM** | DNS + TLS certificate |

```
Internet ──► WAF ──► ALB (HTTPS, 0.0.0.0/0) ──► ECS Fargate (ARM64)
                                                  │
                                                  ├──► Aurora Serverless v2 (data + pgvector)
                                                  ├──► EFS (files)
                                                  └──► Secrets Manager (creds)

Lambda ─► creates initial admin user, stores credentials in Secrets Manager
```

The ALB security group allows HTTPS from anywhere on the internet. Access is gated by WAF (managed rule groups) plus the application's own auth (Cognito OAuth and/or local password). There is no IP allowlist at the SG level.

## Prerequisites

- **AWS account** with VPC, ECS, RDS, EFS, Lambda, ALB, Route53, ACM, ECR, Secrets Manager, WAF, IAM permissions.
- **Existing VPC** with public subnets (for the ALB) and private subnets (for ECS and Aurora).
- **Route53 hosted zone** + **ACM certificate** covering the domain you'll point at the ALB.
- **Terraform** ≥ 1.0, **AWS CLI**, **Docker** (with `buildx`) for image builds.
- Optional: **AWS Cognito User Pool** if you want SSO.

## Repository layout

```
.
├── main.tf, variables.tf, outputs.tf    # Root module
├── backend.tf                            # S3 backend stub (use_lockfile = true)
├── backend.hcl.example                   # Copy to backend.hcl with real bucket name
├── terraform.tfvars.example              # Copy to terraform.tfvars and fill in
├── WAF_IMPORT.md                         # Importing an existing WAF Web ACL
├── bootstrap/                            # One-time: creates the S3 state bucket
├── modules/open-webui-service/           # The actual service module
│   ├── ecs-related.tf                    # Cluster, service, task def, log group
│   ├── ecr-related.tf                    # ECR repo for the custom image
│   ├── efs-related.tf                    # File system + mount targets
│   ├── rds-related.tf                    # Aurora Serverless v2 cluster + instance
│   ├── pub-alb-related.tf                # ALB, listener, SG, Route53 record
│   ├── waf-related.tf                    # WAF Web ACL + managed rule groups
│   ├── lambda-admin-init.tf              # Admin bootstrap Lambda
│   └── locals.tf, variables.tf, outputs.tf, providers.tf
├── docker/                               # Custom image overlay
│   ├── Dockerfile                        # FROM ${BASE_IMAGE}, layer in extras
│   └── requirements-extras.txt           # Pinned pip deps (reportlab)
├── scripts/
│   ├── build-and-push.sh                 # Build + push the custom image to ECR
│   ├── config.sh                         # Share terraform.tfvars via the state bucket
│   └── reembed-files.py                  # One-shot pgvector backfill helper
└── tools/                                # Open WebUI tool source files (see tools/README.md)
```

## First-time deploy

### 1. Bootstrap remote state

The main project's state lives in S3. Create the bucket once per AWS account:

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set a globally-unique bucket name
terraform init
terraform apply
cd ..
```

Note the `s3_bucket_name` output — you'll plug it into `backend.hcl`.

> **Note on locking:** the main backend uses S3-native locking (`use_lockfile = true`). The bootstrap module currently also provisions a DynamoDB lock table; that table is now unused and will be removed in a follow-up. You don't need to reference it anywhere.

See [bootstrap/README.md](bootstrap/README.md) for details.

### 2. Configure the backend

```bash
cp backend.hcl.example backend.hcl
# Edit backend.hcl with your bucket name from step 1
```

`backend.hcl` is gitignored. Each user/environment maintains their own.

### 3. Configure the deployment

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your VPC IDs, domain, certificate ARN, admin email, etc. `terraform.tfvars` is gitignored — it contains credentials.

For the **first** apply, leave `open_webui_image_url` pointing at the upstream image:

```hcl
open_webui_image_url = "ghcr.io/open-webui/open-webui:v0.11.0"
```

This lets you bring up the stack before the custom image exists. We'll swap it for the ECR-hosted custom image in step 5.

### 4. Initial apply

```bash
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

This takes ~10–15 minutes and creates everything including the `openwebui-umbc` ECR repository. After it completes:

- The Lambda will create the admin user and store credentials in Secrets Manager.
- The Aurora cluster is up but the app is running the upstream image — the PDF tool won't work yet because `reportlab` isn't installed.

### 5. Build and push the custom image

```bash
./scripts/build-and-push.sh
```

The script:
- Reads the current `open_webui_image_url` from `terraform.tfvars` to learn the upstream tag.
- Logs into ECR.
- Builds `docker/Dockerfile` for `linux/arm64` via `buildx`, layering `docker/requirements-extras.txt` onto the upstream image.
- Pushes to `${account}.dkr.ecr.${region}.amazonaws.com/openwebui-umbc:${upstream_tag}-extras1` (and `:latest`).

The final line prints the new image URL.

### 6. Switch to the custom image

Update `terraform.tfvars`:

```hcl
open_webui_image_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/openwebui-umbc:v0.11.0-extras1"
```

Apply:

```bash
terraform apply
```

ECS rolls onto the new image. The document-generation tools (Word, PowerPoint, Spreadsheet, PDF) now have their dependencies.

### 7. Install the tools

Tools are stored in the Open WebUI database, not Terraform. Paste each `tools/*.py` file into **Workspace → Tools** through the admin UI. See [tools/README.md](tools/README.md) for the full workflow.

### 8. Retrieve admin credentials

```bash
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw admin_credentials_secret_arn) \
  --query SecretString --output text | jq
```

Log in at your configured domain with the email and password from the secret.

## Day-2 operations

### Updating Open WebUI to a newer upstream version

```bash
OPENWEBUI_UPSTREAM=vX.Y.Z ./scripts/build-and-push.sh
```

The `OPENWEBUI_UPSTREAM` env var is required once `terraform.tfvars` is already pointing at ECR (the script can't infer the upstream tag from an ECR URL). Then update `open_webui_image_url` in `terraform.tfvars` to the new tag and `terraform apply`.

That plain rolling apply is fine for most releases. It is **not** safe for a release that changes the database schema — see below.

#### If a release requires database migrations

Don't rely on the release notes to tell you. They frequently don't: v0.11.1 added three Alembic revisions and its release body never mentions a migration. Diff the migration directory between the deployed tag and the target tag instead:

```bash
gh api repos/open-webui/open-webui/compare/<deployed-tag>...<target-tag> \
  -q '.files[] | select(.filename | test("migrations/versions")) | "\(.status)\t\(.filename)"'
```

Any `added` line means upstream has changed the schema and a plain `terraform apply` will break the service. (`modified` lines on existing revisions are harmless — Alembic tracks revision ids, so an already-applied revision is never re-run.) This deployment runs several tasks behind an ALB with `deployment_minimum_healthy_percent = 100` and `deployment_maximum_percent = 200`, so an apply is a rolling replacement: new tasks migrate the shared Aurora schema while the old tasks are still serving traffic against it. Upstream states that rolling updates are unsupported for schema-changing releases and will cause application failures.

The `deployment_circuit_breaker` block compounds this — if a new task fails its health check after migrating, ECS rolls the task definition back to the previous image pointed at the already-migrated schema, with no corresponding database rollback.

Two properties of upstream's migration runner shape the procedure below:

- **Migrations run before the port opens.** `run_migrations()` is invoked at import time in `backend/open_webui/config.py`, so the container is unreachable for the full duration of the migration. `open_webui_health_check_grace_period` (default 600s) is what stops the target group from marking the task unhealthy and ECS from killing it mid-migration. Raise it if you expect a long migration — index builds on a large `chat` table are the usual culprit.
- **Migration failures are silent.** That same function swallows exceptions (`except Exception: log.exception(...)`). A failed migration does *not* crash the container: the app boots on a partially migrated schema and passes the `/` health check. You cannot infer success from a healthy task — check the logs.

In that case, take the downtime and cut over in stages. Note your current `open_webui_task_count` first; you restore it in step 5.

```bash
# 1. Snapshot Aurora first. Get the cluster id from the console, or:
#    aws rds describe-db-clusters --query 'DBClusters[].DBClusterIdentifier'
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier <cluster-id> \
  --db-cluster-snapshot-identifier openwebui-pre-vX-Y-Z

# 2. Point at the new image and drain all tasks in one apply. Downtime starts
#    here. Setting the image now is safe because the desired count is 0, and it
#    registers the new task definition up front so step 3 launches immediately.
#    Set open_webui_image_url to the new tag AND open_webui_task_count = 0
terraform apply

# 2b. Skip the ALB drain. Scaling to 0 leaves the old tasks draining against the
#     target group's deregistration_delay (300s by default, and Open WebUI's
#     socket.io connections stop it finishing early). That is pure dead time —
#     the tasks are already out of service. Stop them directly; the desired
#     count is already 0, so ECS will not replace them.
aws ecs list-tasks --cluster <prefix>-ecs --service-name <prefix>-svc \
  --query 'taskArns' --output text | tr '\t' '\n' | while read -r t; do
    aws ecs stop-task --cluster <prefix>-ecs --task "$t" --reason "upgrade window"
  done

# 3. Bring up exactly one task so migrations run alone. Every task calls
#    run_migrations() at import, and concurrent "alembic upgrade head" over the
#    same revisions is a race — do not scale straight to full capacity.
#    Set open_webui_task_count = 1
terraform apply

# 4. Confirm the migrations ran and the task is healthy before going further.
#    Expect one "Running upgrade <from> -> <to>" line per revision the diff
#    listed as added, and NO "Error running migrations" line. A healthy task
#    alone proves nothing — see the note on silent failures above.
aws logs tail /ecs/<prefix> --follow
curl -s https://<your-domain>/api/version

# 5. Restore capacity to the value from before step 2.
terraform apply
```

Steps 2–4 are the downtime window. With the drain skipped it is a few minutes; the v0.11.0 → v0.11.1 upgrade measured about two. Fargate cold start (ENI provisioning plus a large image pull) is usually the bigger share, but a release that builds indexes on `chat` or `chat_message` can outweigh it on a large database. Take the snapshot in step 1 *before* draining, so it costs no downtime — a snapshot of a running cluster is crash-consistent and Postgres recovers from it. Don't skip it: a failed migration is recovered by restoring the snapshot, not by reverting the image tag.

Restoring capacity in step 5 does not have to wait for the first task to pass its health checks. Once the logs confirm the migrations, apply immediately — the remaining tasks boot in parallel with the ALB ramp and their own `run_migrations()` calls are no-ops.

Avoid `-target` for these applies. The module is `module.open_webui_service`, and a `-target` naming a module that doesn't exist plans zero changes and reports success without doing anything.

### Sharing configuration with other operators

`terraform.tfvars` is gitignored — this repo is public, and the file carries the
VPC and subnet ids, the Cognito pool/client ids and the ALB certificate ARN.
It contains no secrets (the OAuth client secret lives in Secrets Manager), but
it is still environment-specific and shouldn't be published.

The shared copy lives in the Terraform state bucket, which is already versioned,
encrypted and closed to public access, and which every operator can already
reach. `scripts/config.sh` reads the bucket name from your `backend.hcl`, so it
is never hardcoded here.

```bash
./scripts/config.sh pull       # fetch the shared config before you plan
./scripts/config.sh diff       # see how your local copy differs
./scripts/config.sh push       # publish your changes for everyone else
./scripts/config.sh versions    # history, with a restore command
```

Push after any change others need — most often a new `open_webui_image_url`
following an upgrade. `pull` and `push` both show a diff and refuse to clobber
differing content unless you pass `--yes`.

Two things this deliberately does not solve. There is no locking, so coordinate
before pushing; and nothing forces you to push, so the bucket can lag reality.
The authoritative record of what is actually deployed is the Terraform state
plus the ECR tag list, not this file.

Someone setting up a **new** deployment doesn't need any of the above — they
start from `terraform.tfvars.example` and the [First-time deploy](#first-time-deploy)
steps.

### Adding a Python dependency for a tool

1. Pin the version in `docker/requirements-extras.txt` (only add libs that aren't already in upstream's `backend/requirements.txt`).
2. Bump the tag suffix and rebuild:
   ```bash
   ./scripts/build-and-push.sh --tag-suffix extras2
   ```
3. Update `open_webui_image_url` in `terraform.tfvars` to the new `-extras2` tag.
4. `terraform apply`.

### Re-embedding files after the pgvector cutover (one-shot)

Files uploaded under the previous ChromaDB-backed vector store don't appear in pgvector after the switch. To backfill:

```bash
export OPENWEBUI_BASE_URL="$(terraform output -raw open_webui_url)"
export OPENWEBUI_ADMIN_TOKEN="$(get-admin-api-key)"
python3 scripts/reembed-files.py            # process pending/failed files
python3 scripts/reembed-files.py --status   # check progress
python3 scripts/reembed-files.py --reset    # start fresh
```

State is tracked in `scripts/reembed-state.json` (gitignored) so re-runs only retry failures.

### Viewing logs

```bash
# Application
aws logs tail /ecs/openwebui-service --follow

# Admin-bootstrap Lambda
aws logs tail /aws/lambda/openwebui-admin-init --follow

# WAF (if waf_enable_logging = true)
aws logs tail /aws/wafv2/openwebui --follow
```

Container Insights is set to `enhanced` — per-task and per-container metrics are in CloudWatch under `ECS/ContainerInsights`.

### Scaling

Update `open_webui_task_count`, `open_webui_task_cpu`, or `open_webui_task_mem` in `terraform.tfvars` and `terraform apply`. Aurora scales automatically between `min_capacity` and `max_capacity` ACU (currently 0.5 → 4.0).

### Destroying

```bash
terraform destroy
```

**Warning:** wipes the Aurora cluster (final snapshot is taken — see `final_snapshot_identifier` in `rds-related.tf`), the EFS file system, and Secrets Manager entries (subject to the 7-day recovery window).

## Configuration reference

### OAuth/SSO (AWS Cognito)

1. Create a Cognito User Pool + App Client (with client secret).
2. Set the callback URL to `https://your-domain.com/oauth/oidc/callback`.
3. Put the client secret in Secrets Manager **before the first apply**. Terraform
   looks this secret up by name and injects it into the container through the ECS
   `secrets` mechanism, so the value never lands in the task definition, in
   Terraform state, or in `terraform.tfvars`. Store it as a raw string, not JSON:

   ```bash
   aws secretsmanager create-secret \
     --name openwebui-oauth-client-secret \
     --description "Open WebUI OAuth client secret" \
     --secret-string '<client-secret-from-cognito>'
   ```

   Override the name with `cognito_client_secret_name` if you use a different
   convention. To rotate: `aws secretsmanager put-secret-value` with the new
   value, then force a new deployment so tasks re-read it — secrets are resolved
   at task start, not on the fly.

   ```bash
   aws ecs update-service --cluster openwebui-ecs \
     --service openwebui-svc --force-new-deployment
   ```

4. In `terraform.tfvars`:
   ```hcl
   enable_oauth_signup   = true
   oauth_provider_name   = "Company SSO"
   cognito_user_pool_id  = "us-east-1_ABC123"
   cognito_app_client_id = "..."
   oauth_allowed_domains = "company.com"   # or "*"
   disable_local_auth    = true            # optional: kill password login
   force_oauth_login     = true            # optional: skip the local-login form
   ```

   If the secret is missing or unreadable, tasks fail to start with
   `ResourceInitializationError`. With `force_oauth_login = true` there is no
   other way in, so verify the secret exists before applying.

### WAF

Enabled by default. Disable with `enable_waf = false`. Enable request logging with `waf_enable_logging = true` (CloudWatch Log Group `/aws/wafv2/openwebui`, retention `waf_log_retention_days`).

To import an existing manually-created Web ACL into this Terraform state, see [WAF_IMPORT.md](WAF_IMPORT.md).

### Resource sizing rules of thumb

| Load | Task size | Task count | Aurora max ACU |
|---|---|---|---|
| Dev / demo | 512 CPU / 1 GB | 1 | 1.0 |
| Small prod | 1024 CPU / 2 GB | 2 | 2.0 |
| Standard prod (default) | 1024 CPU / 2 GB | 3 | 4.0 |
| Heavy RAG | 2048 CPU / 4 GB | 3 | 8.0 |

pgvector embedding workloads land on Aurora — bump max ACU before you see throttling.

## Cost estimates

Rough monthly cost for the **default standard-prod** sizing in `us-east-1`. Aurora and WAF dominate; everything else is small.

| Service | Configuration | Approx monthly |
|---|---|---|
| ECS Fargate (ARM64) | 3 tasks × (1 vCPU, 2 GB), 24/7 | ~$72 |
| Aurora Serverless v2 | 0.5–4.0 ACU, avg ~1.5 ACU, storage ~$0.10/GB-mo | ~$130–250 |
| EFS | Few GB, infrequent access | <$5 |
| ALB | 1 ALB + low LCU | ~$22 |
| WAF | Web ACL + 5 managed rule groups | ~$11 (+ $0.60 / M requests) |
| ECR | <1 GB stored, occasional pulls | <$1 |
| CloudWatch (enhanced Container Insights) | 3 tasks | ~$10–20 |
| Secrets Manager | 4 secrets | ~$2 |
| Route53 hosted zone | 1 zone | $0.50 |
| **Total** | | **~$250–380/mo** |

Numbers are ballpark — Aurora ACU usage swings the total by a lot. If the cluster sits idle, expect closer to the low end; under embedding-heavy load, closer to the high end. CloudWatch Container Insights (enhanced tier) is not free — disable it (`containerInsights = "disabled"` in `ecs-related.tf`) if cost matters more than observability.

## Troubleshooting

**Can't reach the URL (timeout)**
- Check ALB target group health: `aws elbv2 describe-target-health --target-group-arn ...`
- Check WAF blocked requests: WAF console → `openwebui-waf` → Sampled requests.

**403 from the app**
- Likely WAF. Confirm in the WAF Sampled-requests view.

**Admin user wasn't created**
```bash
aws logs tail /aws/lambda/openwebui-admin-init --follow
aws lambda invoke --function-name openwebui-admin-init response.json && cat response.json
```

**Tasks won't start / unhealthy**
- DB connection: check the Aurora SG allows ingress from the ECS SG (see `rds-related.tf`).
- EFS mount: check mount targets exist in each AZ.
- OOM: bump `open_webui_task_mem`.
- Image pull: confirm the task execution role can pull from ECR (the default policy includes `AmazonECSTaskExecutionRolePolicy`).

**Vector search returns nothing for old files**
- Run `scripts/reembed-files.py` (see day-2 ops).

**OAuth callback fails**
- Callback URL must be `https://your-domain.com/oauth/oidc/callback` (note `/oidc/` — not `/callback`).
- Cognito User Pool must be in the same region as the deployment (or the issuer URL needs to be set accordingly).

## License

This infrastructure is provided as-is. [Open WebUI](https://github.com/open-webui/open-webui) is MIT-licensed.

---

**Built with** [Claude Code](https://claude.com/claude-code)

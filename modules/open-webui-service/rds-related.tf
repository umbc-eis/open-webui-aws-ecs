# Aurora Serverless v2 PostgreSQL for Open WebUI
# Provides scalable, reliable database for multi-container deployments

# Generate unique suffix for secrets (allows recreation after destroy)
resource "random_id" "secret_suffix" {
  byte_length = 4
  keepers = {
    # Change this to force new secret names (e.g., after intentional destroy)
    prefix = var.prefix
  }
}

# Generate random password for database
resource "random_password" "db_master_password" {
  length  = 32
  special = true
  # Exclude characters that might cause issues in connection strings
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Generate random password for admin user
resource "random_password" "admin_password" {
  length           = 20
  special          = true
  override_special = "!@#$%^&*()-_=+[]{}|:,.<>?"
}

# Generate random secret key for JWT tokens (important for multi-container)
resource "random_password" "webui_secret_key" {
  length  = 64
  special = true
}

# Store password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_master_password" {
  name                    = "${var.prefix}-db-master-password-${random_id.secret_suffix.hex}"
  description             = "Master password for Open WebUI Aurora database"
  recovery_window_in_days = 7

  tags = {
    "Name" : "${var.prefix}-db-master-password"
  }
}

resource "aws_secretsmanager_secret_version" "db_master_password" {
  secret_id = aws_secretsmanager_secret.db_master_password.id
  secret_string = jsonencode({
    username = "openwebui_admin"
    password = random_password.db_master_password.result
  })
}

# Store admin user credentials in Secrets Manager
resource "aws_secretsmanager_secret" "admin_credentials" {
  name                    = "${var.prefix}-admin-credentials-${random_id.secret_suffix.hex}"
  description             = "Initial admin user credentials for Open WebUI"
  recovery_window_in_days = 7

  tags = {
    "Name" : "${var.prefix}-admin-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "admin_credentials" {
  secret_id = aws_secretsmanager_secret.admin_credentials.id
  secret_string = jsonencode({
    name             = var.admin_name
    email            = var.admin_email
    password         = random_password.admin_password.result
    webui_secret_key = random_password.webui_secret_key.result
    instructions     = "Use this email and password to create the first admin account. The first user to sign up will automatically be an admin."
  })
}

# DB Subnet Group
resource "aws_db_subnet_group" "open_webui" {
  name       = "${var.prefix}-db-subnet-group"
  subnet_ids = var.ecs_subnet_ids

  tags = {
    "Name" : "${var.prefix}-db-subnet-group"
  }
}

# Security Group for Aurora
resource "aws_security_group" "aurora_sg" {
  name        = "${var.prefix}-aurora-sg"
  description = "Security group for Open WebUI Aurora database"
  vpc_id      = var.vpc_id

  tags = {
    "Name" : "${var.prefix}-aurora-sg"
  }
}

# Allow PostgreSQL access from ECS tasks
resource "aws_vpc_security_group_ingress_rule" "aurora_from_ecs" {
  security_group_id            = aws_security_group.aurora_sg.id
  description                  = "PostgreSQL access from ECS tasks"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.open_webui_sg.id
}

# Aurora Serverless v2 Cluster
resource "aws_rds_cluster" "open_webui" {
  cluster_identifier = "${var.prefix}-aurora-cluster"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = var.db_engine_version
  database_name      = "openwebui"
  master_username    = "openwebui_admin"
  master_password    = random_password.db_master_password.result

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.open_webui.name
  vpc_security_group_ids = [aws_security_group.aurora_sg.id]

  # Serverless v2 scaling
  serverlessv2_scaling_configuration {
    min_capacity = 0.5 # Minimum ACUs (Aurora Capacity Units)
    max_capacity = 4.0 # Maximum ACUs - adjust based on your needs
  }

  # Backup configuration - nightly snapshots with 30-day retention
  backup_retention_period      = 30
  preferred_backup_window      = "05:00-06:00" # 5-6 AM UTC
  preferred_maintenance_window = "sun:06:00-sun:07:00"

  # Snapshot configuration
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.prefix}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Security
  storage_encrypted = true

  # Enable enhanced monitoring
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # Apply changes immediately for faster updates
  apply_immediately = true

  tags = {
    "Name" : "${var.prefix}-aurora-cluster"
  }

  lifecycle {
    ignore_changes = [
      final_snapshot_identifier, # Prevent changes on every apply
      engine_version,            # Allow AWS auto-minor-upgrades without TF drift; major bumps handled out-of-band
    ]
  }
}

# Aurora Serverless v2 Instance
resource "aws_rds_cluster_instance" "open_webui" {
  identifier         = "${var.prefix}-aurora-instance-1"
  cluster_identifier = aws_rds_cluster.open_webui.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.open_webui.engine
  engine_version     = aws_rds_cluster.open_webui.engine_version

  # Performance insights
  performance_insights_enabled = true

  # Monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  tags = {
    "Name" : "${var.prefix}-aurora-instance-1"
  }

  lifecycle {
    ignore_changes = [
      engine_version, # Track the cluster's version (auto-upgraded by AWS)
    ]
  }
}

# IAM role for enhanced monitoring
resource "aws_iam_role" "rds_monitoring" {
  name               = "${var.prefix}-rds-monitoring-role"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json

  tags = {
    "Name" : "${var.prefix}-rds-monitoring-role"
  }
}

data "aws_iam_policy_document" "rds_monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

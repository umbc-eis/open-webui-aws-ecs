# EFS, mount target and etc
resource "aws_efs_file_system" "open_webui" {
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  protection {
    replication_overwrite = "ENABLED"
  }

  tags = {
    "Name" : "${var.prefix}-efs"
  }
}

# Mount target: for workloads in pvt subnets
resource "aws_efs_mount_target" "efs_to_pvt_subnets" {
  count = length(var.ecs_subnet_ids)

  file_system_id  = aws_efs_file_system.open_webui.id
  security_groups = [aws_security_group.efs_sg.id]
  subnet_id       = var.ecs_subnet_ids[count.index]
}

# SG for EFS
resource "aws_security_group" "efs_sg" {
  name        = "${var.prefix}-efs-sg"
  description = "Security group for EFS"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "efs_egress_1" {
  security_group_id = aws_security_group.efs_sg.id
  description       = "Allow all tcp outbound"
  from_port         = 0
  to_port           = 65535
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr_block
}

resource "aws_vpc_security_group_ingress_rule" "efs_ingress_1" {
  security_group_id = aws_security_group.efs_sg.id
  description       = "Access EFS via NFS port"
  from_port         = 2049
  to_port           = 2049
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr_block
}

# Backup vault for EFS
resource "aws_backup_vault" "efs_backup_vault" {
  name = "${var.prefix}-efs-backup-vault"

  tags = {
    "Name" : "${var.prefix}-efs-backup-vault"
  }
}

# Backup plan for nightly snapshots with 30-day retention
resource "aws_backup_plan" "efs_backup_plan" {
  name = "${var.prefix}-efs-backup-plan"

  rule {
    rule_name         = "nightly_backup_30day_retention"
    target_vault_name = aws_backup_vault.efs_backup_vault.name
    schedule          = "cron(0 5 * * ? *)" # Daily at 5 AM UTC

    lifecycle {
      delete_after = 30
    }

    recovery_point_tags = {
      "Name" : "${var.prefix}-efs-backup"
    }
  }

  tags = {
    "Name" : "${var.prefix}-efs-backup-plan"
  }
}

# IAM role for AWS Backup
resource "aws_iam_role" "backup_role" {
  name               = "${var.prefix}-backup-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume_role.json

  tags = {
    "Name" : "${var.prefix}-backup-role"
  }
}

data "aws_iam_policy_document" "backup_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "backup_policy" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore_policy" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Backup selection - target the EFS filesystem
resource "aws_backup_selection" "efs_backup_selection" {
  name         = "${var.prefix}-efs-backup-selection"
  plan_id      = aws_backup_plan.efs_backup_plan.id
  iam_role_arn = aws_iam_role.backup_role.arn

  resources = [
    aws_efs_file_system.open_webui.arn
  ]
}

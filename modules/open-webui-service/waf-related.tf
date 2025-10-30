# AWS WAF v2 Configuration for Open WebUI ALB
# Provides protection against common web exploits and malicious traffic

# WAF Web ACL
resource "aws_wafv2_web_acl" "openwebui" {
  count = var.enable_waf ? 1 : 0

  name        = "${var.prefix}-waf"
  description = "WAF for Open WebUI Application Load Balancer"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Rule 1: Amazon IP Reputation List
  # Blocks requests from IP addresses known to be malicious
  rule {
    name     = "AWS-AWSManagedRulesAmazonIpReputationList"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAmazonIpReputationList"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesAmazonIpReputationList"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: Common Rule Set (OWASP Top 10)
  # Protects against common web vulnerabilities with custom overrides
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"

        # Custom rule overrides - set to Count mode for Open WebUI compatibility
        rule_action_override {
          name = "NoUserAgent_HEADER"
          action_to_use {
            count {}
          }
        }

        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use {
            count {}
          }
        }

        rule_action_override {
          name = "GenericLFI_BODY"
          action_to_use {
            count {}
          }
        }

        rule_action_override {
          name = "CrossSiteScripting_BODY"
          action_to_use {
            count {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: Known Bad Inputs
  # Blocks requests with patterns associated with exploits
  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4: Linux Rule Set
  # Protects against Linux-specific vulnerabilities
  rule {
    name     = "AWS-AWSManagedRulesLinuxRuleSet"
    priority = 4

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesLinuxRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesLinuxRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Rule 5: PHP Rule Set
  # Protects against PHP-specific vulnerabilities
  rule {
    name     = "AWS-AWSManagedRulesPHPRuleSet"
    priority = 5

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesPHPRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesPHPRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.prefix}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "${var.prefix}-waf"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Associate WAF with ALB
resource "aws_wafv2_web_acl_association" "openwebui_alb" {
  count = var.enable_waf ? 1 : 0

  resource_arn = aws_lb.openwebui.arn
  web_acl_arn  = aws_wafv2_web_acl.openwebui[0].arn
}

# CloudWatch Log Group for WAF logs (optional but recommended)
resource "aws_cloudwatch_log_group" "waf_logs" {
  count = var.enable_waf && var.waf_enable_logging ? 1 : 0

  name              = "/aws/wafv2/${var.prefix}"
  retention_in_days = var.waf_log_retention_days

  tags = {
    Name      = "${var.prefix}-waf-logs"
    ManagedBy = "terraform"
  }
}

# WAF Logging Configuration
resource "aws_wafv2_web_acl_logging_configuration" "openwebui" {
  count = var.enable_waf && var.waf_enable_logging ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.openwebui[0].arn
  log_destination_configs = [aws_cloudwatch_log_group.waf_logs[0].arn]

  # Redact sensitive fields from logs
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}
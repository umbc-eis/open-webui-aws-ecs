# Lambda function to automatically create admin user after deployment
# Uses Open WebUI's /api/v1/auths/signup API endpoint

# Lambda function code
data "archive_file" "admin_init_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda_admin_init.zip"

  source {
    content = <<-EOF
      import json
      import boto3
      import urllib3
      import time
      import os

      http = urllib3.PoolManager()
      secretsmanager = boto3.client('secretsmanager')

      def lambda_handler(event, context):
          print("Starting admin user creation")

          # Get configuration from environment
          endpoint = os.environ['OPENWEBUI_ENDPOINT']
          secret_arn = os.environ['ADMIN_SECRET_ARN']
          max_retries = int(os.environ.get('MAX_RETRIES', '30'))
          retry_delay = int(os.environ.get('RETRY_DELAY', '10'))

          # Retrieve admin credentials from Secrets Manager
          try:
              secret_response = secretsmanager.get_secret_value(SecretId=secret_arn)
              secret_data = json.loads(secret_response['SecretString'])

              admin_name = secret_data['name']
              admin_email = secret_data['email']
              admin_password = secret_data['password']
          except Exception as e:
              print(f"Error retrieving admin credentials: {str(e)}")
              return {
                  'statusCode': 500,
                  'body': json.dumps({'error': 'Failed to retrieve admin credentials'})
              }

          # Wait for Open WebUI to be healthy
          health_url = f"{endpoint}/health"
          print(f"Checking health endpoint: {health_url}")

          for attempt in range(max_retries):
              try:
                  response = http.request('GET', health_url, timeout=5.0)
                  if response.status == 200:
                      print(f"Service is healthy after {attempt + 1} attempts")
                      break
              except Exception as e:
                  print(f"Health check attempt {attempt + 1} failed: {str(e)}")

              if attempt < max_retries - 1:
                  print(f"Waiting {retry_delay} seconds before retry...")
                  time.sleep(retry_delay)
              else:
                  return {
                      'statusCode': 500,
                      'body': json.dumps({'error': 'Service health check timeout'})
                  }

          # Create admin user via signup API
          signup_url = f"{endpoint}/api/v1/auths/signup"
          print(f"Creating admin user at: {signup_url}")

          payload = {
              "name": admin_name,
              "email": admin_email,
              "password": admin_password,
              "role": "admin"
          }

          try:
              response = http.request(
                  'POST',
                  signup_url,
                  body=json.dumps(payload),
                  headers={'Content-Type': 'application/json'},
                  timeout=10.0
              )

              response_body = response.data.decode('utf-8')
              print(f"Signup API response status: {response.status}")
              print(f"Signup API response body: {response_body}")

              if response.status in [200, 201]:
                  print("Admin user created successfully")
                  return {
                      'statusCode': 200,
                      'body': json.dumps({
                          'message': 'Admin user created successfully',
                          'email': admin_email
                      })
                  }
              elif response.status == 400:
                  # User might already exist
                  if 'already exists' in response_body.lower() or 'email' in response_body.lower():
                      print("Admin user already exists")
                      return {
                          'statusCode': 200,
                          'body': json.dumps({
                              'message': 'Admin user already exists',
                              'email': admin_email
                          })
                      }

              return {
                  'statusCode': response.status,
                  'body': json.dumps({
                      'error': 'Failed to create admin user',
                      'details': response_body
                  })
              }

          except Exception as e:
              print(f"Error creating admin user: {str(e)}")
              return {
                  'statusCode': 500,
                  'body': json.dumps({
                      'error': 'Exception creating admin user',
                      'details': str(e)
                  })
              }
    EOF
    filename = "lambda_function.py"
  }
}

# IAM role for Lambda
resource "aws_iam_role" "admin_init_lambda" {
  name               = "${var.prefix}-admin-init-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    "Name" : "${var.prefix}-admin-init-lambda-role"
  }
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Lambda execution policy
resource "aws_iam_role_policy" "admin_init_lambda_policy" {
  name = "${var.prefix}-admin-init-lambda-policy"
  role = aws_iam_role.admin_init_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.region}:*:log-group:/aws/lambda/${var.prefix}-admin-init",
          "arn:aws:logs:${var.region}:*:log-group:/aws/lambda/${var.prefix}-admin-init:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.admin_credentials.arn
      },
      {
        # Note: EC2 network interface permissions require Resource = "*" for VPC Lambda functions
        # This is an AWS limitation - these actions don't support resource-level permissions
        # See: https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda function
resource "aws_lambda_function" "admin_init" {
  filename         = data.archive_file.admin_init_lambda.output_path
  function_name    = "${var.prefix}-admin-init"
  role             = aws_iam_role.admin_init_lambda.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.admin_init_lambda.output_base64sha256
  runtime          = "python3.11"
  timeout          = 300
  memory_size      = 256

  vpc_config {
    subnet_ids         = var.ecs_subnet_ids
    security_group_ids = [aws_security_group.lambda_admin_init.id]
  }

  environment {
    variables = {
      OPENWEBUI_ENDPOINT = local.alb_configs.create_domain ? "https://${var.open_webui_domain}" : "http://${aws_lb.openwebui.dns_name}"
      ADMIN_SECRET_ARN   = aws_secretsmanager_secret.admin_credentials.arn
      MAX_RETRIES        = "30"
      RETRY_DELAY        = "10"
    }
  }

  depends_on = [
    aws_iam_role_policy.admin_init_lambda_policy,
    aws_ecs_service.open_webui
  ]

  tags = {
    "Name" : "${var.prefix}-admin-init"
  }
}

# Security group for Lambda
resource "aws_security_group" "lambda_admin_init" {
  name        = "${var.prefix}-lambda-admin-init-sg"
  description = "Security group for admin init Lambda function"
  vpc_id      = var.vpc_id

  tags = {
    "Name" : "${var.prefix}-lambda-admin-init-sg"
  }
}

# Allow Lambda to reach ALB (HTTP)
resource "aws_vpc_security_group_egress_rule" "lambda_to_alb_http" {
  security_group_id            = aws_security_group.lambda_admin_init.id
  description                  = "Allow Lambda to reach ALB over HTTP"
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.open_webui_alb_sg.id
}

# Allow Lambda to reach ALB (HTTPS)
resource "aws_vpc_security_group_egress_rule" "lambda_to_alb_https" {
  security_group_id            = aws_security_group.lambda_admin_init.id
  description                  = "Allow Lambda to reach ALB over HTTPS"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.open_webui_alb_sg.id
}

# Allow Lambda to reach AWS services (Secrets Manager via VPC endpoints or internet)
resource "aws_vpc_security_group_egress_rule" "lambda_to_aws_services" {
  security_group_id = aws_security_group.lambda_admin_init.id
  description       = "Allow Lambda to reach AWS services"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "admin_init_lambda" {
  name              = "/aws/lambda/${var.prefix}-admin-init"
  retention_in_days = 7

  tags = {
    "Name" : "${var.prefix}-admin-init-logs"
  }
}

# Null resource to trigger Lambda after deployment
resource "null_resource" "trigger_admin_init" {
  depends_on = [
    aws_lambda_function.admin_init,
    aws_ecs_service.open_webui
  ]

  # Trigger when service or Lambda changes
  triggers = {
    lambda_version = aws_lambda_function.admin_init.version
    service_id     = aws_ecs_service.open_webui.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws lambda invoke \
        --function-name ${aws_lambda_function.admin_init.function_name} \
        --region ${var.region} \
        --log-type Tail \
        /tmp/${var.prefix}-admin-init-response.json

      echo "Admin init Lambda response:"
      cat /tmp/${var.prefix}-admin-init-response.json
    EOT
  }
}

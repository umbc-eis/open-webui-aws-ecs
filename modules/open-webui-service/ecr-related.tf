resource "aws_ecr_repository" "openwebui_umbc" {
  name                 = "openwebui-umbc"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name      = "openwebui-umbc"
    ManagedBy = "terraform"
  }
}

resource "aws_ecr_lifecycle_policy" "openwebui_umbc" {
  repository = aws_ecr_repository.openwebui_umbc.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["v*"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      }
    ]
  })
}

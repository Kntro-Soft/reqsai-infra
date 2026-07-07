# Docker image repository for the reqsai-api backend. deploy.yml (in the
# reqsai-api repo) pushes here and ECS pulls from here.
resource "aws_ecr_repository" "reqsai_api" {
  name = "reqsai-api"

  # Immutable tags: once "abc1234" is pushed, it can never be overwritten —
  # a tag always points at the same image, which is what the deploy workflow
  # relies on (it tags images with the short git SHA).
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Without this, every push (dozens per day once CI is active) keeps its
# image forever and the repo grows unbounded. Keeps the last 10 tagged
# images and deletes untagged ones (leftovers from failed/superseded
# builds) after 1 day.
resource "aws_ecr_lifecycle_policy" "reqsai_api" {
  repository = aws_ecr_repository.reqsai_api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 10 tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

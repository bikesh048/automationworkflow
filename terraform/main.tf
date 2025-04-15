# Let's start with the terraform configuration for your infrastructure

# main.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ECR Repository
resource "aws_ecr_repository" "app_repo" {
  name                 = var.app_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = var.app_name
    Environment = var.environment
  }
}

# ECR Repository Policy to allow CodeBuild to pull images
resource "aws_ecr_repository_policy" "app_repo_policy" {
  repository = aws_ecr_repository.app_repo.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPushPull"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
      }
    ]
  })
}

# ECS Cluster
resource "aws_ecs_cluster" "app_cluster" {
  name = "${var.app_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "${var.app_name}-cluster"
    Environment = var.environment
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/ecs/${var.app_name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.app_name}-logs"
    Environment = var.environment
  }
}

# Task Execution Role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.app_name}-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# VPC and networking (simplified for example)
resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_default_subnet" "default_az1" {
  availability_zone = "${var.aws_region}a"
}

resource "aws_default_subnet" "default_az2" {
  availability_zone = "${var.aws_region}b"
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.app_name}-ecs-tasks-sg"
  description = "Allow inbound traffic to ECS tasks"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.app_name}-ecs-tasks-sg"
    Environment = var.environment
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "app_task" {
  family                   = var.app_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name         = var.app_name
      image        = "${aws_ecr_repository.app_repo.repository_url}:latest"
      essential    = true
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Name        = "${var.app_name}-task"
    Environment = var.environment
  }
}

# ECS Service
resource "aws_ecs_service" "app_service" {
  name            = "${var.app_name}-service"
  cluster         = aws_ecs_cluster.app_cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  launch_type     = "FARGATE"
  desired_count   = var.app_count

  network_configuration {
    subnets         = [aws_default_subnet.default_az1.id, aws_default_subnet.default_az2.id]
    security_groups = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  tags = {
    Name        = "${var.app_name}-service"
    Environment = var.environment
  }
}

# CodePipeline and related resources
resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = "${var.app_name}-${var.environment}-pipeline-artifacts"

  tags = {
    Name        = "${var.app_name}-pipeline-artifacts"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_ownership_controls" "codepipeline_bucket_ownership" {
  bucket = aws_s3_bucket.codepipeline_bucket.id
  
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "codepipeline_bucket_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.codepipeline_bucket_ownership]
  
  bucket = aws_s3_bucket.codepipeline_bucket.id
  acl    = "private"
}

resource "aws_iam_role" "codepipeline_role" {
  name = "${var.app_name}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}
# EventBridge rule to detect ECR image push events
resource "aws_cloudwatch_event_rule" "ecr_image_push" {
  name        = "${var.app_name}-ecr-image-push"
  description = "Detect ECR image push events and trigger CodePipeline"

  event_pattern = jsonencode({
    source      = ["aws.ecr"],
    detail-type = ["ECR Image Action"],
    detail      = {
      action-type     = ["PUSH"],
      repository-name = [aws_ecr_repository.app_repo.name],
      image-tag       = ["latest"]
    }
  })
}
# IAM role for EventBridge to start CodePipeline execution
resource "aws_iam_role" "eventbridge_role" {
  name = "${var.app_name}-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "events.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}
# IAM policy to allow EventBridge to start CodePipeline
resource "aws_iam_role_policy" "eventbridge_policy" {
  name = "${var.app_name}-eventbridge-policy"
  role = aws_iam_role.eventbridge_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = "codepipeline:StartPipelineExecution",
      Resource = aws_codepipeline.app_pipeline.arn
    }]
  })
}
# EventBridge target to start the CodePipeline
resource "aws_cloudwatch_event_target" "codepipeline_target" {
  rule     = aws_cloudwatch_event_rule.ecr_image_push.name
  arn      = aws_codepipeline.app_pipeline.arn
  role_arn = aws_iam_role.eventbridge_role.arn
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "${var.app_name}-codepipeline-policy"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObject"
        ],
        Resource = [
          aws_s3_bucket.codepipeline_bucket.arn,
          "${aws_s3_bucket.codepipeline_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:DescribeImages"
        ],
        Resource = aws_ecr_repository.app_repo.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "codebuild_role" {
  name = "${var.app_name}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "${var.app_name}-codebuild-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ],
        Resource = [
          "${aws_s3_bucket.codepipeline_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ],
        Resource = aws_ecs_service.app_service.id
      }
    ]
  })
}

resource "aws_codebuild_project" "deploy_project" {
  name          = "${var.app_name}-deploy"
  description   = "Deploy the ${var.app_name} app to ECS Fargate"
  build_timeout = "10"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "CLUSTER_NAME"
      value = aws_ecs_cluster.app_cluster.name
    }
    
    environment_variable {
      name  = "SERVICE_NAME"
      value = aws_ecs_service.app_service.name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<BUILDSPEC
version: 0.2
phases:
  pre_build:
    commands:
      - echo Pre-build phase...
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
  build:
    commands:
      - echo Starting the deployment to ECS...
      - aws ecs update-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --force-new-deployment
  post_build:
    commands:
      - echo Deployment to ECS completed successfully
BUILDSPEC
  }
}

resource "aws_codepipeline" "app_pipeline" {
  name     = "${var.app_name}-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "ECR"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        RepositoryName = aws_ecr_repository.app_repo.name
        ImageTag       = "latest"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

       configuration = {
        ProjectName = aws_codebuild_project.deploy_project.name
        EnvironmentVariables = jsonencode([
          {
            name  = "AWS_ACCOUNT_ID",
            value = "#{codepipeline.PipelineExecutionId}",
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  tags = {
    Name        = "${var.app_name}-pipeline"
    Environment = var.environment
  }
}

# Outputs
output "ecr_repository_url" {
  description = "The URL of the ECR repository"
  value       = aws_ecr_repository.app_repo.repository_url
}

output "ecs_cluster_name" {
  description = "The name of the ECS cluster"
  value       = aws_ecs_cluster.app_cluster.name
}

output "ecs_service_name" {
  description = "The name of the ECS service"
  value       = aws_ecs_service.app_service.name
}

output "codepipeline_name" {
  description = "The name of the CodePipeline"
  value       = aws_codepipeline.app_pipeline.name
}


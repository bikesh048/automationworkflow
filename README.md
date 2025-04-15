# NestJS AWS CI/CD Pipeline

This repository contains a NestJS application with a complete CI/CD pipeline using GitHub Actions, Terraform, AWS ECR, and AWS Fargate.

## CI/CD Pipeline Architecture

- **GitHub Actions** - For running workflows
- **Terraform** - For infrastructure as code
- **AWS ECR** - For storing Docker images
- **AWS CodePipeline** - For automated deployments
- **AWS Fargate** - For running containerized applications

## Workflows

The project uses two separate GitHub Actions workflows:

### 1. Infrastructure Provisioning (`infrastructure.yml`)

This workflow is triggered:

- When changes are made to Terraform files (\*.tf)
- When manually triggered from the GitHub Actions UI

It uses Terraform to provision:

- ECR repository
- ECS cluster and service
- CodePipeline and related resources
- Networking and security components

### 2. Build and Deploy (`build-and-deploy.yml`)

This workflow is triggered:

- When changes are pushed to the main branch (excluding Terraform files)
- When manually triggered from the GitHub Actions UI

It:

- Builds a Docker image for the NestJS application
- Pushes the image to ECR
- AWS CodePipeline automatically detects the new image and deploys to Fargate

## Initial Setup

1. Set up AWS credentials in GitHub repository secrets:

   - Go to Settings > Secrets and variables > Actions
   - Add `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`

2. Run the infrastructure workflow first (manually trigger it)

3. Push code changes to trigger the build and deploy workflow

## Local Development

To run the application locally:

```bash
# Install dependencies
npm install

# Start development server
npm run start:dev
```

## Docker Development

```bash
# Build the image
docker build -t nestjs-app .

# Run the container
docker run -p 3000:3000 nestjs-app
```

## Infrastructure Management

```bash
# Initialize Terraform
terraform init

# Plan changes
terraform plan

# Apply changes
terraform apply

# Destroy resources when done
terraform destroy
```

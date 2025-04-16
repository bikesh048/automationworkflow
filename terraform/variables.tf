# variables.tf
variable "aws_region" {
  description = "The AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}
variable "app_name" {
  description = "The name of the application"
  type        = string
  default     = "nestjs-app"
}
variable "environment" {
  description = "The deployment environment"
  type        = string
  default     = "dev"
}
variable "container_port" {
  description = "The port the container will listen on"
  type        = number
  default     = 3000
}
variable "task_cpu" {
  description = "The CPU units for the task"
  type        = string
  default     = "256"
}
variable "task_memory" {
  description = "The memory for the task"
  type        = string
  default     = "512"
}
variable "app_count" {
  description = "The number of instances of the task to run"
  type        = number
  default     = 1
}
variable "api_endpoint" {
  description = "The Url endpoint for api"
  type = string
  default = "api.bikeshrestha.com.np"
}
variable "account_id" {
  description = "The AWS account ID"
  type = string
}
variable "certificate_id" {
  description = "TLS Certificate id"
  type = string
}
variable "zone_id" {
  description = "The zone ID for bikeshrestha.com.np"
  type = string
}

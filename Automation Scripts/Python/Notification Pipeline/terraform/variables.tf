variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "infra-lifecycle-alerts"
}

variable "slack_webhook_url" {
  description = "Slack Incoming Webhook URL for notifications (used by Lambda formatter)"
  type        = string
  sensitive   = true
}

variable "slack_channel" {
  description = "Slack channel name (without #) for Lambda webhook posts"
  type        = string
  default     = "infra-alerts"
}

variable "slack_workspace_id" {
  description = "Slack workspace ID for AWS Chatbot integration (leave empty to skip)"
  type        = string
  default     = ""
}

variable "slack_channel_id" {
  description = "Slack channel ID for AWS Chatbot integration (leave empty to skip)"
  type        = string
  default     = ""
}

variable "enable_ecs_retirement_alerts" {
  description = "Enable ECS Fargate task retirement notifications"
  type        = bool
  default     = true
}

variable "enable_ec2_termination_alerts" {
  description = "Enable EC2 instance termination notifications (Karpenter/Auto Mode)"
  type        = bool
  default     = true
}

variable "enable_eks_events" {
  description = "Enable EKS service events (Fargate pod termination, etc.)"
  type        = bool
  default     = true
}

variable "enable_ec2_health_alerts" {
  description = "Enable EC2 scheduled maintenance health events"
  type        = bool
  default     = true
}

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention in days for the Lambda function"
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project   = "infra-lifecycle-alerts"
    ManagedBy = "terraform"
  }
}

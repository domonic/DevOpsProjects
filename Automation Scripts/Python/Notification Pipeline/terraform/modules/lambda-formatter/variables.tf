variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "slack_webhook_url" {
  description = "Slack Incoming Webhook URL for notifications"
  type        = string
  sensitive   = true
}

variable "slack_channel" {
  description = "Slack channel name (without #)"
  type        = string
  default     = "infra-alerts"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

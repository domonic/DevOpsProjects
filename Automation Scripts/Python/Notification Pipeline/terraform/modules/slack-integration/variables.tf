variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic to subscribe to (for AWS Chatbot integration)"
  type        = string
}

variable "slack_workspace_id" {
  description = "Slack workspace ID for AWS Chatbot (leave empty to skip Chatbot setup)"
  type        = string
  default     = ""
}

variable "slack_channel_id" {
  description = "Slack channel ID for AWS Chatbot (leave empty to skip Chatbot setup)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

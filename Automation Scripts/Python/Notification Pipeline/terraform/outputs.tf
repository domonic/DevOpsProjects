output "lambda_function_arn" {
  description = "ARN of the formatter Lambda function"
  value       = module.lambda_formatter.function_arn
}

output "lambda_function_name" {
  description = "Name of the formatter Lambda function"
  value       = module.lambda_formatter.function_name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for lifecycle alerts"
  value       = module.sns_topic.topic_arn
}

output "eventbridge_rule_arns" {
  description = "ARNs of all EventBridge rules"
  value       = module.eventbridge_rules.rule_arns
}

output "chatbot_enabled" {
  description = "Whether AWS Chatbot Slack integration is enabled"
  value       = module.slack_integration.chatbot_enabled
}

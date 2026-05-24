resource "aws_sns_topic" "this" {
  name = "${var.project_name}-alerts"
  tags = var.tags
}

output "topic_arn" {
  description = "ARN of the SNS topic"
  value       = aws_sns_topic.this.arn
}

output "topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.this.name
}

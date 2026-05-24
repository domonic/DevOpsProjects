# -----------------------------------------------------------------------------
# Slack Integration via AWS Chatbot (Optional)
#
# This module sets up AWS Chatbot to forward SNS messages to Slack.
# If slack_workspace_id and slack_channel_id are not provided, this module
# is effectively a no-op — use the Lambda webhook approach instead.
#
# Note: AWS Chatbot Slack workspace configuration must be done manually in the
# AWS Console first (one-time OAuth setup). This module creates the channel
# configuration that references that workspace.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "chatbot" {
  count = var.slack_workspace_id != "" ? 1 : 0

  name = "${var.project_name}-chatbot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "chatbot.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "chatbot" {
  count = var.slack_workspace_id != "" ? 1 : 0

  name = "${var.project_name}-chatbot-policy"
  role = aws_iam_role.chatbot[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:Describe*",
          "cloudwatch:Get*",
          "cloudwatch:List*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Note: aws_chatbot_slack_channel_configuration requires the AWS Chatbot
# provider or manual setup. The resource below uses the awscc provider
# if available, otherwise this serves as documentation of the required config.
#
# If using the standard AWS provider, you may need to configure Chatbot
# via the AWS Console or use a CloudFormation resource.

resource "aws_cloudformation_stack" "chatbot" {
  count = var.slack_workspace_id != "" ? 1 : 0

  name = "${var.project_name}-chatbot"

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "AWS Chatbot Slack channel configuration for infrastructure lifecycle alerts"
    Resources = {
      SlackChannelConfig = {
        Type = "AWS::Chatbot::SlackChannelConfiguration"
        Properties = {
          ConfigurationName = "${var.project_name}-slack"
          IamRoleArn        = aws_iam_role.chatbot[0].arn
          SlackChannelId    = var.slack_channel_id
          SlackWorkspaceId  = var.slack_workspace_id
          SnsTopicArns      = [var.sns_topic_arn]
          LoggingLevel      = "INFO"
        }
      }
    }
  })

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "chatbot_enabled" {
  description = "Whether AWS Chatbot Slack integration is enabled"
  value       = var.slack_workspace_id != ""
}

output "chatbot_role_arn" {
  description = "ARN of the Chatbot IAM role (null if not enabled)"
  value       = var.slack_workspace_id != "" ? aws_iam_role.chatbot[0].arn : null
}

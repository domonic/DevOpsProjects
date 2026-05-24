terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# Module: SNS Topic
# -----------------------------------------------------------------------------
module "sns_topic" {
  source = "./modules/sns-topic"

  project_name = var.project_name
  tags         = var.tags
}

# -----------------------------------------------------------------------------
# Module: Lambda Formatter
# -----------------------------------------------------------------------------
module "lambda_formatter" {
  source = "./modules/lambda-formatter"

  project_name       = var.project_name
  slack_webhook_url  = var.slack_webhook_url
  slack_channel      = var.slack_channel
  log_retention_days = var.lambda_log_retention_days
  tags               = var.tags
}

# -----------------------------------------------------------------------------
# Module: EventBridge Rules
# -----------------------------------------------------------------------------
module "eventbridge_rules" {
  source = "./modules/eventbridge-rules"

  project_name         = var.project_name
  lambda_function_arn  = module.lambda_formatter.function_arn
  lambda_function_name = module.lambda_formatter.function_name

  enable_ecs_retirement_alerts  = var.enable_ecs_retirement_alerts
  enable_ec2_termination_alerts = var.enable_ec2_termination_alerts
  enable_eks_events             = var.enable_eks_events
  enable_ec2_health_alerts      = var.enable_ec2_health_alerts

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Module: Slack Integration (AWS Chatbot — optional)
# -----------------------------------------------------------------------------
module "slack_integration" {
  source = "./modules/slack-integration"

  project_name       = var.project_name
  sns_topic_arn      = module.sns_topic.topic_arn
  slack_workspace_id = var.slack_workspace_id
  slack_channel_id   = var.slack_channel_id
  tags               = var.tags
}

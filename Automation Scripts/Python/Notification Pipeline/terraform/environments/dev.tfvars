aws_region    = "us-east-1"
project_name  = "infra-lifecycle-alerts-dev"
slack_channel = "infra-alerts-dev"

enable_ecs_retirement_alerts  = true
enable_ec2_termination_alerts = true
enable_eks_events             = true
enable_ec2_health_alerts      = true

lambda_log_retention_days = 7

tags = {
  Project     = "infra-lifecycle-alerts"
  Environment = "dev"
  ManagedBy   = "terraform"
}

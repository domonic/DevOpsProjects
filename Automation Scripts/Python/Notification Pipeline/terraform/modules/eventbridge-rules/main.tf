# -----------------------------------------------------------------------------
# EventBridge Rule: ECS Fargate Task Retirement
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "ecs_task_retirement" {
  count = var.enable_ecs_retirement_alerts ? 1 : 0

  name        = "${var.project_name}-ecs-task-retirement"
  description = "Captures ECS Fargate task retirement notifications from AWS Health"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
    detail = {
      service           = ["ECS"]
      eventTypeCategory = ["scheduledChange"]
      eventTypeCode     = ["AWS_ECS_TASK_PATCHING_RETIREMENT"]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "ecs_task_retirement" {
  count = var.enable_ecs_retirement_alerts ? 1 : 0

  rule      = aws_cloudwatch_event_rule.ecs_task_retirement[0].name
  target_id = "send-to-lambda"
  arn       = var.lambda_function_arn
}

resource "aws_lambda_permission" "ecs_task_retirement" {
  count = var.enable_ecs_retirement_alerts ? 1 : 0

  statement_id  = "AllowECSTaskRetirementRule"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecs_task_retirement[0].arn
}

# -----------------------------------------------------------------------------
# EventBridge Rule: EC2 Instance Termination (Karpenter / Auto Mode nodes)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "ec2_instance_terminated" {
  count = var.enable_ec2_termination_alerts ? 1 : 0

  name        = "${var.project_name}-ec2-terminated"
  description = "Captures EC2 instance terminations for Karpenter and EKS Auto Mode nodes"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
    detail = {
      state = ["terminated", "shutting-down"]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "ec2_instance_terminated" {
  count = var.enable_ec2_termination_alerts ? 1 : 0

  rule      = aws_cloudwatch_event_rule.ec2_instance_terminated[0].name
  target_id = "send-to-lambda"
  arn       = var.lambda_function_arn
}

resource "aws_lambda_permission" "ec2_instance_terminated" {
  count = var.enable_ec2_termination_alerts ? 1 : 0

  statement_id  = "AllowEC2TerminatedRule"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_instance_terminated[0].arn
}

# -----------------------------------------------------------------------------
# EventBridge Rule: EKS Service Events (Fargate Pod Termination, etc.)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "eks_events" {
  count = var.enable_eks_events ? 1 : 0

  name        = "${var.project_name}-eks-events"
  description = "Captures EKS Auto Mode and Fargate pod scheduled termination events"

  event_pattern = jsonencode({
    source      = ["aws.eks"]
    detail-type = ["EKS Fargate Pod Scheduled Termination"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "eks_events" {
  count = var.enable_eks_events ? 1 : 0

  rule      = aws_cloudwatch_event_rule.eks_events[0].name
  target_id = "send-to-lambda"
  arn       = var.lambda_function_arn
}

resource "aws_lambda_permission" "eks_events" {
  count = var.enable_eks_events ? 1 : 0

  statement_id  = "AllowEKSEventsRule"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.eks_events[0].arn
}

# -----------------------------------------------------------------------------
# EventBridge Rule: EC2 Scheduled Maintenance (Health Events)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "ec2_health_maintenance" {
  count = var.enable_ec2_health_alerts ? 1 : 0

  name        = "${var.project_name}-ec2-maintenance"
  description = "Captures EC2 scheduled maintenance events from AWS Health"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
    detail = {
      service           = ["EC2"]
      eventTypeCategory = ["scheduledChange"]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "ec2_health_maintenance" {
  count = var.enable_ec2_health_alerts ? 1 : 0

  rule      = aws_cloudwatch_event_rule.ec2_health_maintenance[0].name
  target_id = "send-to-lambda"
  arn       = var.lambda_function_arn
}

resource "aws_lambda_permission" "ec2_health_maintenance" {
  count = var.enable_ec2_health_alerts ? 1 : 0

  statement_id  = "AllowEC2MaintenanceRule"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_health_maintenance[0].arn
}

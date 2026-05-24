output "rule_arns" {
  description = "ARNs of all EventBridge rules"
  value = {
    ecs_task_retirement = var.enable_ecs_retirement_alerts ? aws_cloudwatch_event_rule.ecs_task_retirement[0].arn : null
    ec2_terminated      = var.enable_ec2_termination_alerts ? aws_cloudwatch_event_rule.ec2_instance_terminated[0].arn : null
    eks_events          = var.enable_eks_events ? aws_cloudwatch_event_rule.eks_events[0].arn : null
    ec2_health          = var.enable_ec2_health_alerts ? aws_cloudwatch_event_rule.ec2_health_maintenance[0].arn : null
  }
}

output "rule_names" {
  description = "Names of all EventBridge rules"
  value = {
    ecs_task_retirement = var.enable_ecs_retirement_alerts ? aws_cloudwatch_event_rule.ecs_task_retirement[0].name : null
    ec2_terminated      = var.enable_ec2_termination_alerts ? aws_cloudwatch_event_rule.ec2_instance_terminated[0].name : null
    eks_events          = var.enable_eks_events ? aws_cloudwatch_event_rule.eks_events[0].name : null
    ec2_health          = var.enable_ec2_health_alerts ? aws_cloudwatch_event_rule.ec2_health_maintenance[0].name : null
  }
}

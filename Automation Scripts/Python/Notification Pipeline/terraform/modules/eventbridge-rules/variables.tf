variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "lambda_function_arn" {
  description = "ARN of the Lambda function to target"
  type        = string
}

variable "lambda_function_name" {
  description = "Name of the Lambda function (for permissions)"
  type        = string
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

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

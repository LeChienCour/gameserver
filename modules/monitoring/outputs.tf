output "dashboard_name" {
  description = "Name of the CloudWatch observability dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "alarm_arns" {
  description = "Map of CloudWatch alarm ARNs"
  value = {
    ec2_high_cpu          = aws_cloudwatch_metric_alarm.ec2_high_cpu.arn
    event_dlq_messages    = aws_cloudwatch_metric_alarm.event_dlq_messages.arn
    message_lambda_errors = aws_cloudwatch_metric_alarm.message_lambda_errors.arn
  }
}

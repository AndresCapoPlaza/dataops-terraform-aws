output "flink_application_name" {
  description = "Nombre de la aplicación de Flink"
  value       = try(aws_kinesisanalyticsv2_application.clicks_processor[0].name, null)
}

output "flink_application_arn" {
  description = "ARN de la aplicación de Flink"
  value       = try(aws_kinesisanalyticsv2_application.clicks_processor[0].arn, null)
}

output "flink_execution_role_arn" {
  description = "ARN del rol de ejecución de Flink"
  value       = aws_iam_role.flink_execution_role.arn
}

output "flink_log_group_name" {
  description = "Nombre del CloudWatch Log Group de Flink"
  value       = aws_cloudwatch_log_group.flink_log_group.name
}

output "flink_execution_role_name" {
  description = "Nombre del rol de ejecución de Flink"
  value       = aws_iam_role.flink_execution_role.name
}

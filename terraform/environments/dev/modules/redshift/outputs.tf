output "namespace_name" {
  description = "Nombre del namespace de Redshift Serverless"
  value       = aws_redshiftserverless_namespace.lakehouse.namespace_name
}

output "workgroup_name" {
  description = "Nombre del workgroup de Redshift Serverless"
  value       = aws_redshiftserverless_workgroup.lakehouse.workgroup_name
}

output "database_name" {
  description = "Base de datos inicial del namespace"
  value       = aws_redshiftserverless_namespace.lakehouse.db_name
}

output "redshift_iam_role_arn" {
  description = "ARN del rol IAM usado en las sentencias CREATE EXTERNAL SCHEMA"
  value       = aws_iam_role.redshift_role.arn
}

output "admin_password_secret_arn" {
  description = "Secreto de Secrets Manager con la contrasena del usuario admin"
  value       = aws_redshiftserverless_namespace.lakehouse.admin_password_secret_arn
}

output "workgroup_endpoint" {
  description = "Endpoint del workgroup"
  value       = try(aws_redshiftserverless_workgroup.lakehouse.endpoint[0].address, null)
}

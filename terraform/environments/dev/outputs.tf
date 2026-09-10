output "vpc_id" {
  value       = module.network.vpc_id
  description = "ID de la VPC Creada"
}
output "private_subnets" {
  value       = module.network.private_subnet_ids
  description = "Lista de subredes privadas"
}
output "s3_endpoint_id" {
  value       = module.network.s3_endpoint_id
  description = "ID del VPC Endpoint para S3"
}
output "data_role_arn" {
  value       = module.identity.role_arn
  description = "ARN del Rol IAM de procesamiento"
}
output "raw_bucket_name" {
  value       = aws_s3_bucket.raw_bucket.bucket
  description = "Nombre del Bucket S3 Raw"
}

output "audit_role_arn" {
  value       = module.identity.audit_role_arn
  description = "ARN del Rol IAM de auditoría"
}

# ------------------------------------------------------------------------------
# Entrega 6 - datos necesarios para ejecutar el SQL en Query Editor v2
# ------------------------------------------------------------------------------

output "redshift_workgroup" {
  description = "Workgroup al que conectarse desde Query Editor v2"
  value       = module.redshift.workgroup_name
}

output "redshift_database" {
  description = "Base de datos del namespace"
  value       = module.redshift.database_name
}

output "redshift_iam_role_arn" {
  description = "ARN a usar en las sentencias CREATE EXTERNAL SCHEMA ... IAM_ROLE"
  value       = module.redshift.redshift_iam_role_arn
}

output "redshift_admin_secret_arn" {
  description = "Secreto de Secrets Manager con la contrasena del usuario admin"
  value       = module.redshift.admin_password_secret_arn
}

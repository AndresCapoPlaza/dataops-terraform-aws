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
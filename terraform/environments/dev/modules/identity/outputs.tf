output "role_arn" {
  value       = aws_iam_role.data_processing_role.arn
  description = "ARN del Rol IAM configurado"
}
output "role_name" {
  value       = aws_iam_role.data_processing_role.name
  description = "Nombre del Rol IAM"
}

output "audit_role_arn" {
  value       = aws_iam_role.control_plane_audit_role.arn
  description = "ARN del Rol IAM de auditoría del plano de control"
}

output "audit_role_name" {
  value       = aws_iam_role.control_plane_audit_role.name
  description = "Nombre del Rol IAM de auditoría"
}
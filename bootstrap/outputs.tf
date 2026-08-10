# ------------------------------------------------------------------------------
# VALORES DE SALIDA
# Entregan los nombres exactos necesarios para el backend de dev.
# ------------------------------------------------------------------------------
output "s3_bucket_name" {
  value       = aws_s3_bucket.tf_state.bucket
  description = "Nombre del bucket S3 configurado como backend remoto"
}
output "dynamodb_table_name" {
  value       = aws_dynamodb_table.tf_locks.name
  description = "Nombre de la tabla DynamoDB usada para el State Locking"
}
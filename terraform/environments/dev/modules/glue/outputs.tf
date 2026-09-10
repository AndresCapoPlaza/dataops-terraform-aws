output "database_name" {
  description = "Nombre de la base de datos de Glue"
  value       = aws_glue_catalog_database.lakehouse_db.name
}

output "database_arn" {
  description = "ARN de la base de datos de Glue"
  value       = aws_glue_catalog_database.lakehouse_db.arn
}

output "lock_table_name" {
  description = "Tabla DynamoDB usada como lock manager de Iceberg"
  value       = aws_dynamodb_table.iceberg_glue_lock.name
}

output "database_name" {
  description = "Nombre de la base de datos de Glue"
  value       = aws_glue_catalog_database.lakehouse_db.name
}

output "database_arn" {
  description = "ARN de la base de datos de Glue"
  value       = aws_glue_catalog_database.lakehouse_db.arn
}
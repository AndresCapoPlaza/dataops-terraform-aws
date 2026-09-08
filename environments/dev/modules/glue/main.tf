# ============================================================
# Base de datos en AWS Glue Data Catalog (Lakehouse)
# ============================================================

resource "aws_glue_catalog_database" "lakehouse_db" {
  name        = "lakehouse_db"
  description = "Catálogo de tablas Iceberg para el pipeline de clicks de e-commerce"
}

# ============================================================
# Permisos adicionales para el rol de Flink: Glue Data Catalog
# ============================================================

resource "aws_iam_role_policy" "flink_glue_access" {
  name = "flink-glue-access-policy"
  role = var.flink_execution_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetTables",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:DeleteTable",
          "glue:GetPartitions",
          "glue:BatchCreatePartition",
        ]
        Resource = [
          "arn:aws:glue:${var.region}:${var.account_id}:catalog",
          "arn:aws:glue:${var.region}:${var.account_id}:database/${aws_glue_catalog_database.lakehouse_db.name}",
          "arn:aws:glue:${var.region}:${var.account_id}:table/${aws_glue_catalog_database.lakehouse_db.name}/*",
        ]
      }
    ]
  })
}

# ============================================================
# Permisos ampliados de S3 para el Lakehouse (lectura/escritura de datos + metadata Iceberg)
# ============================================================

resource "aws_iam_role_policy" "flink_lakehouse_s3_access" {
  name = "flink-lakehouse-s3-access-policy"
  role = var.flink_execution_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          var.lakehouse_bucket_arn,
          "${var.lakehouse_bucket_arn}/*",
        ]
      }
    ]
  })
}
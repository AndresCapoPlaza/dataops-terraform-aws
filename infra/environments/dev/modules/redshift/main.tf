# ==============================================================================
# ENTREGA 6 - Analítica avanzada in-stream con Amazon Redshift Serverless
#
# Este módulo despliega la capa de consulta analítica de baja latencia:
#   - Rol IAM que permite a Redshift leer del Kinesis Data Stream (Streaming
#     Ingestion) y del Glue Data Catalog (Spectrum sobre tablas Iceberg).
#   - Namespace: la capa lógica (base de datos, usuarios, permisos).
#   - Workgroup: la capa de cómputo (RPUs, red, endpoint).
#
# Se eligió Redshift Serverless en lugar de un clúster provisionado porque
# factura por RPU-segundo de cómputo efectivamente consumido: un clúster
# provisionado factura mientras existe, aunque nadie lo consulte.
# ==============================================================================

data "aws_caller_identity" "current" {}

# ------------------------------------------------------------------------------
# 1. ROL IAM DE SERVICIO PARA REDSHIFT
# ------------------------------------------------------------------------------

resource "aws_iam_role" "redshift_role" {
  name = "redshift-serverless-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "redshift.amazonaws.com",
            "redshift-serverless.amazonaws.com",
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "redshift-serverless-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Streaming Ingestion: leer directamente del Kinesis Data Stream, sin pasar por S3
resource "aws_iam_role_policy" "redshift_kinesis_read" {
  name = "redshift-kinesis-streaming-policy"
  role = aws_iam_role.redshift_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadKinesisStream"
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards",
        ]
        Resource = var.kinesis_stream_arn
      },
      {
        Sid      = "ListStreams"
        Effect   = "Allow"
        Action   = ["kinesis:ListStreams"]
        Resource = "*"
      },
      {
        # El stream está cifrado con KMS: sin esta acción, GetRecords devuelve
        # registros que Redshift no puede descifrar.
        Sid      = "DecryptKinesisRecords"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "kinesis.${var.region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Spectrum sobre Iceberg: leer el Glue Data Catalog y los archivos en S3
resource "aws_iam_role_policy" "redshift_glue_lakehouse" {
  name = "redshift-glue-lakehouse-policy"
  role = aws_iam_role.redshift_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadGlueCatalog"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
        ]
        Resource = [
          "arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:database/${var.glue_database_name}",
          "arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.glue_database_name}/*",
        ]
      },
      {
        Sid    = "ReadLakehouseFiles"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = [
          var.lakehouse_bucket_arn,
          "${var.lakehouse_bucket_arn}/*",
        ]
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# 2. SECURITY GROUP DEL WORKGROUP
# ------------------------------------------------------------------------------

resource "aws_security_group" "redshift_sg" {
  name        = "redshift-serverless-${var.environment}"
  description = "Security group del workgroup de Redshift Serverless"
  vpc_id      = var.vpc_id

  # Acceso al puerto de Redshift unicamente desde dentro de la VPC.
  # Query Editor v2 no usa esta ruta: se conecta por la API de Redshift Data,
  # por eso el workgroup puede permanecer sin acceso publico.
  ingress {
    description = "Redshift desde la VPC"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Salida a servicios de AWS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "sg-redshift-serverless-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ------------------------------------------------------------------------------
# 3. NAMESPACE - capa logica (base de datos, credenciales, permisos)
# ------------------------------------------------------------------------------

resource "aws_redshiftserverless_namespace" "lakehouse" {
  namespace_name = "lakehouse-ns-${var.environment}"
  db_name        = var.database_name

  # La contrasena del usuario admin la genera y rota AWS Secrets Manager.
  # De esta forma no existe ningun secreto en el codigo ni en el state.
  admin_username        = var.admin_username
  manage_admin_password = true

  # Roles IAM que el namespace puede asumir desde SQL (IAM_ROLE en los
  # CREATE EXTERNAL SCHEMA).
  iam_roles            = [aws_iam_role.redshift_role.arn]
  default_iam_role_arn = aws_iam_role.redshift_role.arn

  log_exports = ["userlog", "connectionlog", "useractivitylog"]

  tags = {
    Name        = "lakehouse-ns-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ------------------------------------------------------------------------------
# 4. WORKGROUP - capa de computo (RPUs, red, endpoint)
# ------------------------------------------------------------------------------

resource "aws_redshiftserverless_workgroup" "lakehouse" {
  workgroup_name = "lakehouse-wg-${var.environment}"
  namespace_name = aws_redshiftserverless_namespace.lakehouse.namespace_name

  # 8 RPU es el minimo que admite Redshift Serverless y es holgado para el
  # volumen de este proyecto. La facturacion es por RPU-segundo consumido.
  base_capacity = var.base_capacity

  subnet_ids         = var.subnet_ids
  security_group_ids = [aws_security_group.redshift_sg.id]

  # Sin acceso publico: el consumo es via Query Editor v2 (API Redshift Data).
  publicly_accessible = false

  tags = {
    Name        = "lakehouse-wg-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ------------------------------------------------------------------------------
# 1. ROL DE SERVICIO (IAM Role)
# Define qué servicios pueden asumir este rol (Lambda / Flink).
# ------------------------------------------------------------------------------
resource "aws_iam_role" "data_processing_role" {
  name = "role-data-processing-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = ["lambda.amazonaws.com", "kinesisanalytics.amazonaws.com"]
        }
      }
    ]
  })
  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
# ------------------------------------------------------------------------------
# 2. POLÍTICA DE PERMISOS ACOTADA
# Permite únicamente listar el bucket y operar en el prefijo especificado.
# ------------------------------------------------------------------------------
resource "aws_iam_policy" "strict_s3_policy" {
  name        = "policy-s3-restricted-${var.environment}"
  description = "Permisos S3 acotados por prefijo sin comodines globales"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBucketScope"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [var.bucket_arn]
      },
      {
        Sid      = "ObjectOperationsScope"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = ["${var.bucket_arn}/${var.prefix}"]
      }
    ]
  })
}
# ------------------------------------------------------------------------------
# 3. ASOCIACIÓN DE POLÍTICA AL ROL
# ------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "attach_data_policy" {
  role       = aws_iam_role.data_processing_role.name
  policy_arn = aws_iam_policy.strict_s3_policy.arn
}

# ------------------------------------------------------------------------------
# 4. ROL DEL PLANO DE CONTROL PARA AUDITORÍA
# ------------------------------------------------------------------------------
# Este rol está destinado a tareas de auditoría y observabilidad.
# Sus permisos no permiten modificar ni eliminar recursos.
# ------------------------------------------------------------------------------

resource "aws_iam_role" "control_plane_audit_role" {
  name = "role-control-plane-audit-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"

        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "Audit"
  }
}

# ------------------------------------------------------------------------------
# 5. POLÍTICA DE SOLO LECTURA PARA AUDITORÍA
# ------------------------------------------------------------------------------
# Permite consultar información de los recursos sin modificarlos.
# ------------------------------------------------------------------------------

resource "aws_iam_policy" "control_plane_audit_policy" {
  name        = "policy-control-plane-audit-${var.environment}"
  description = "Permisos de solo lectura para auditoría del plano de control"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "AuditReadOnly"
        Effect = "Allow"

        Action = [
          "ec2:Describe*",
          "s3:Get*",
          "s3:List*",
          "iam:Get*",
          "iam:List*",
          "cloudwatch:Describe*",
          "cloudwatch:Get*",
          "cloudwatch:List*"
        ]

        Resource = "*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# 6. ASOCIACIÓN DE LA POLÍTICA DE AUDITORÍA AL ROL
# ------------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "attach_audit_policy" {
  role       = aws_iam_role.control_plane_audit_role.name
  policy_arn = aws_iam_policy.control_plane_audit_policy.arn
}
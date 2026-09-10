data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

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
      # ------------------------------------------------------------------
      # Acciones que SI admiten permisos a nivel de recurso: se acotan al
      # bucket del proyecto y a los roles de este entorno.
      # ------------------------------------------------------------------
      {
        Sid    = "AuditBucketReadOnly"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetBucketLocation",
          "s3:GetBucketPolicy",
          "s3:GetBucketVersioning",
          "s3:ListBucket",
          "s3:ListBucketVersions",
        ]
        Resource = [
          var.bucket_arn,
          "${var.bucket_arn}/*",
        ]
      },
      {
        Sid    = "AuditIamReadOnly"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRoles",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
      },

      # ------------------------------------------------------------------
      # Acciones de solo lectura del plano de control que, por diseno de AWS,
      # NO admiten permisos a nivel de recurso: la API opera sobre la cuenta
      # completa y solo acepta "*". Se acotan por dos vias alternativas:
      #   1. Lista explicita de acciones, sin comodines.
      #   2. Condicion de region, que limita el alcance a us-east-1.
      # Todas son de lectura: ninguna permite crear, modificar ni eliminar.
      # ------------------------------------------------------------------
      {
        Sid    = "AuditControlPlaneReadOnly"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcEndpoints",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.name
          }
        }
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
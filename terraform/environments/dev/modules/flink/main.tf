# ============================================================
# IAM Role de ejecución para la aplicación de Flink
# ============================================================

resource "aws_iam_role" "flink_execution_role" {
  name = "flink-execution-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "kinesisanalytics.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Name        = "flink-execution-${var.environment}"
  }
}

# Permisos: leer del Kinesis Data Stream de origen
resource "aws_iam_role_policy" "flink_kinesis_read" {
  name = "flink-kinesis-read-policy"
  role = aws_iam_role.flink_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards",
        ]
        Resource = var.kinesis_stream_arn
      }
    ]
  })
}

# Permisos: leer el código de la app desde S3
resource "aws_iam_role_policy" "flink_s3_code_read" {
  name = "flink-s3-code-read-policy"
  role = aws_iam_role.flink_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
        ]
        Resource = "${var.code_bucket_arn}/${var.code_s3_key}"
      }
    ]
  })
}

# Permisos: leer/escribir checkpoints en S3
resource "aws_iam_role_policy" "flink_s3_checkpoints" {
  name = "flink-s3-checkpoints-policy"
  role = aws_iam_role.flink_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
        ]
        Resource = [
          var.checkpoint_bucket_arn,
          "${var.checkpoint_bucket_arn}/*",
        ]
      }
    ]
  })
}

# Permisos: escribir logs en CloudWatch
resource "aws_iam_role_policy" "flink_cloudwatch_logs" {
  name = "flink-cloudwatch-logs-policy"
  role = aws_iam_role.flink_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        # Acotado al log group de esta aplicacion. Se eliminaron
        # logs:CreateLogGroup y DescribeLogGroups: el grupo lo crea Terraform
        # y describirlo no es necesario en runtime.
        Sid    = "WriteApplicationLogs"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = "${aws_cloudwatch_log_group.flink_log_group.arn}:*"
      }
    ]
  })
}

# ============================================================
# CloudWatch Log Group para la aplicación
# ============================================================

resource "aws_cloudwatch_log_group" "flink_log_group" {
  name              = "/aws/kinesisanalytics/${var.app_name}-${var.environment}"
  retention_in_days = 7

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_log_stream" "flink_log_stream" {
  name           = "flink-log-stream"
  log_group_name = aws_cloudwatch_log_group.flink_log_group.name
}

# ============================================================
# Aplicación de Managed Service for Apache Flink
# ============================================================


# ------------------------------------------------------------------------------
# ARTEFACTO DE LA APLICACION
# Terraform sube el .zip a S3 como parte del despliegue. Sin esto, crear la
# aplicacion exigiria un `aws s3 cp` manual previo y el stack dejaria de ser
# reproducible con un unico `terraform apply`.
# ------------------------------------------------------------------------------
resource "aws_s3_object" "app_artifact" {
  count = var.enable_managed_flink ? 1 : 0

  bucket = var.code_bucket_name
  key    = var.code_s3_key
  source = var.app_artifact_path

  # Fuerza la re-subida cuando cambia el contenido del artefacto
  etag = filemd5(var.app_artifact_path)

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_kinesisanalyticsv2_application" "clicks_processor" {
  # Controlado por var.enable_managed_flink (ver variables.tf)
  count = var.enable_managed_flink ? 1 : 0

  # Garantiza que el .zip este en S3 antes de crear la aplicacion
  depends_on = [aws_s3_object.app_artifact]

  name                   = "${var.app_name}-${var.environment}"
  runtime_environment    = "FLINK-1_15"
  service_execution_role = aws_iam_role.flink_execution_role.arn

  application_configuration {

    application_code_configuration {
      code_content {
        s3_content_location {
          bucket_arn = var.code_bucket_arn
          file_key   = var.code_s3_key
        }
      }
      code_content_type = "ZIPFILE"
    }

    environment_properties {
      property_group {
        property_group_id = "kinesis.analytics.flink.run.options"
        property_map = {
          python = "clicks_processor.py"

          # HALLAZGO DE AUDITORIA (ver DAAT, seccion de analisis de fallos):
          # esta aplicacion se despliega correctamente pero no llega a estado
          # RUNNING. El job de PyFlink requiere el conector de Kinesis, que en
          # Managed Flink no viene en el classpath. Se intento declararlo con
          # la propiedad `jarfile` apuntando al JAR empaquetado dentro del zip
          # (rutas normalizadas con "/" mediante scripts/build_flink_zip.py),
          # pero el servicio sigue respondiendo:
          #
          #   InvalidArgumentException: We couldn't find the configured file
          #   'lib/flink-sql-connector-kinesis-1.15.4.jar' in your zip file
          #
          # La propiedad queda documentada y desactivada para que el
          # `terraform apply` complete sin errores. El procesamiento en
          # streaming se ejecuta y evidencia con PyFlink local
          # (flink-app/iceberg_processor.py), que escribe a Iceberg y es el
          # job que sostiene el pipeline end-to-end de este proyecto.
          #
          # jarfile = "lib/flink-sql-connector-kinesis-1.15.4.jar"
        }
      }

      property_group {
        property_group_id = "consumer.config"
        property_map = {
          "input.stream.name" = var.kinesis_stream_name
          "aws.region"         = var.region
          "flink.stream.initpos" = "LATEST"
        }
      }
    }

    flink_application_configuration {
      checkpoint_configuration {
        configuration_type   = "CUSTOM"
        checkpointing_enabled = true
        checkpoint_interval   = 60000
        min_pause_between_checkpoints = 5000
      }

      monitoring_configuration {
        configuration_type = "CUSTOM"
        log_level           = "INFO"
        metrics_level       = "APPLICATION"
      }

      parallelism_configuration {
        configuration_type   = "CUSTOM"
        parallelism          = 1
        parallelism_per_kpu  = 1
        auto_scaling_enabled = false
      }
    }
  }

  cloudwatch_logging_options {
    log_stream_arn = aws_cloudwatch_log_stream.flink_log_stream.arn
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Name        = "${var.app_name}-${var.environment}"
  }
}
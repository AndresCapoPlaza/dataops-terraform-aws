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
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
        ]
        Resource = "*"
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

resource "aws_kinesisanalyticsv2_application" "clicks_processor" {
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
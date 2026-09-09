# BLOQUE A: KINESIS DATA STREAM
# ------------------------------------------------------------------------------
# 1. KINESIS DATA STREAM (KDS) — PROVISIONED, 2 shards
# ------------------------------------------------------------------------------
resource "aws_kinesis_stream" "main" {
  name             = var.stream_name
  shard_count      = var.shard_count
  retention_period = 24 # horas, default 24

  # Pre-entrega: el stream debe estar cifrado
  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  tags = {
    Name        = var.stream_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ------------------------------------------------------------------------------
# 2. IAM ROLE PARA FIREHOSE
# Leer del stream + escribir en S3 + logs en CloudWatch
# ------------------------------------------------------------------------------
resource "aws_iam_role" "firehose" {
  name = "firehose-kinesis-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "firehose" {
  name = "firehose-kinesis-policy"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords"
        ]
        Resource = aws_kinesis_stream.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:AbortMultipartUpload",
          "s3:ListBucketMultipartUploads",
          "s3:ListMultipartUploadParts"
        ]
        Resource = [
          "arn:aws:s3:::${var.bucket_name}",
          "arn:aws:s3:::${var.bucket_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream"
        ]
        Resource = "*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# 3. KINESIS DATA FIREHOSE (KDF) — source = KDS, destination = S3
# ------------------------------------------------------------------------------
resource "aws_kinesis_firehose_delivery_stream" "main" {
  name        = "ingesta-${var.stream_name}"
  destination = "extended_s3"

  # Nota: "extended_s3" es el destino s3 moderno de Terraform.
  # El recurso clásico "s3" está deprecado en favor de extended_s3.

  # Origen: el Kinesis Data Stream (patrón híbrido)
  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.main.arn
    role_arn           = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = "arn:aws:s3:::${var.bucket_name}"

    # Prefijos dinámicos (Bronze layer organizada por año)
    prefix              = "ingesta/year=!{timestamp:yyyy}/"
    error_output_prefix = "ingesta-errores/!{firehose:error-output-type}/year=!{timestamp:yyyy}/"

    # Política de buffering agresiva para desarrollo
    buffering_size     = var.buffer_size_mb     # 5 MB
    buffering_interval = var.buffer_interval_sec # 60 s

    # Compresión recomendada
    compression_format = "GZIP"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = "/aws/kinesis-firehose/${var.stream_name}"
      log_stream_name = "S3Delivery"
    }
  }

  tags = {
    Name        = "ingesta-${var.stream_name}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ------------------------------------------------------------------------------
# 4. OBSERVABILIDAD - Firehose en CloudWatch
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "read_throttle" {
  alarm_name          = "kinesis-read-throttled-${var.stream_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ReadProvisionedThroughputExceeded"
  namespace           = "AWS/Kinesis"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Lecturas excediendo la capacidad provisionada del stream"
  dimensions = {
    StreamName = aws_kinesis_stream.main.name
  }
}

resource "aws_cloudwatch_metric_alarm" "write_throttle" {
  alarm_name          = "kinesis-write-throttled-${var.stream_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "WriteProvisionedThroughputExceeded"
  namespace           = "AWS/Kinesis"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Escrituras excediendo la capacidad provisionada del stream"
  dimensions = {
    StreamName = aws_kinesis_stream.main.name
  }
}
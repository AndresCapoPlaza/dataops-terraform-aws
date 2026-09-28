# ------------------------------------------------------------------------------
# 0. CONTEXTO DE LA CUENTA
# Evita hardcodear account id y region en los ARN de las politicas.
# ------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ------------------------------------------------------------------------------
# Log group de Firehose gestionado por Terraform.
# Declararlo aqui permite acotar la politica IAM a su ARN en lugar de usar "*".
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesis-firehose/${var.stream_name}"
  retention_in_days = 7

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

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

  # --------------------------------------------------------------------------
  # METRICAS A NIVEL DE FRAGMENTO (enhanced monitoring)
  #
  # Por defecto Kinesis solo publica metricas agregadas del stream. Con eso, un
  # shard atrasado queda enmascarado por el promedio de los demas: el tablero
  # se ve sano mientras una particion concreta se hunde.
  #
  # Habilitarlas expone IteratorAgeMilliseconds con dimension ShardId, que es
  # lo que consumen las alarmas por fragmento definidas mas abajo.
  #
  # COSTO: se factura por metrica y por shard-hora. Con 2 shards y 5 metricas
  # el importe es marginal, pero escala de forma lineal con el numero de
  # fragmentos: en un stream de 200 shards conviene revisarlo.
  # --------------------------------------------------------------------------
  shard_level_metrics = var.enable_shard_level_metrics ? [
    "IncomingBytes",
    "IncomingRecords",
    "IteratorAgeMilliseconds",
    "ReadProvisionedThroughputExceeded",
    "WriteProvisionedThroughputExceeded",
  ] : []

  tags = {
    Name        = var.stream_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ------------------------------------------------------------------------------
# IDENTIFICADORES DE FRAGMENTO
#
# Kinesis nombra los shards de forma determinista al crear el stream:
# shardId-000000000000, shardId-000000000001, ... Como este stream se crea con
# un shard_count fijo y NO se reparte (no hay split ni merge), los nombres se
# pueden derivar y usar como dimension de las alarmas.
#
# LIMITACION CONOCIDA: al hacer resharding, Kinesis cierra los shards padres y
# crea hijos con identificadores nuevos y no contiguos. En ese escenario esta
# derivacion deja de ser valida y habria que enumerar los fragmentos con un
# data source o migrar a una alarma con expresion de busqueda de metricas.
# ------------------------------------------------------------------------------
locals {
  shard_ids = [for i in range(var.shard_count) : format("shardId-%012d", i)]
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
        # Acotado al log group de este delivery stream. Se elimino
        # logs:CreateLogGroup porque el grupo lo crea Terraform.
        Sid    = "WriteFirehoseLogs"
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogStream"
        ]
        Resource = "${aws_cloudwatch_log_group.firehose.arn}:*"
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


# ------------------------------------------------------------------------------
# ALARMA: ITERATOR AGE
# Mide cuanto se atrasa el consumidor respecto de la punta del shard. Es la
# senal temprana de backpressure: si el consumidor (Flink o Redshift) no drena
# al ritmo de escritura, esta metrica crece de forma sostenida hasta que los
# registros expiran por retencion y se pierden datos.
# Umbral: 60.000 ms (1 minuto) sobre la retencion de 24 h configurada.
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "iterator_age" {
  alarm_name          = "kinesis-iterator-age-${var.stream_name}"
  alarm_description   = "El consumidor se esta atrasando respecto de la punta del shard (backpressure)"
  namespace           = "AWS/Kinesis"
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 60000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = aws_kinesis_stream.main.name
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}


# ------------------------------------------------------------------------------
# ALARMA POR FRAGMENTO: ITERATOR AGE
#
# Complementa a la alarma agregada del stream. La diferencia importa: la
# metrica agregada usa el maximo entre fragmentos y puede tardar en reaccionar
# a un desbalance, mientras que estas alarmas identifican QUE shard concreto se
# atraso, que es el primer dato que hace falta para diagnosticar.
#
# Causa tipica de un unico shard atrasado: una clave de particion mal
# distribuida (hot shard). En ese escenario agregar fragmentos no resuelve
# nada, porque el trafico seguiria cayendo en el mismo: hay que cambiar la
# clave. Sin metricas por shard, ese diagnostico no es posible.
#
# Umbral igual al de la alarma agregada (60 s sostenidos durante 2 periodos),
# para que ambas sean comparables.
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "shard_iterator_age" {
  for_each = var.enable_shard_level_metrics ? toset(local.shard_ids) : toset([])

  alarm_name        = "kinesis-shard-lag-${var.stream_name}-${each.value}"
  alarm_description = "El fragmento ${each.value} se atrasa respecto de la punta del stream"

  namespace   = "AWS/Kinesis"
  metric_name = "IteratorAgeMilliseconds" # nombre sin prefijo: es metrica de shard
  statistic   = "Maximum"

  period              = 60
  evaluation_periods  = 2
  threshold           = 60000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = aws_kinesis_stream.main.name
    ShardId    = each.value
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

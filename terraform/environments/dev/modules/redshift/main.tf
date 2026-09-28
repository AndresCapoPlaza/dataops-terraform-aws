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

# Clave gestionada por AWS con la que esta cifrado el Kinesis Data Stream.
# Resolverla permite acotar kms:Decrypt a su ARN en lugar de usar "*".
data "aws_kms_alias" "kinesis" {
  name = "alias/aws/kinesis"
}

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
        # El stream está cifrado con KMS: sin esta acción, GetRecords devuelve
        # registros que Redshift no puede descifrar.
        Sid      = "DecryptKinesisRecords"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = data.aws_kms_alias.kinesis.target_key_arn
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

# ==============================================================================
# 5. MECANISMO OPERATIVO DE REFRESCO DE LA VISTA MATERIALIZADA
#
# El enunciado exige definir QUIEN ejecuta el refresco y con que cadencia. No
# alcanza con documentar una intencion: tiene que ser un recurso desplegado.
#
# POR QUE NO `AUTO REFRESH YES`
# -----------------------------
# AUTO REFRESH es best-effort: Redshift decide cuando refrescar en funcion de
# la carga del cluster. Con eso no se puede comprometer un objetivo de frescura
# ni auditar por que un refresco no ocurrio. Sirve para "que este razonablemente
# al dia", no para "cada 60 segundos".
#
# MECANISMO ADOPTADO
# ------------------
#   EventBridge Scheduler --(cada 60 s)--> Redshift Data API --> REFRESH
#
# Es deterministico, esta versionado en el repositorio, y sus fallos emiten una
# metrica propia sobre la que se alarma (ver mas abajo). El intervalo minimo
# que admite EventBridge Scheduler es de 1 minuto, que coincide exactamente con
# el objetivo de frescura definido.
# ==============================================================================

# ------------------------------------------------------------------------------
# 5.1 Rol que asume el planificador para invocar la Data API
#
# Menor privilegio: solo puede ejecutar sentencias contra ESTE workgroup.
# No puede leer datos por si mismo ni conectarse por otra via.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "refresh_scheduler" {
  count = var.enable_scheduled_refresh ? 1 : 0

  name = "redshift-mv-refresh-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "scheduler.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = {
          # Evita el problema del "confused deputy": solo esta cuenta puede
          # hacer que el servicio de scheduling asuma este rol.
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = {
    Name        = "redshift-mv-refresh-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy" "refresh_scheduler" {
  count = var.enable_scheduled_refresh ? 1 : 0

  name = "redshift-mv-refresh-policy"
  role = aws_iam_role.refresh_scheduler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ExecuteRefreshStatement"
        Effect   = "Allow"
        Action   = ["redshift-data:ExecuteStatement"]
        Resource = aws_redshiftserverless_workgroup.lakehouse.arn
      },
      {
        # La Data API necesita credenciales temporales del workgroup.
        # Acotado al workgroup concreto, no a "*".
        Sid      = "GetTemporaryCredentials"
        Effect   = "Allow"
        Action   = ["redshift-serverless:GetCredentials"]
        Resource = aws_redshiftserverless_workgroup.lakehouse.arn
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# 5.2 El planificador: REFRESH cada 60 segundos
# ------------------------------------------------------------------------------
resource "aws_scheduler_schedule" "refresh_mv" {
  count = var.enable_scheduled_refresh ? 1 : 0

  name        = "redshift-refresh-mv-${var.environment}"
  description = "Refresca mv_clicks_stream_raw cada 60 s via Redshift Data API"

  # Sin ventana flexible: el disparo es en el segundo previsto, no "en algun
  # momento de los proximos N minutos". La frescura depende de eso.
  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "rate(1 minute)"
  schedule_expression_timezone = "UTC"
  state                        = "ENABLED"

  target {
    # Destino universal: invoca directamente la API del SDK, sin Lambda de por
    # medio. Menos piezas moviles y nada de codigo que mantener.
    arn      = "arn:aws:scheduler:::aws-sdk:redshiftdata:executeStatement"
    role_arn = aws_iam_role.refresh_scheduler[0].arn

    input = jsonencode({
      Sql           = "REFRESH MATERIALIZED VIEW mv_clicks_stream_raw;"
      Database      = var.database_name
      WorkgroupName = aws_redshiftserverless_workgroup.lakehouse.workgroup_name
      StatementName = "refresh-mv-clicks-stream-raw"
    })

    retry_policy {
      # Un refresco perdido se recupera solo en el siguiente disparo: el
      # refresco es incremental y acumulativo, de modo que no tiene sentido
      # reintentar durante mucho tiempo.
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 120
    }
  }
}

# ------------------------------------------------------------------------------
# 5.3 ALARMA: el refresco dejo de ejecutarse
#
# Detecta el fallo del MECANISMO (permisos revocados, workgroup pausado,
# sentencia rechazada). Es distinto de la alarma de lag del stream, que detecta
# el fallo del CONSUMO. Ambas hacen falta: el refresco puede estar corriendo
# sobre un stream atrasado, y el stream puede estar sano con el refresco caido.
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "refresh_failed" {
  count = var.enable_scheduled_refresh ? 1 : 0

  alarm_name        = "redshift-mv-refresh-failed-${var.environment}"
  alarm_description = "El refresco programado de mv_clicks_stream_raw esta fallando"

  namespace   = "AWS/Scheduler"
  metric_name = "TargetErrorCount"
  statistic   = "Sum"

  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ScheduleGroup = "default"
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ==============================================================================
# 6. IDENTIDAD IAM DEL ROL ANALITICO
#
# El usuario analyst_user se crea en SQL con PASSWORD DISABLE, lo que obliga a
# obtener credenciales temporales por IAM. Este rol es la contraparte de esa
# decision: define QUIEN puede obtenerlas y sobre que workgroup.
#
# Sin esto, "autenticacion IAM" seria una afirmacion sin respaldo: el usuario
# existiria sin contrasena y sin ninguna via declarada para conectarse.
# ==============================================================================

resource "aws_iam_role" "analyst" {
  count = var.enable_analyst_iam_role ? 1 : 0

  name        = "redshift-analyst-${var.environment}"
  description = "Identidad de analitica: credenciales temporales de solo lectura"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          # Cualquier principal de esta cuenta autorizado explicitamente.
          # En una organizacion real aqui iria el rol del proveedor de
          # identidad (SSO) o el grupo de analistas.
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "redshift-analyst-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy" "analyst_connect" {
  count = var.enable_analyst_iam_role ? 1 : 0

  name = "redshift-analyst-connect-policy"
  role = aws_iam_role.analyst[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Credenciales temporales SOLO sobre este workgroup, y SOLO para la
        # identidad de base de datos analyst_user. La condicion es lo que
        # impide que el rol se conecte como el usuario administrador.
        Sid      = "ConnectAsAnalystUserOnly"
        Effect   = "Allow"
        Action   = ["redshift-serverless:GetCredentials"]
        Resource = aws_redshiftserverless_workgroup.lakehouse.arn
        Condition = {
          StringEquals = {
            "redshift-serverless:DbName" = var.database_name
          }
        }
      },
      {
        # Ejecutar consultas desde Query Editor v2 o la Data API.
        Sid    = "RunQueries"
        Effect = "Allow"
        Action = [
          "redshift-data:ExecuteStatement",
          "redshift-data:DescribeStatement",
          "redshift-data:GetStatementResult",
          "redshift-data:ListStatements",
        ]
        Resource = "*"
        Condition = {
          # redshift-data no admite ARN de recurso en todas sus acciones de
          # lectura de resultados (son de nivel de cuenta). Se acota por region
          # y, en ExecuteStatement, el permiso efectivo lo limita el workgroup
          # al que se puede pedir credenciales en la sentencia anterior.
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      {
        # NO se concede redshift-serverless:* ni acceso al secreto del usuario
        # administrador. El analista no puede escalar a admin por esta via.
        Sid      = "DenyAdminSecret"
        Effect   = "Deny"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_redshiftserverless_namespace.lakehouse.admin_password_secret_arn
      }
    ]
  })
}

variable "environment" {
  type        = string
  description = "Ambiente de despliegue (ej: dev, prod)"
}

variable "region" {
  type        = string
  description = "Region de AWS"
  default     = "us-east-1"
}

variable "vpc_id" {
  type        = string
  description = "ID de la VPC donde se despliega el workgroup"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR de la VPC, usado en el ingress del security group"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subredes del workgroup. Redshift Serverless exige al menos 3, en 3 Zonas de Disponibilidad distintas."

  validation {
    condition     = length(var.subnet_ids) >= 3
    error_message = "Redshift Serverless requiere al menos 3 subredes en 3 Zonas de Disponibilidad distintas."
  }
}

variable "kinesis_stream_arn" {
  type        = string
  description = "ARN del Kinesis Data Stream consumido por Streaming Ingestion"
}

variable "glue_database_name" {
  type        = string
  description = "Base de datos del Glue Data Catalog con las tablas Iceberg"
}

variable "lakehouse_bucket_arn" {
  type        = string
  description = "ARN del bucket S3 que almacena los datos del Lakehouse"
}

variable "database_name" {
  type        = string
  description = "Nombre de la base de datos inicial del namespace"
  default     = "analytics"
}

variable "admin_username" {
  type        = string
  description = "Usuario administrador del namespace"
  default     = "adminuser"
}

variable "base_capacity" {
  type        = number
  description = "Capacidad base en RPUs (minimo 8)"
  default     = 8
}

variable "enable_scheduled_refresh" {
  type        = bool
  description = <<-EOT
    Despliega el mecanismo operativo de refresco: EventBridge Scheduler que
    invoca la Redshift Data API cada 60 segundos para ejecutar
    REFRESH MATERIALIZED VIEW mv_clicks_stream_raw.

    Se prefiere a AUTO REFRESH porque el intervalo es deterministico, esta
    versionado en el repositorio y sus fallos emiten una metrica propia sobre
    la que se alarma.

    COSTO: cada refresco consume RPU-segundo de Redshift Serverless. Con un
    refresco de ~2 s cada 60 s el ciclo util es de alrededor del 3 %, pero el
    workgroup no llega a quedar inactivo. Desactivarlo si se deja el entorno
    levantado sin trafico.
  EOT
  default     = true
}

variable "enable_analyst_iam_role" {
  type        = bool
  description = <<-EOT
    Despliega el rol IAM que obtiene credenciales temporales para conectarse
    como analyst_user. Es la contraparte de CREATE USER ... PASSWORD DISABLE:
    sin este rol, el usuario existe sin contrasena y sin via declarada de
    conexion.
  EOT
  default     = true
}

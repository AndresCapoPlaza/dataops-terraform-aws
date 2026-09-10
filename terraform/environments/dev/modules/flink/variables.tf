variable "environment" {
  description = "Nombre del entorno (ej: dev)"
  type        = string
}

variable "app_name" {
  description = "Nombre de la aplicación de Flink"
  type        = string
  default     = "clicks-processor"
}

variable "kinesis_stream_arn" {
  description = "ARN del Kinesis Data Stream de origen"
  type        = string
}

variable "kinesis_stream_name" {
  description = "Nombre del Kinesis Data Stream de origen"
  type        = string
}

variable "code_bucket_arn" {
  description = "ARN del bucket S3 donde vive el código de la app"
  type        = string
}

variable "code_bucket_name" {
  description = "Nombre del bucket S3 donde vive el código de la app"
  type        = string
}

variable "code_s3_key" {
  description = "Key (ruta) del .zip del código dentro del bucket S3"
  type        = string
  default     = "flink/clicks_processor.zip"
}

variable "checkpoint_bucket_arn" {
  description = "ARN del bucket S3 usado para checkpoints"
  type        = string
}

variable "region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-1"
}

variable "enable_managed_flink" {
  type        = bool
  description = <<-EOT
    Despliega la aplicacion de Amazon Managed Service for Apache Flink.
    Desactivada por defecto: este recurso factura por KPU-hora de forma
    continua mientras existe (~USD 0,11/KPU-hora), y requiere que el artefacto
    clicks_processor.zip este previamente subido a S3. La logica de
    procesamiento se valida ejecutando el job localmente con PyFlink contra
    el stream real de Kinesis.
  EOT
  default     = false
}


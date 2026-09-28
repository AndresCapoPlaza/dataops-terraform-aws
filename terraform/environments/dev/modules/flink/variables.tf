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

    Activada por defecto para que un unico `terraform apply` levante el stack
    completo sin pasos manuales: Terraform sube el artefacto a S3 y crea la
    aplicacion en el orden correcto.

    ATENCION AL COSTO: este recurso factura por KPU-hora mientras existe
    (~USD 0,11/KPU-hora, unos USD 80/mes si se deja corriendo). Para entornos
    de estudio, ponerla en false o destruir el stack al terminar la sesion.
  EOT
  default     = true
}

variable "app_artifact_path" {
  description = <<-EOT
    Ruta local al .zip con el codigo de la aplicacion de Flink. Terraform lo
    sube a S3 antes de crear la aplicacion, de modo que el despliegue no
    requiere ninguna carga manual previa.
  EOT
  type        = string
}


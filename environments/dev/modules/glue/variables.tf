variable "flink_execution_role_id" {
  description = "ID del rol IAM de ejecución de Flink al que se le agregan permisos de Glue"
  type        = string
}

variable "lakehouse_bucket_arn" {
  description = "ARN del bucket S3 usado como Lakehouse"
  type        = string
}

variable "region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "ID de la cuenta de AWS"
  type        = string
}
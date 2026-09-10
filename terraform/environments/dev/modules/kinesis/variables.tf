variable "environment" {
  description = "The environment for the Kinesis resources (e.g., dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "stream_name" {
  type        = string
  description = "Nombre del Kinesis Data Stream"
  default     = "clicks-ecommerce"
}

variable "shard_count" {
  type        = number
  description = "Cantidad de shards (2 MB/s de entrada => 2 shards)"
  default     = 2
}

variable "bucket_name" {
  type        = string
  description = "Bucket S3 destino de Firehose (el del Módulo 1)"
  # Sin default Terraform pregunta
}

variable "buffer_size_mb" {
  type        = number
  description = "Tamaño del buffer de Firehose en MB"
  default     = 5
}

variable "buffer_interval_sec" {
  type        = number
  description = "Intervalo del buffer de Firehose en segundos"
  default     = 60
}

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

variable "enable_shard_level_metrics" {
  type        = bool
  description = <<-EOT
    Habilita las metricas por fragmento (enhanced monitoring) del Kinesis Data
    Stream y despliega una alarma de IteratorAge por cada shard.

    POR QUE: las metricas agregadas del stream enmascaran un unico fragmento
    atrasado. Sin desglose por ShardId no se puede distinguir un hot shard de
    una saturacion general, y el diagnostico cambia por completo: el primero se
    corrige cambiando la clave de particion, el segundo agregando fragmentos.

    COSTO: se factura por metrica y por shard-hora. Con 2 shards es marginal;
    escala de forma lineal con el numero de fragmentos.
  EOT
  default     = true
}

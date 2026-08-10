variable "environment" {
  type        = string
  description = "Nombre del ambiente"
}
variable "bucket_arn" {
  type        = string
  description = "ARN del Bucket S3 al que se le aplicarán los permisos acotados"
}
variable "prefix" {
  type        = string
  description = "Prefijo/Carpeta específica dentro de S3"
  default     = "raw-data/*"
}
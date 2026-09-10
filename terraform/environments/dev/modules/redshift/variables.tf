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

variable "environment" {
  type        = string
  description = "Ambiente de despliegue (ej: dev, prod)"
}
variable "vpc_cidr" {
  type        = string
  description = "Rango de direcciones IP para la red VPC"
  default     = "10.0.0.0/16"
}
variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Rangos de IP para las subredes privadas"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}
variable "availability_zones" {
  type        = list(string)
  description = "Zonas de Disponibilidad (AZs) para alta disponibilidad"
  default     = ["us-east-1a", "us-east-1b"]
}
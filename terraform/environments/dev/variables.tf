variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "environment" {
  type    = string
  default = "dev"
}
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
# La variable account_id fue eliminada: el identificador de cuenta se resuelve
# con data.aws_caller_identity.current, de modo que no queda ningun valor fijo
# en el codigo ni hace falta pasarlo por linea de comandos.

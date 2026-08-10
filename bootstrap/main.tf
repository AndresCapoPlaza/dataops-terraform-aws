# Configuración del Proveedor AWS
provider "aws" {
region = var.aws_region
}
# ------------------------------------------------------------------------------
# 1. BUCKET S3 PARA GUARDAR EL ESTADO REMOTO (.tfstate)
# Almacena el archivo central que describe la infraestructura.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "tf_state" {
  # El nombre debe ser único a nivel MUNDIAL en AWS.
  bucket        = "coderhouse-dataops-tfstate-2026-andres-${var.environment}"
  force_destroy = true

  tags = {
    Name        = "Terraform State Storage"
    Environment = var.environment
    ManagedBy   = "Terraform-Bootstrap"
  }
}
# ------------------------------------------------------------------------------
# 2. VERSIONADO DEL BUCKET S3
# Permite guardar un historial de cambios para recuperar estados ante corrupción.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "tf_state_versioning" {
bucket = aws_s3_bucket.tf_state.id
versioning_configuration {
status = "Enabled"
}
}
# ------------------------------------------------------------------------------
# 3. CIFRADO AUTOMÁTICO EN REPOSO (AES256)
# Garantiza que los datos sensibles del estado estén cifrados por defecto.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state_crypto" {
bucket = aws_s3_bucket.tf_state.id
rule {
apply_server_side_encryption_by_default {
sse_algorithm = "AES256"
}
}
}
# ------------------------------------------------------------------------------
# 4. TABLA DYNAMODB PARA CONTROL DE CONCURRENCIA (State Locking)
# Evita que dos ingenieros apliquen cambios en simultáneo y corrompan el estado.
# ------------------------------------------------------------------------------
resource "aws_dynamodb_table" "tf_locks" {
name = "terraform-locks-${var.environment}"
billing_mode = "PAY_PER_REQUEST" # Pagas solo por demanda
hash_key = "LockID" # Requisito obligatorio de Terraform
attribute {
name = "LockID"
type = "S" # String
}          
}
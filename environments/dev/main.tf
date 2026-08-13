# 1. Invocación del Módulo de Red Base
module "network" {
  source      = "./modules/network"
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
}
# 2. Bucket S3 para Data Lake (Capa RAW)
resource "aws_s3_bucket" "raw_bucket" {
  bucket        = "datalake-raw-${var.environment}-${var.account_id}"
  force_destroy = true
  tags = {
    Name        = "Data Lake Raw Bucket"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
# 3. Invocación del Módulo IAM Acotado
module "identity" {
  source      = "./modules/identity"
  environment = var.environment
  bucket_arn  = aws_s3_bucket.raw_bucket.arn
  prefix      = "raw-data/*"
}

module "kinesis" {
  source = "./modules/kinesis"

  environment        = var.environment
  stream_name        = "clicks-ecommerce"
  shard_count        = 2
  bucket_name        = aws_s3_bucket.raw_bucket.bucket
  buffer_size_mb     = 5
  buffer_interval_sec = 60
}
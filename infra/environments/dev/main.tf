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


resource "aws_s3_bucket_versioning" "raw_bucket_versioning" {
  bucket = aws_s3_bucket.raw_bucket.id
  versioning_configuration {
    status = "Enabled"
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


module "flink" {
  source = "./modules/flink"

  environment           = var.environment
  app_name              = "clicks-processor"
  kinesis_stream_arn    = module.kinesis.stream_arn
  kinesis_stream_name   = "clicks-ecommerce"
  code_bucket_arn       = aws_s3_bucket.raw_bucket.arn
  code_bucket_name      = aws_s3_bucket.raw_bucket.bucket
  code_s3_key           = "flink/clicks_processor.zip"
  checkpoint_bucket_arn = aws_s3_bucket.raw_bucket.arn
  region                = "us-east-1"
}

module "glue" {
  source = "./modules/glue"

  flink_execution_role_id = module.flink.flink_execution_role_name
  lakehouse_bucket_arn    = aws_s3_bucket.raw_bucket.arn
  region                  = "us-east-1"
}

# ==============================================================================
# ENTREGA 6 - Capa de analitica de baja latencia (Redshift Serverless)
# ==============================================================================

module "redshift" {
  source = "./modules/redshift"

  environment          = var.environment
  region               = "us-east-1"
  vpc_id               = module.network.vpc_id
  vpc_cidr             = var.vpc_cidr
  subnet_ids           = module.network.private_subnet_ids
  kinesis_stream_arn   = module.kinesis.stream_arn
  glue_database_name   = module.glue.database_name
  lakehouse_bucket_arn = aws_s3_bucket.raw_bucket.arn
}

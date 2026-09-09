terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Configuración del Backend Remoto S3 + DynamoDB
  backend "s3" {
    bucket         = "coderhouse-dataops-tfstate-2026-andres-dev"
    key            = "dev/infrastructure-base.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks-dev"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}
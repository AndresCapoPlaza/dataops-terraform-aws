# ------------------------------------------------------------------------------
# 1. VPC PRINCIPAL (Virtual Private Cloud)
# Nube privada virtual aislada donde residen los recursos de datos.
# ------------------------------------------------------------------------------
resource "aws_vpc" "data_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name        = "vpc-data-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
# ------------------------------------------------------------------------------
# 2. SUBREDES PRIVADAS
# Utiliza 'count' para distribuir subredes en distintas Zonas de Disponibilidad.
# ------------------------------------------------------------------------------
resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.data_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "subnet-private-${var.environment}-${count.index + 1}"
    Environment = var.environment
    Layer       = "PrivateData"
    ManagedBy   = "Terraform"
  }
}
# ------------------------------------------------------------------------------
# 3. TABLA DE RUTEO PRIVADA Y ASOCIACIÓN
# ------------------------------------------------------------------------------
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.data_vpc.id
  tags = {
    Name        = "rt-private-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}
# ------------------------------------------------------------------------------
# 4. S3 GATEWAY VPC ENDPOINT
# Conexión directa y privada a S3 dentro de la red interna de AWS (Costo $0).
# ------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id            = aws_vpc.data_vpc.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_rt.id]
  tags = {
    Name        = "vpce-s3-gateway-${var.environment}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
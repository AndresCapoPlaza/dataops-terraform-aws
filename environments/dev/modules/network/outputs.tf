output "vpc_id" {
  value       = aws_vpc.data_vpc.id
  description = "ID de la VPC creada"
}
output "private_subnet_ids" {
  value       = aws_subnet.private_subnets[*].id
  description = "Lista de IDs de subredes privadas"
}
output "s3_endpoint_id" {
  value       = aws_vpc_endpoint.s3_endpoint.id
  description = "ID del S3 Gateway Endpoint"
}
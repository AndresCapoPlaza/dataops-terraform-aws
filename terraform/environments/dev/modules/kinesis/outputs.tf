output "stream_arn" {
  value = aws_kinesis_stream.main.arn
}

output "stream_name" {
  value = aws_kinesis_stream.main.name
}

output "firehose_arn" {
  value = aws_kinesis_firehose_delivery_stream.main.arn
}

output "firehose_name" {
  value = aws_kinesis_firehose_delivery_stream.main.name
}
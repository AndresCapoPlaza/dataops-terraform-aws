# ============================================================
# Verificacion de la Pre-entrega 5 (Lakehouse Iceberg + Glue)
# Ejecutar DESPUES de que el job de Flink haya completado checkpoints.
# ============================================================

$ErrorActionPreference = "Stop"
$BUCKET = "datalake-raw-dev-123456789012"
$DB     = "lakehouse_db"
$TABLE  = "clicks_by_product"
$REGION = "us-east-1"

Write-Host "`n=== 1. metadata_location en Glue (debe AVANZAR de 00000 a 00001+) ===" -ForegroundColor Cyan
aws glue get-table --database-name $DB --name $TABLE --region $REGION `
  --query "Table.Parameters.metadata_location"

Write-Host "`n=== 2. Archivos de DATOS en S3 (debe existir .../data/product_id=.../*.parquet) ===" -ForegroundColor Cyan
aws s3 ls "s3://$BUCKET/lakehouse/$DB.db/$TABLE/data/" --recursive --region $REGION

Write-Host "`n=== 3. Metadata Iceberg en S3 (metadata.json + snap-*.avro + *.avro manifests) ===" -ForegroundColor Cyan
aws s3 ls "s3://$BUCKET/lakehouse/$DB.db/$TABLE/metadata/" --recursive --region $REGION

Write-Host "`n=== 4. Consulta en Athena ===" -ForegroundColor Cyan
$q = aws athena start-query-execution `
  --query-string "SELECT product_id, window_end, click_count FROM $DB.$TABLE ORDER BY window_end DESC, product_id LIMIT 20;" `
  --result-configuration "OutputLocation=s3://$BUCKET/athena-results/" `
  --region $REGION --query "QueryExecutionId" --output text

Write-Host "QueryExecutionId: $q"
Start-Sleep -Seconds 8
aws athena get-query-execution --query-execution-id $q --region $REGION `
  --query "QueryExecution.Status.[State,StateChangeReason]"
aws athena get-query-results --query-execution-id $q --region $REGION `
  --query "ResultSet.Rows[].Data[].VarCharValue" --output table

Write-Host "`n=== 5. Partition pruning: la misma consulta filtrando por particion ===" -ForegroundColor Cyan
$q2 = aws athena start-query-execution `
  --query-string "SELECT SUM(click_count) AS total FROM $DB.$TABLE WHERE product_id = 'product-3';" `
  --result-configuration "OutputLocation=s3://$BUCKET/athena-results/" `
  --region $REGION --query "QueryExecutionId" --output text
Start-Sleep -Seconds 8
aws athena get-query-execution --query-execution-id $q2 --region $REGION `
  --query "QueryExecution.Statistics.[DataScannedInBytes,EngineExecutionTimeInMillis]"
aws athena get-query-results --query-execution-id $q2 --region $REGION `
  --query "ResultSet.Rows[].Data[].VarCharValue" --output table

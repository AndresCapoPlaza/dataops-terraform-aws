-- =============================================================================
-- PROYECTO FINAL | DDL de la capa Lakehouse (Apache Iceberg sobre AWS Glue)
-- Autor: Andres Capo Plaza
--
-- QUE ES ESTE ARCHIVO
-- -------------------
-- El DDL que ejecuta el job de PyFlink `flink-app/iceberg_processor.py` contra
-- el Table API de Flink. Se versiona por separado para que un auditor pueda
-- leer el modelo de datos sin abrir el codigo Python, y para poder ejecutarlo
-- a mano desde el SQL Client de Flink si hiciera falta recrear el catalogo.
--
-- NO se ejecuta contra Redshift ni contra Athena: es dialecto Flink SQL.
-- Las vistas de Redshift viven en `sql/checkpoint6_redshift.sql`.
--
-- PREREQUISITO: la variable ${LAKEHOUSE_BUCKET} se resuelve desde el output
-- `raw_bucket_name` de Terraform. No hay account id ni nombre de bucket fijo
-- en ningun punto del repositorio.
--     terraform -chdir=terraform/environments/dev output -raw raw_bucket_name
-- =============================================================================


-- =============================================================================
-- BLOQUE 1 | ORIGEN: tabla logica sobre el Kinesis Data Stream
-- =============================================================================

-- El conector lee el stream en formato `raw` (un STRING por registro) y los
-- campos se derivan con columnas calculadas. Esto evita que un cambio en el
-- esquema del JSON rompa la deserializacion del connector: si manana el
-- productor agrega un campo, JSON_VALUE simplemente lo ignora.
--
-- WATERMARK: se tolera un desorden de 10 segundos. Es el compromiso entre
-- completitud y latencia:
--   watermark corto  -> ventanas cierran antes, pero se descartan rezagados
--   watermark largo  -> mas completo, pero el resultado tarda mas en emitirse
-- Con un productor propio en la misma region, 10 s cubre holgadamente la
-- variacion de red observada (latencia medida de ingesta: 2-3 s).
CREATE TABLE clicks_source (
    raw_json   STRING,
    product_id AS JSON_VALUE(raw_json, '$.product_id'),
    event_time AS CAST(
        SUBSTRING(REPLACE(JSON_VALUE(raw_json, '$.timestamp'), 'T', ' '), 1, 23)
        AS TIMESTAMP(3)
    ),
    WATERMARK FOR event_time AS event_time - INTERVAL '10' SECOND
) WITH (
    'connector'            = 'kinesis',
    'stream'               = 'clicks-ecommerce',
    'aws.region'           = 'us-east-1',
    'scan.stream.initpos'  = 'LATEST',
    'format'               = 'raw'
);


-- =============================================================================
-- BLOQUE 2 | CATALOGO: Glue Data Catalog como metastore de Iceberg
-- =============================================================================

-- GlueCatalog + S3FileIO: los metadatos de la tabla (snapshots, manifiestos,
-- esquema) se registran en Glue y los archivos Parquet viven en S3. Athena y
-- Redshift Spectrum leen exactamente el mismo catalogo, sin copiar datos.
--
-- CONCURRENCIA: Glue resuelve los commits concurrentes con bloqueo optimista
-- sobre el VersionId de la tabla. Para escrituras desde varios jobs en
-- paralelo se puede activar el lock manager de DynamoDB, ya provisto por
-- Terraform (tabla `iceberg_glue_lock`), agregando:
--     'lock-impl' = 'org.apache.iceberg.aws.dynamodb.DynamoDbLockManager',
--     'lock.table' = 'iceberg_glue_lock'
-- Con un unico escritor, como en este pipeline, no es necesario.
CREATE CATALOG glue_catalog WITH (
    'type'          = 'iceberg',
    'catalog-impl'  = 'org.apache.iceberg.aws.glue.GlueCatalog',
    'warehouse'     = 's3://${LAKEHOUSE_BUCKET}/lakehouse/',
    'io-impl'       = 'org.apache.iceberg.aws.s3.S3FileIO',
    'glue.region'   = 'us-east-1',
    'client.region' = 'us-east-1'
);

CREATE DATABASE IF NOT EXISTS glue_catalog.lakehouse_db;


-- =============================================================================
-- BLOQUE 3 | DESTINO: tabla Iceberg particionada
-- =============================================================================

-- PARTICIONADO POR product_id: es la clave de filtro dominante de las consultas
-- analiticas, de modo que Athena aplica partition pruning y escanea un solo
-- prefijo en S3 en vez de la tabla completa.
--
-- format-version = 2  habilita deletes a nivel de fila (merge-on-read), lo que
--                     deja abierta la puerta a correcciones sin reescribir
--                     particiones enteras.
-- zstd                mejor ratio de compresion que snappy con un costo de CPU
--                     despreciable para este volumen; menos bytes en S3 y menos
--                     bytes escaneados por Athena, que es lo que se factura.
-- delete-after-commit se descartan los metadata.json antiguos y solo se
-- + previous-versions  conservan las ultimas 20 versiones. Sin esto, el prefijo
--                     /metadata crece de forma indefinida en un job de
--                     streaming que commitea cada 30 segundos.
CREATE TABLE IF NOT EXISTS glue_catalog.lakehouse_db.clicks_by_product (
    product_id  STRING,
    window_end  TIMESTAMP(3),
    click_count BIGINT
) PARTITIONED BY (product_id)
WITH (
    'format-version'                            = '2',
    'write.format.default'                      = 'parquet',
    'write.parquet.compression-codec'           = 'zstd',
    'write.metadata.delete-after-commit.enabled' = 'true',
    'write.metadata.previous-versions-max'      = '20'
);


-- =============================================================================
-- BLOQUE 4 | LA TRANSFORMACION: ventana TUMBLE de 1 minuto sobre event time
-- =============================================================================

-- Este INSERT es el job de streaming propiamente dicho: nunca termina.
--
-- IDEMPOTENCIA DEL SINK: el IcebergFilesCommitter solo publica un snapshot en
-- `notifyCheckpointComplete`, y registra el id del checkpoint en los metadatos
-- del snapshot. Si el job se reinicia desde el ultimo checkpoint y vuelve a
-- generar archivos de datos ya commiteados, el committer descarta esos commits
-- por id duplicado. Los archivos Parquet huerfanos quedan en S3 sin ser
-- referenciados por ningun snapshot: ocupan espacio, pero NO se leen ni
-- duplican filas. Se limpian con el procedimiento `remove_orphan_files`.
INSERT INTO glue_catalog.lakehouse_db.clicks_by_product
SELECT
    product_id,
    TUMBLE_END(event_time, INTERVAL '1' MINUTE) AS window_end,
    COUNT(*)                                    AS click_count
FROM clicks_source
GROUP BY TUMBLE(event_time, INTERVAL '1' MINUTE), product_id;


-- =============================================================================
-- BLOQUE 5 | VERIFICACION (dialecto Athena / Trino, no Flink)
-- =============================================================================

-- Ultimas ventanas cerradas por Flink.
-- SELECT product_id, window_end, click_count
-- FROM lakehouse_db.clicks_by_product
-- ORDER BY window_end DESC, product_id
-- LIMIT 20;

-- Partition pruning: al filtrar por la columna de particion, Athena escanea
-- un unico prefijo de S3. Comparar "Data scanned" con y sin el WHERE.
-- SELECT SUM(click_count) AS total
-- FROM lakehouse_db.clicks_by_product
-- WHERE product_id = 'product-1';

-- Historial de snapshots: un snapshot por checkpoint con datos.
-- SELECT * FROM "lakehouse_db"."clicks_by_product$snapshots"
-- ORDER BY committed_at DESC;

-- Archivos huerfanos (los que dejo un reinicio): no estan en ningun snapshot.
-- CALL system.remove_orphan_files(table => 'lakehouse_db.clicks_by_product');

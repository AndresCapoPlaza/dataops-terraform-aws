-- =============================================================================
-- PRE-ENTREGA 6 | Analitica avanzada in-stream con Amazon Redshift
-- Proyecto: pipeline DataOps - clicks de e-commerce
-- Autor:    Andres Capo Plaza
--
-- Arquitectura:
--   Kinesis Data Stream (clicks-ecommerce)
--        |-- Redshift Streaming Ingestion --> datos CALIENTES (segundos)
--        |-- Flink --> Iceberg / Glue ------> datos HISTORICOS (Lakehouse)
--                                   ambos consultables en la misma sesion SQL
--
-- Convenciones de nombrado usadas en todo el script:
--   ext_*  esquemas externos (fuentes fuera de Redshift)
--   mv_*   vistas materializadas
--   v_*    vistas logicas
--
-- ANTES DE EJECUTAR: reemplazar arn:aws:iam::010798385513:role/redshift-serverless-dev por el valor del output
-- `redshift_iam_role_arn` de Terraform.
-- =============================================================================


-- =============================================================================
-- BLOQUE 1 | INGESTA DIRECTA DESDE KINESIS (Streaming Ingestion)
-- =============================================================================

-- 1.1 Esquema externo que puentea Kinesis con Redshift.
--     No hay S3 intermedio: Redshift lee los shards directamente, lo que baja
--     la latencia de minutos (ruta Firehose -> S3 -> COPY) a segundos.
CREATE EXTERNAL SCHEMA IF NOT EXISTS ext_kinesis
FROM KINESIS
IAM_ROLE 'arn:aws:iam::010798385513:role/redshift-serverless-dev';


-- 1.2 Vista materializada de aterrizaje (landing).
--
--     DECISION DE DISENO - proteccion frente a "schema drift":
--     esta MV NO castea a tipos nativos. Guarda el payload como SUPER y marca
--     cada registro como parseable o no con CAN_JSON_PARSE. Si manana el
--     productor cambia la estructura del JSON o emite un registro corrupto,
--     la ingesta NO se rompe: el registro entra igual y queda aislado para
--     inspeccion. El casteo a tipos nativos ocurre recien en el Bloque 2,
--     sobre los registros ya validados.
--
--     AUTO REFRESH NO: el refresco se gobierna de forma explicita (Bloque 5).
CREATE MATERIALIZED VIEW mv_clicks_stream_raw
DISTSTYLE EVEN
SORTKEY (approximate_arrival_timestamp)
AUTO REFRESH NO
AS
SELECT
    -- Metadatos que aporta Kinesis en cada registro
    kinesis.approximate_arrival_timestamp,
    kinesis.shard_id,
    kinesis.sequence_number,
    kinesis.partition_key,
    kinesis.refresh_time,

    -- Bandera de validez: permite detectar drift sin perder el dato
    CAN_JSON_PARSE(FROM_VARBYTE(kinesis.kinesis_data, 'utf-8')) AS es_json_valido,

    -- Payload crudo, util para auditar registros que no parsean
    FROM_VARBYTE(kinesis.kinesis_data, 'utf-8') AS payload_texto,

    -- Payload semiestructurado (tipo SUPER) para navegacion con notacion punto
    CASE
        WHEN CAN_JSON_PARSE(FROM_VARBYTE(kinesis.kinesis_data, 'utf-8'))
        THEN JSON_PARSE(FROM_VARBYTE(kinesis.kinesis_data, 'utf-8'))
        ELSE NULL
    END AS payload
FROM ext_kinesis."clicks-ecommerce" AS kinesis;


-- 1.3 Primera carga.
REFRESH MATERIALIZED VIEW mv_clicks_stream_raw;


-- =============================================================================
-- BLOQUE 2 | MODELADO DEL JSON A TIPOS NATIVOS
-- =============================================================================

-- 2.1 Vista tipada sobre los registros validos.
--     Extrae y castea 5 campos del JSON a tipos nativos de Redshift.
--
--     Estructura del evento de origen:
--       { "event_id": "uuid", "user_id": "user-1", "event_type": "click",
--         "product_id": "product-1", "timestamp": "2026-09-09T02:37:00.123+00:00" }
CREATE OR REPLACE VIEW v_clicks_tipado AS
SELECT
    -- Extraccion con JSON_EXTRACT_PATH_TEXT: determinista y sin comillas
    -- residuales, a diferencia del cast directo de SUPER a VARCHAR.
    json_extract_path_text(k.payload_texto, 'event_id')   AS event_id,
    json_extract_path_text(k.payload_texto, 'user_id')    AS user_id,
    json_extract_path_text(k.payload_texto, 'event_type') AS event_type,
    json_extract_path_text(k.payload_texto, 'product_id') AS product_id,

    -- Event time. Se castea a TIMESTAMP (no TIMESTAMPTZ) para que DATEDIFF
    -- pueda compararlo con approximate_arrival_timestamp, que Kinesis entrega
    -- como TIMESTAMP sin zona. Ambos valores estan en UTC.
    json_extract_path_text(k.payload_texto, 'timestamp')::TIMESTAMP AS event_timestamp,

    -- Timestamp de llegada a Kinesis (processing time). La diferencia entre
    -- ambos es la latencia real de la ruta productor -> stream.
    k.approximate_arrival_timestamp,

    -- Latencia de ingesta en segundos, util para el monitoreo del Bloque 6
    DATEDIFF(
        second,
        json_extract_path_text(k.payload_texto, 'timestamp')::TIMESTAMP,
        k.approximate_arrival_timestamp
    ) AS latencia_ingesta_seg,

    k.shard_id,
    k.sequence_number
FROM mv_clicks_stream_raw AS k
WHERE k.es_json_valido = TRUE;   -- los invalidos quedan fuera, pero no se pierden


-- 2.2 Cuarentena: registros que no parsean.
--     Consultar esta vista es la forma de detectar schema drift a tiempo.
CREATE OR REPLACE VIEW v_clicks_cuarentena AS
SELECT
    approximate_arrival_timestamp,
    shard_id,
    sequence_number,
    payload_texto
FROM mv_clicks_stream_raw
WHERE es_json_valido = FALSE;


-- 2.3 Agregacion en tiempo real: clicks por producto y por minuto.
--     Equivale a la ventana TUMBLE de 1 minuto que calcula Flink, pero
--     resuelta en el momento de la consulta sobre los datos calientes.
CREATE OR REPLACE VIEW v_clicks_por_minuto AS
SELECT
    product_id,
    DATE_TRUNC('minute', event_timestamp)      AS ventana_minuto,
    COUNT(*)                                   AS clicks,
    COUNT(DISTINCT user_id)                    AS usuarios_unicos,
    ROUND(AVG(latencia_ingesta_seg), 2)        AS latencia_media_seg
FROM v_clicks_tipado
GROUP BY 1, 2;


-- =============================================================================
-- BLOQUE 3 | INTEGRACION CON EL LAKEHOUSE (Iceberg via Glue Data Catalog)
-- =============================================================================

-- 3.1 Esquema externo apuntando al Glue Data Catalog de la Entrega 5.
--     Redshift Spectrum lee las tablas Iceberg leyendo sus metadatos en Glue
--     y sus archivos Parquet en S3, sin copiar ni mover datos.
CREATE EXTERNAL SCHEMA IF NOT EXISTS ext_lakehouse
FROM DATA CATALOG
DATABASE 'lakehouse_db'
IAM_ROLE 'arn:aws:iam::010798385513:role/redshift-serverless-dev'
REGION 'us-east-1';


-- 3.2 Verificacion: la tabla Iceberg es visible desde Redshift.
SELECT product_id, window_end, click_count
FROM ext_lakehouse.clicks_by_product
ORDER BY window_end DESC, product_id
LIMIT 20;


-- 3.3 CONSULTA FEDERADA: datos calientes + datos historicos en una sola query.
--
--     Este es el objetivo central de la entrega: el stream aporta lo que esta
--     pasando ahora (segundos de latencia) y el Lakehouse aporta el historico
--     consolidado por Flink. Ambos conviven en la misma sesion SQL.
CREATE OR REPLACE VIEW v_clicks_hot_vs_cold AS
WITH caliente AS (
    -- Ultimos 15 minutos, directo del stream
    SELECT
        product_id,
        COUNT(*) AS clicks_ahora
    FROM v_clicks_tipado
    WHERE event_timestamp >= DATEADD(minute, -15, GETDATE())
    GROUP BY product_id
),
historico AS (
    -- Consolidado por Flink en la tabla Iceberg
    SELECT
        product_id,
        SUM(click_count)   AS clicks_historicos,
        COUNT(*)           AS ventanas_registradas,
        MAX(window_end)    AS ultima_ventana
    FROM ext_lakehouse.clicks_by_product
    GROUP BY product_id
)
SELECT
    COALESCE(c.product_id, h.product_id)          AS product_id,
    COALESCE(c.clicks_ahora, 0)                   AS clicks_ultimos_15_min,
    COALESCE(h.clicks_historicos, 0)              AS clicks_historicos,
    h.ventanas_registradas,
    h.ultima_ventana,
    -- Indice de tendencia: actividad reciente contra el promedio historico
    CASE
        WHEN COALESCE(h.clicks_historicos, 0) = 0 THEN NULL
        ELSE ROUND(
            COALESCE(c.clicks_ahora, 0)::DECIMAL(12, 4)
            / NULLIF(h.clicks_historicos, 0) * 100, 2
        )
    END AS pct_sobre_historico
FROM caliente c
FULL OUTER JOIN historico h ON c.product_id = h.product_id
-- Obligatorio: una vista que referencia tablas externas debe ser late-binding.
-- Redshift valida dependencias al crear la vista, pero los metadatos de un
-- esquema externo viven en Glue y pueden evolucionar de forma independiente.
WITH NO SCHEMA BINDING;


-- 3.4 Resultado de la consulta federada.
SELECT * FROM v_clicks_hot_vs_cold ORDER BY clicks_ultimos_15_min DESC;


-- =============================================================================
-- BLOQUE 4 | SEGURIDAD: rol de analitica con privilegios acotados
-- =============================================================================

-- 4.1 Rol especifico de analitica (RBAC nativo de Redshift).
CREATE ROLE analytics_reader;

-- 4.2 Permisos estrictamente de lectura sobre las tres capas.
GRANT USAGE ON SCHEMA public        TO ROLE analytics_reader;
GRANT USAGE ON SCHEMA ext_lakehouse TO ROLE analytics_reader;

GRANT SELECT ON mv_clicks_stream_raw   TO ROLE analytics_reader;
GRANT SELECT ON v_clicks_tipado        TO ROLE analytics_reader;
GRANT SELECT ON v_clicks_por_minuto    TO ROLE analytics_reader;
GRANT SELECT ON v_clicks_hot_vs_cold   TO ROLE analytics_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA ext_lakehouse TO ROLE analytics_reader;

-- 4.3 El esquema de ingesta queda FUERA del rol de analitica: un analista
--     consulta los datos modelados, no la fuente cruda del stream.
--     (no se otorga USAGE sobre ext_kinesis)

-- 4.4 Usuario de analitica con autenticacion IAM.
--     PASSWORD DISABLE fuerza el acceso federado: no existe contrasena que
--     robar ni rotar, la identidad la valida IAM.
CREATE USER analyst_user PASSWORD DISABLE;
GRANT ROLE analytics_reader TO analyst_user;

-- 4.5 Verificacion de los privilegios otorgados.
SELECT role_name, ddl FROM svv_roles WHERE role_name = 'analytics_reader';
SELECT * FROM svv_user_grants WHERE user_name = 'analyst_user';


-- =============================================================================
-- BLOQUE 5 | ESTRATEGIA DE REFRESCO
-- =============================================================================

-- El refresco de una MV de streaming ingestion es INCREMENTAL: Redshift lee
-- solo los registros posteriores al ultimo sequence_number procesado por shard.
-- No reprocesa el historico.
--
-- TRADE-OFF DE LATENCIA (error comun senalado en el enunciado):
--   refresco cada 1 s   -> latencia minima, pero el cluster queda saturado
--                          refrescando y el costo en RPU se dispara
--   refresco cada 30-60 s -> latencia aceptable para el negocio y consumo
--                          de RPU acotado
--
-- Para este caso de uso (ranking de productos por actividad reciente) una
-- latencia de 60 segundos es holgadamente suficiente: ninguna decision
-- comercial se toma con granularidad menor. Se adopta AUTO REFRESH con
-- intervalo gobernado por Redshift, que refresca segun carga del cluster
-- respetando ese orden de magnitud.

-- 5.1 Refresco manual (usado en la demostracion, control total del momento).
REFRESH MATERIALIZED VIEW mv_clicks_stream_raw;

-- 5.2 Activar refresco automatico para operacion continua.
ALTER MATERIALIZED VIEW mv_clicks_stream_raw AUTO REFRESH YES;

-- 5.3 Volver a manual (recomendado al terminar la demo, para no consumir RPU).
-- ALTER MATERIALIZED VIEW mv_clicks_stream_raw AUTO REFRESH NO;


-- =============================================================================
-- BLOQUE 6 | MONITOREO DE INGESTA Y LAG
-- =============================================================================

-- 6.1 Estado del scan por shard: posicion, registros leidos y retraso.
SELECT
    trim(external_schema_name) AS esquema,
    trim(stream_name)          AS stream,
    trim(shard_id)             AS shard,
    record_time,
    total_bytes,
    total_records
FROM sys_stream_scan_states
ORDER BY record_time DESC
LIMIT 20;

-- 6.2 Errores de ingesta (registros descartados, problemas de permisos).
SELECT * FROM sys_stream_scan_errors ORDER BY record_time DESC LIMIT 20;

-- 6.3 Historial de refrescos: duracion y filas incorporadas en cada uno.
SELECT
    mv_name,
    status,
    start_time,
    end_time,
    DATEDIFF(second, start_time, end_time) AS duracion_seg
FROM sys_mv_refresh_history
WHERE mv_name = 'mv_clicks_stream_raw'
ORDER BY start_time DESC
LIMIT 20;

-- 6.4 Estado general de las vistas materializadas.
SELECT * FROM svv_mv_info;

-- 6.5 Lag de punta a punta, medido sobre los propios datos:
--     cuanto tarda un evento desde que ocurre hasta que es consultable.
SELECT
    COUNT(*)                             AS eventos,
    MIN(latencia_ingesta_seg)            AS lag_min_seg,
    ROUND(AVG(latencia_ingesta_seg), 2)  AS lag_promedio_seg,
    MAX(latencia_ingesta_seg)            AS lag_max_seg,
    MAX(approximate_arrival_timestamp)   AS ultimo_evento_recibido
FROM v_clicks_tipado;


-- =============================================================================
-- BLOQUE 7 | LIMPIEZA (ejecutar al finalizar la demostracion)
-- =============================================================================

-- Detiene el consumo de RPU por refrescos automaticos.
-- ALTER MATERIALIZED VIEW mv_clicks_stream_raw AUTO REFRESH NO;

-- DROP VIEW IF EXISTS v_clicks_hot_vs_cold;
-- DROP VIEW IF EXISTS v_clicks_por_minuto;
-- DROP VIEW IF EXISTS v_clicks_cuarentena;
-- DROP VIEW IF EXISTS v_clicks_tipado;
-- DROP MATERIALIZED VIEW IF EXISTS mv_clicks_stream_raw;
-- DROP SCHEMA IF EXISTS ext_lakehouse;
-- DROP SCHEMA IF EXISTS ext_kinesis;
-- DROP USER IF EXISTS analyst_user;
-- DROP ROLE IF EXISTS analytics_reader;

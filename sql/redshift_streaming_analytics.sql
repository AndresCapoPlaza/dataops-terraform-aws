-- =============================================================================
-- PROYECTO FINAL | Analitica in-stream con Amazon Redshift Serverless
-- Autor:    Andres Capo Plaza
-- Repo:     github.com/AndresCapoPlaza/dataops-terraform-aws
--
-- ARQUITECTURA
--   Kinesis Data Stream (clicks-ecommerce)
--        |-- Redshift Streaming Ingestion --> datos CALIENTES  (latencia 2-3 s)
--        |-- Flink --> Iceberg / Glue ------> datos HISTORICOS (Lakehouse)
--                                   ambos consultables en la misma sesion SQL
--
-- CONVENCIONES DE NOMBRADO
--   ext_*  esquemas externos (fuentes que viven fuera de Redshift)
--   mv_*   vistas materializadas
--   v_*    vistas logicas
--   chk_*  consultas de verificacion (no crean objetos)
--
-- =============================================================================
-- ORDEN DE EJECUCION  (probado de arriba a abajo en una sesion limpia)
-- =============================================================================
--   PASO  BLOQUE  QUE HACE                                     CREA / DEVUELVE
--   ----  ------  -------------------------------------------  -----------------
--    1     0.1    Verifica el rol IAM y la conectividad        (solo lectura)
--    2     0.2    Verifica que el catalogo de Glue responde    (solo lectura)
--    3     1.1    Esquema externo sobre Kinesis                ext_kinesis
--    4     1.2    Vista materializada de ingesta, ya TIPADA    mv_clicks_stream_raw
--    5     1.3    Primera carga                                (refresh)
--    6     1.4    CHECK: hay filas y ninguna en cuarentena     (solo lectura)
--    7     2.1    Vista de servicio sobre registros validos    v_clicks_tipado
--    8     2.2    Vista de cuarentena                          v_clicks_cuarentena
--    9     2.3    Agregacion por minuto                        v_clicks_por_minuto
--   10     3.1    Esquema externo sobre Glue Data Catalog      ext_lakehouse
--   11     3.2    CHECK: la tabla Iceberg es visible y tiene   (solo lectura)
--                 filas ANTES de intentar la federada
--   12     3.3    Vista federada caliente + frio               v_clicks_hot_vs_cold
--   13     3.4    Resultado de la consulta federada            (solo lectura)
--   14     4.1    Rol de analitica y permisos                  analytics_reader
--   15     4.2    Usuario con autenticacion IAM                analyst_user
--   16     4.3    PRUEBA DE ACCESO PERMITIDO                   (solo lectura)
--   17     4.4    PRUEBA DE ACCESO DENEGADO                    (error esperado)
--   18     5      Estrategia y mecanismo de refresco           (documentacion)
--   19     6      Monitoreo de ingesta, lag y frescura         (solo lectura)
--   20     7      Limpieza                                     (comentado)
--
-- REQUISITOS PREVIOS
--   * Terraform aplicado: `terraform -chdir=terraform/environments/dev apply`
--   * El ARN del rol sale del output, no se escribe a mano:
--       terraform -chdir=terraform/environments/dev output -raw redshift_iam_role_arn
--     En este script figura el valor concreto del entorno de la evidencia.
--     Si se reproduce en otra cuenta, sustituir las 2 apariciones del ARN.
-- =============================================================================


-- #############################################################################
-- BLOQUE 0 | CHECKS PREVIOS
--
-- Se ejecutan ANTES de crear nada. Si alguno falla, el problema es de
-- infraestructura o de permisos, no del SQL, y conviene detenerse aca en vez
-- de perseguir errores mas adelante.
-- #############################################################################

-- 0.1 (PASO 1) Identidad y contexto de la sesion.
--     Confirma contra que namespace, base y usuario se esta trabajando.
SELECT
    current_user                AS usuario_conectado,
    current_database()          AS base_de_datos,
    current_schema()            AS esquema_por_defecto,
    GETDATE()                   AS hora_utc_del_cluster;


-- 0.2 (PASO 2) El catalogo de Glue responde y la tabla Iceberg existe.
--     Esta consulta NO depende todavia de ext_lakehouse: interroga el catalogo
--     de esquemas externos de Redshift. Si devuelve cero filas al final del
--     script, el esquema externo no se creo correctamente.
SELECT
    schemaname,
    tablename
FROM svv_external_tables
WHERE schemaname = 'ext_lakehouse'
ORDER BY tablename;
-- Resultado esperado en la primera pasada: 0 filas (aun no existe el esquema).
-- Se vuelve a ejecutar en el PASO 11, donde ya debe listar clicks_by_product.


-- #############################################################################
-- BLOQUE 1 | INGESTA DIRECTA DESDE KINESIS (Streaming Ingestion)
-- #############################################################################

-- 1.1 (PASO 3) Esquema externo que puentea Kinesis con Redshift.
--
--     No hay S3 intermedio: Redshift lee los shards directamente, lo que baja
--     la latencia de minutos (ruta Firehose -> S3 -> COPY) a segundos.
--     La autenticacion es por rol IAM asumido por el servicio: no hay
--     credenciales embebidas en la sentencia.
CREATE EXTERNAL SCHEMA IF NOT EXISTS ext_kinesis
FROM KINESIS
IAM_ROLE 'arn:aws:iam::010798385513:role/redshift-serverless-dev';


-- 1.2 (PASO 4) Vista materializada de ingesta, CON PARSEO TIPADO.
--
--     ---------------------------------------------------------------------
--     DECISION DE DISENO: tipado dentro de la MV, pero con guarda
--     ---------------------------------------------------------------------
--     La MV extrae y castea CINCO campos del JSON a tipos nativos de Redshift
--     (event_id, user_id, event_type, product_id y event_timestamp), de modo
--     que el modelado ocurre en la capa de ingesta y no se difiere a una vista
--     posterior.
--
--     Cada extraccion esta envuelta en un CASE que solo castea si el registro
--     es JSON valido. Con eso se obtienen las dos propiedades a la vez:
--
--       (a) Tipos nativos disponibles ya en la MV, sin casteos repetidos en
--           cada consulta y sin comillas residuales.
--       (b) Resistencia a "schema drift": si el productor cambia la estructura
--           del JSON o emite un registro corrupto, la ingesta NO se rompe.
--           El registro entra igual, sus columnas tipadas quedan en NULL, la
--           bandera es_json_valido lo marca y el payload crudo se conserva
--           para inspeccion en v_clicks_cuarentena (2.2).
--
--     Sin esa guarda, un unico registro malformado abortaria el REFRESH
--     completo y detendria la ingesta de TODO el stream.
--
--     El casteo de event_timestamp lleva ademas una verificacion de forma con
--     expresion regular: un JSON puede ser sintacticamente valido y aun asi
--     traer basura en el campo de fecha, y un cast fallido tiene el mismo
--     efecto destructivo que un JSON roto.
--
--     Se repite la expresion FROM_VARBYTE(...) en cada columna a proposito:
--     una MV de streaming ingestion no admite subconsultas ni CTE, por lo que
--     no hay forma de aliasar el payload una sola vez.
--
--     ---------------------------------------------------------------------
--     ORDEN OBLIGATORIO DE LAS CLAUSULAS
--     ---------------------------------------------------------------------
--     CREATE MATERIALIZED VIEW <nombre>
--         [ DISTSTYLE ... ] [ SORTKEY ( ... ) ]   <- atributos de tabla
--         [ AUTO REFRESH { YES | NO } ]           <- despues de los atributos
--         AS <query>                              <- siempre al final
--     Invertir el orden (por ejemplo poner AUTO REFRESH antes de SORTKEY)
--     produce un error de sintaxis.
--
--     SORTKEY sobre approximate_arrival_timestamp: es la columna por la que se
--     filtra y ordena en practicamente todas las consultas de frescura y lag
--     (bloque 6), de modo que Redshift puede descartar bloques completos.
--
--     AUTO REFRESH NO: el refresco se gobierna de forma explicita. El
--     mecanismo operativo esta definido en el BLOQUE 5.
CREATE MATERIALIZED VIEW mv_clicks_stream_raw
DISTSTYLE EVEN
SORTKEY (approximate_arrival_timestamp)
AUTO REFRESH NO
AS
SELECT
    -- ---------- metadatos que aporta Kinesis en cada registro ----------
    kinesis.approximate_arrival_timestamp,
    kinesis.shard_id,
    kinesis.sequence_number,
    kinesis.partition_key,
    kinesis.refresh_time,

    -- ---------- bandera de validez (permite detectar drift) ----------
    CAN_JSON_PARSE(FROM_VARBYTE(kinesis.kinesis_data, 'utf-8')) AS es_json_valido,

    -- ---------- campos del evento, TIPADOS ----------
    CASE WHEN CAN_JSON_PARSE(FROM_VARBYTE(kinesis.kinesis_data, 'utf-8'))
         THEN json_extract_path_text(
                  FROM_VARBYTE(kinesis.kinesis_data, 'utf-8'), 'event_id')
    END::VARCHAR(64)                                            AS event_id,

    CASE WHEN CAN_JSON_PARSE(FROM_VARBYTE(kinesis.kinesis_data, 'utf-8'))
         THEN json_extract_path_text(
                  FROM_VARBYTE(kinesis.kinesis_data, 'utf-8'), 'user_id')
    END::VARCHAR(64)                                            AS user_id,

    CASE WHEN CAN_JSON_PARSE(FROM_VARBYTE(kinesis.kinesis_data, 'utf-8'))
         THEN json_extract_path_text(
                  FROM_VARBYTE(kinesis.kinesis_data, 'utf-8'), 'event_type')
    END::VARCHAR(32)                                            AS event_type,

    CASE WHEN CAN_JSON_PARSE(FROM_VARBYTE(kinesis.kinesis_data, 'utf-8'))
         THEN json_extract_path_text(
                  FROM_VARBYTE(kinesis.kinesis_data, 'utf-8'), 'product_id')
    END::VARCHAR(64)                                            AS product_id,

    -- event_time: doble guarda -- JSON valido Y fecha con forma ISO 8601.
    -- Se castea a TIMESTAMP (sin zona) para que DATEDIFF pueda compararlo con
    -- approximate_arrival_timestamp, que Kinesis entrega tambien sin zona.
    -- Ambos valores estan en UTC.
    CASE WHEN CAN_JSON_PARSE(FROM_VARBYTE(kinesis.kinesis_data, 'utf-8'))
          AND json_extract_path_text(
                  FROM_VARBYTE(kinesis.kinesis_data, 'utf-8'), 'timestamp')
              ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}'
         THEN json_extract_path_text(
                  FROM_VARBYTE(kinesis.kinesis_data, 'utf-8'), 'timestamp')::TIMESTAMP
    END                                                         AS event_timestamp,

    -- ---------- payload crudo, para auditar lo que no parsea ----------
    FROM_VARBYTE(kinesis.kinesis_data, 'utf-8')                 AS payload_texto
FROM ext_kinesis."clicks-ecommerce" AS kinesis;
-- Nota sobre el nombre entre comillas: el stream se llama "clicks-ecommerce"
-- y el guion obliga a usar identificador delimitado. No es un espacio ni un
-- error de transcripcion.


-- 1.3 (PASO 5) Primera carga.
REFRESH MATERIALIZED VIEW mv_clicks_stream_raw;


-- 1.4 (PASO 6) CHECK de ingesta.
--     Debe devolver total > 0 y, en condiciones normales, invalidos = 0.
--     Si total = 0: el productor no esta emitiendo, o el rol IAM no puede leer
--     el stream. Si invalidos > 0: revisar v_clicks_cuarentena (2.2).
SELECT
    COUNT(*)                                            AS total_registros,
    SUM(CASE WHEN es_json_valido THEN 1 ELSE 0 END)     AS validos,
    SUM(CASE WHEN es_json_valido THEN 0 ELSE 1 END)     AS invalidos,
    SUM(CASE WHEN event_timestamp IS NULL THEN 1 ELSE 0 END)
                                                        AS sin_fecha_parseable,
    COUNT(DISTINCT shard_id)                            AS shards_leidos,
    MIN(approximate_arrival_timestamp)                  AS primer_evento,
    MAX(approximate_arrival_timestamp)                  AS ultimo_evento
FROM mv_clicks_stream_raw;


-- #############################################################################
-- BLOQUE 2 | VISTAS DE SERVICIO
--
-- El tipado ya ocurrio en la MV (1.2). Estas vistas no castean nada: solo
-- separan responsabilidades y agregan la metrica de latencia.
-- #############################################################################

-- 2.1 (PASO 7) Vista de servicio sobre los registros validos.
--     Es la unica superficie que consume el rol de analitica (bloque 4).
CREATE OR REPLACE VIEW v_clicks_tipado AS
SELECT
    event_id,
    user_id,
    event_type,
    product_id,
    event_timestamp,                    -- event time (cuando ocurrio)
    approximate_arrival_timestamp,      -- processing time (cuando llego)

    -- Latencia real de la ruta productor -> stream, en segundos.
    DATEDIFF(second, event_timestamp, approximate_arrival_timestamp)
                                        AS latencia_ingesta_seg,
    shard_id,
    sequence_number
FROM mv_clicks_stream_raw
WHERE es_json_valido = TRUE
  AND event_timestamp IS NOT NULL;      -- los no parseables van a cuarentena


-- 2.2 (PASO 8) Cuarentena: lo que no se pudo tipar.
--     Consultar esta vista de forma periodica es la manera de detectar schema
--     drift a tiempo, antes de que alguien note numeros raros en un tablero.
CREATE OR REPLACE VIEW v_clicks_cuarentena AS
SELECT
    approximate_arrival_timestamp,
    shard_id,
    sequence_number,
    es_json_valido,
    CASE
        WHEN NOT es_json_valido           THEN 'JSON no parseable'
        WHEN event_timestamp IS NULL      THEN 'timestamp con formato invalido'
        ELSE                                   'otro'
    END                                 AS motivo,
    payload_texto
FROM mv_clicks_stream_raw
WHERE es_json_valido = FALSE
   OR event_timestamp IS NULL;


-- 2.3 (PASO 9) Agregacion en tiempo real: clicks por producto y por minuto.
--     Equivale a la ventana TUMBLE de 1 minuto que calcula Flink, pero
--     resuelta en el momento de la consulta sobre los datos calientes.
CREATE OR REPLACE VIEW v_clicks_por_minuto AS
SELECT
    product_id,
    DATE_TRUNC('minute', event_timestamp)       AS ventana_minuto,
    COUNT(*)                                    AS clicks,
    COUNT(DISTINCT user_id)                     AS usuarios_unicos,
    ROUND(AVG(latencia_ingesta_seg), 2)         AS latencia_media_seg
FROM v_clicks_tipado
GROUP BY 1, 2;


-- #############################################################################
-- BLOQUE 3 | INTEGRACION CON EL LAKEHOUSE (Iceberg via Glue Data Catalog)
-- #############################################################################

-- 3.1 (PASO 10) Esquema externo apuntando al Glue Data Catalog.
--      Redshift Spectrum lee las tablas Iceberg tomando sus metadatos de Glue
--      y sus archivos Parquet de S3, sin copiar ni mover datos. Es el mismo
--      catalogo que consulta Athena.
CREATE EXTERNAL SCHEMA IF NOT EXISTS ext_lakehouse
FROM DATA CATALOG
DATABASE 'lakehouse_db'
IAM_ROLE 'arn:aws:iam::010798385513:role/redshift-serverless-dev'
REGION 'us-east-1';


-- 3.2 (PASO 11) CHECKS previos a la consulta federada.
--      La federada cruza dos motores de almacenamiento. Si devuelve resultados
--      vacios o raros, hay que poder decir CUAL de los dos lados fallo. Estas
--      dos consultas lo dejan establecido antes de unirlos.

-- 3.2.a  El catalogo responde y la tabla Iceberg esta registrada.
SELECT
    schemaname,
    tablename,
    location
FROM svv_external_tables
WHERE schemaname = 'ext_lakehouse';
-- Esperado: 1 fila -> clicks_by_product, apuntando al prefijo del lakehouse.

-- 3.2.b  La tabla Iceberg tiene filas y ventanas cerradas por Flink.
SELECT
    COUNT(*)              AS filas_en_iceberg,
    COUNT(DISTINCT product_id) AS productos,
    MIN(window_end)       AS primera_ventana,
    MAX(window_end)       AS ultima_ventana,
    SUM(click_count)      AS clicks_totales
FROM ext_lakehouse.clicks_by_product;
-- Esperado: filas_en_iceberg > 0. Si da 0, el job de Flink no commiteo:
-- el problema esta en el lado frio, no en Redshift.


-- 3.3 (PASO 12) CONSULTA FEDERADA: datos calientes + historicos en una query.
--
--      Este es el objetivo central: el stream aporta lo que esta pasando ahora
--      (2-3 s de latencia) y el Lakehouse aporta el historico consolidado por
--      Flink. Ambos conviven en la misma sesion SQL.
CREATE OR REPLACE VIEW v_clicks_hot_vs_cold AS
WITH caliente AS (
    -- Ultimos 15 minutos, directo del stream.
    SELECT
        product_id,
        COUNT(*) AS clicks_ahora
    -- WITH NO SCHEMA BINDING exige que TODAS las relaciones esten calificadas
    -- con su esquema, tambien las locales. Sin el prefijo "public." Redshift
    -- rechaza la creacion con:
    --   ERROR: All the relation names inside should be qualified when
    --          creating VIEW WITH NO SCHEMA BINDING
    FROM public.v_clicks_tipado
    WHERE event_timestamp >= DATEADD(minute, -15, GETDATE())
    GROUP BY product_id
),
historico AS (
    -- Consolidado por Flink en la tabla Iceberg.
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
    -- Indice de tendencia: actividad reciente contra el acumulado historico.
    CASE
        WHEN COALESCE(h.clicks_historicos, 0) = 0 THEN NULL
        ELSE ROUND(
            COALESCE(c.clicks_ahora, 0)::DECIMAL(12, 4)
            / NULLIF(h.clicks_historicos, 0) * 100, 2
        )
    END                                           AS pct_sobre_historico
FROM caliente c
FULL OUTER JOIN historico h ON c.product_id = h.product_id
-- Obligatorio: una vista que referencia tablas externas debe ser late-binding.
-- Redshift valida dependencias al crear la vista, pero los metadatos de un
-- esquema externo viven en Glue y evolucionan de forma independiente.
WITH NO SCHEMA BINDING;


-- 3.4 (PASO 13) Resultado de la consulta federada.
SELECT * FROM v_clicks_hot_vs_cold ORDER BY clicks_ultimos_15_min DESC;


-- #############################################################################
-- BLOQUE 4 | SEGURIDAD: rol de analitica con privilegios acotados
-- #############################################################################

-- 4.1 (PASO 14) Rol especifico de analitica (RBAC nativo de Redshift).
CREATE ROLE analytics_reader;

-- Permisos estrictamente de lectura sobre las capas modeladas.
GRANT USAGE ON SCHEMA public        TO ROLE analytics_reader;
GRANT USAGE ON SCHEMA ext_lakehouse TO ROLE analytics_reader;

GRANT SELECT ON v_clicks_tipado        TO ROLE analytics_reader;
GRANT SELECT ON v_clicks_por_minuto    TO ROLE analytics_reader;
GRANT SELECT ON v_clicks_hot_vs_cold   TO ROLE analytics_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA ext_lakehouse TO ROLE analytics_reader;

-- DECISION DELIBERADA: el esquema de ingesta queda FUERA del rol.
--   * NO se otorga USAGE sobre ext_kinesis  -> no puede leer la fuente cruda.
--   * NO se otorga SELECT sobre mv_clicks_stream_raw -> no accede al payload
--     sin procesar ni a los registros en cuarentena.
-- Un analista consulta el modelo; la fuente del stream es superficie de
-- operacion, no de analitica. El PASO 17 lo demuestra ejecutandolo.


-- 4.2 (PASO 15) Usuario de analitica con autenticacion IAM.
--      PASSWORD DISABLE fuerza el acceso federado: no existe contrasena que
--      robar ni rotar, la identidad la valida IAM. La politica que habilita la
--      obtencion de credenciales temporales esta declarada en Terraform
--      (modules/redshift/main.tf, recurso aws_iam_policy.analyst_connect) y
--      solo permite redshift-serverless:GetCredentials sobre ESTE workgroup.
CREATE USER analyst_user PASSWORD DISABLE;
GRANT ROLE analytics_reader TO analyst_user;

-- Verificacion del otorgamiento.
SELECT * FROM svv_user_grants WHERE user_name = 'analyst_user';


-- 4.3 (PASO 16) PRUEBA DE ACCESO PERMITIDO.
--      Se adopta la identidad del usuario analitico dentro de la misma sesion.
SET SESSION AUTHORIZATION 'analyst_user';

SELECT current_user AS actuando_como;

-- Debe FUNCIONAR: la vista modelada esta concedida al rol.
SELECT COUNT(*) AS filas_visibles_para_el_analista
FROM public.v_clicks_tipado;

-- Debe FUNCIONAR: el lakehouse esta concedido al rol.
SELECT COUNT(*) AS filas_iceberg_visibles
FROM ext_lakehouse.clicks_by_product;


-- 4.4 (PASO 17) PRUEBA DE ACCESO DENEGADO.
--      Las tres sentencias siguientes DEBEN fallar. Un error aqui no es un
--      defecto del script: es la evidencia de que el menor privilegio se
--      aplica de verdad y no solo esta declarado.
--      Ejecutar UNA POR VEZ y capturar el mensaje de error.

-- (a) La fuente cruda del stream: sin USAGE sobre ext_kinesis.
--     Error esperado: permission denied for schema ext_kinesis
SELECT COUNT(*) FROM ext_kinesis."clicks-ecommerce";

-- (b) La vista materializada de ingesta: sin SELECT concedido.
--     Error esperado: permission denied for relation mv_clicks_stream_raw
SELECT COUNT(*) FROM public.mv_clicks_stream_raw;

-- (c) La cuarentena, que expone payloads crudos: sin SELECT concedido.
--     Error esperado: permission denied for relation v_clicks_cuarentena
SELECT COUNT(*) FROM public.v_clicks_cuarentena;

-- Volver a la identidad administrativa.
RESET SESSION AUTHORIZATION;
SELECT current_user AS identidad_restaurada;


-- #############################################################################
-- BLOQUE 5 | ESTRATEGIA Y MECANISMO DE REFRESCO
-- #############################################################################

-- ---------------------------------------------------------------------------
-- QUE HACE UN REFRESCO
-- ---------------------------------------------------------------------------
-- El refresco de una MV de streaming ingestion es INCREMENTAL: Redshift lee
-- solo los registros posteriores al ultimo sequence_number procesado por
-- shard. No reprocesa el historico. Esa posicion es la que reporta
-- sys_stream_scan_states (bloque 6.1).
--
-- ---------------------------------------------------------------------------
-- TRADE-OFF DE LATENCIA
-- ---------------------------------------------------------------------------
--   cada 1 s       -> latencia minima, pero el cluster queda saturado
--                     refrescando y el costo en RPU se dispara
--   cada 30-60 s   -> latencia aceptable para el negocio y consumo de RPU
--                     acotado
--   cada 15 min    -> el "tiempo real" deja de serlo
--
-- Para este caso de uso (ranking de productos por actividad reciente) una
-- latencia de 60 segundos es holgadamente suficiente: ninguna decision
-- comercial se toma con granularidad menor.
--
-- ---------------------------------------------------------------------------
-- MECANISMO OPERATIVO ADOPTADO: EventBridge Scheduler + Redshift Data API
-- ---------------------------------------------------------------------------
-- El refresco NO se deja librado a AUTO REFRESH. Motivo: AUTO REFRESH es
-- best-effort -- Redshift decide cuando refrescar segun la carga del cluster,
-- de modo que no se puede comprometer un objetivo de frescura ni auditar por
-- que un refresco no ocurrio.
--
-- En su lugar, Terraform despliega (modules/redshift/main.tf):
--
--   aws_scheduler_schedule.refresh_mv
--       schedule_expression = "rate(1 minute)"        <- los 60 s exactos
--       target: redshift-data:ExecuteStatement
--               Sql = "REFRESH MATERIALIZED VIEW mv_clicks_stream_raw;"
--               WorkgroupName / Database del output de Terraform
--       role:   rol dedicado que SOLO puede ejecutar redshift-data:
--               ExecuteStatement sobre este workgroup
--
--   aws_cloudwatch_metric_alarm.refresh_failed
--       namespace  = "AWS/Scheduler"
--       metric     = TargetErrorCount > 0
--       -> avisa si el refresco deja de ejecutarse
--
--   aws_cloudwatch_metric_alarm.shard_iterator_age  (una por shard)
--       namespace  = "AWS/Kinesis"
--       metric     = IteratorAgeMilliseconds, dimension ShardId
--       -> avisa si UN shard concreto se atrasa, aunque el promedio del
--          stream se vea sano. Requiere metricas de shard habilitadas:
--          shard_level_metrics en aws_kinesis_stream.
--
-- Ventaja de este esquema sobre AUTO REFRESH: el intervalo es deterministico,
-- esta versionado en el repositorio, y tanto el fallo del refresco como el
-- atraso por shard disparan una alarma en vez de pasar inadvertidos.

-- 5.1 Refresco manual (el usado en la demostracion, para controlar el momento
--     exacto y poder medirlo).
REFRESH MATERIALIZED VIEW mv_clicks_stream_raw;

-- 5.2 Alternativa gestionada por Redshift, si no se quiere infraestructura
--     adicional. Se deja documentada pero NO es la adoptada.
-- ALTER MATERIALIZED VIEW mv_clicks_stream_raw AUTO REFRESH YES;

-- 5.3 Volver a manual (recomendado al terminar la demo, para no consumir RPU).
-- ALTER MATERIALIZED VIEW mv_clicks_stream_raw AUTO REFRESH NO;


-- #############################################################################
-- BLOQUE 6 | MONITOREO DE INGESTA, LAG Y FRESCURA
-- #############################################################################

-- 6.1 (PASO 19) Estado del scan por fragmento: posicion, filas leidas, lag.
--
--     Se consulta con SELECT * a proposito: el catalogo de esta vista de
--     sistema varia entre versiones de Redshift. En el entorno utilizado NO
--     existe la columna "shard_id" -- el identificador de fragmento viaja en
--     "partition_id" -- y nombrar columnas explicitamente rompe el script con:
--        ERROR: column "shard_id" does not exist in sys_stream_scan_states
--     Columnas relevantes que devuelve: external_schema_name, stream_name,
--     mv_name, partition_id, latest_position, scanned_rows, skipped_rows,
--     scanned_bytes y las marcas de tiempo de lag.
--     Lo que hay que mirar: skipped_rows debe ser 0 en todos los fragmentos.
SELECT * FROM sys_stream_scan_states ORDER BY record_time DESC LIMIT 20;


-- 6.2 Errores de ingesta (registros descartados, problemas de permisos).
--     Debe devolver 0 filas.
SELECT * FROM sys_stream_scan_errors ORDER BY record_time DESC LIMIT 20;


-- 6.3 Historial de refrescos: duracion y estado de cada uno.
--     Sirve para verificar que el mecanismo del bloque 5 esta corriendo cada
--     60 segundos y cuanto tarda cada pasada.
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
--     SELECT * por el mismo motivo que 6.1: el catalogo de svv_mv_info
--     cambia entre versiones.
SELECT * FROM svv_mv_info;


-- 6.5 FRESCURA Y LAG DE PUNTA A PUNTA, medido sobre los propios datos:
--     cuanto tarda un evento desde que ocurre hasta que es consultable.
SELECT
    COUNT(*)                             AS eventos,
    MIN(latencia_ingesta_seg)            AS lag_min_seg,
    ROUND(AVG(latencia_ingesta_seg), 2)  AS lag_promedio_seg,
    MAX(latencia_ingesta_seg)            AS lag_max_seg,
    MAX(approximate_arrival_timestamp)   AS ultimo_evento_recibido,
    DATEDIFF(second, MAX(approximate_arrival_timestamp), GETDATE())
                                         AS antiguedad_del_dato_mas_nuevo_seg
FROM v_clicks_tipado;
-- antiguedad_del_dato_mas_nuevo_seg es la metrica de FRESCURA: si crece de
-- forma sostenida, el refresco dejo de ejecutarse o el consumidor se atraso.
-- Es la consulta que alimentaria una metrica personalizada de CloudWatch.


-- 6.6 Evidencia directa de la columna de llegada, por evento.
SELECT
    product_id,
    event_timestamp,
    approximate_arrival_timestamp,
    latencia_ingesta_seg
FROM v_clicks_tipado
ORDER BY approximate_arrival_timestamp DESC
LIMIT 15;


-- #############################################################################
-- BLOQUE 7 | LIMPIEZA (PASO 20 -- ejecutar al finalizar la demostracion)
-- #############################################################################

-- Detiene el consumo de RPU por refrescos automaticos, si se habian activado.
-- ALTER MATERIALIZED VIEW mv_clicks_stream_raw AUTO REFRESH NO;

-- Orden inverso al de creacion, por dependencias.
-- DROP VIEW IF EXISTS v_clicks_hot_vs_cold;
-- DROP VIEW IF EXISTS v_clicks_por_minuto;
-- DROP VIEW IF EXISTS v_clicks_cuarentena;
-- DROP VIEW IF EXISTS v_clicks_tipado;
-- DROP MATERIALIZED VIEW IF EXISTS mv_clicks_stream_raw;
-- DROP SCHEMA IF EXISTS ext_lakehouse;
-- DROP SCHEMA IF EXISTS ext_kinesis;
-- DROP USER IF EXISTS analyst_user;
-- DROP ROLE IF EXISTS analytics_reader;

-- Nota: el recurso que factura por hora es la infraestructura, no estos
-- objetos. La limpieza real es:
--   terraform -chdir=terraform/environments/dev destroy -auto-approve

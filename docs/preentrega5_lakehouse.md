# Pre-entrega 5 — Pipeline Lakehouse con Iceberg, Glue y Catálogo

## 1. Arquitectura

```
producer (boto3)  ──►  Kinesis Data Stream        clicks-ecommerce (2 shards)
                            │
                            ▼
                       Apache Flink 1.15  (PyFlink, Table API)
                            │   TUMBLE 1 min  •  GROUP BY product_id
                            │   checkpoint EXACTLY_ONCE cada 30 s
                            ▼
                       Apache Iceberg  (format-version 2, Parquet + zstd)
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
   S3  s3://<bucket>/lakehouse/     AWS Glue Data Catalog
   (data/ + metadata/)              lakehouse_db.clicks_by_product
                                            │
                                            ▼
                                       Amazon Athena
```

## 2. Infraestructura (Terraform)

| Recurso | Archivo | Rol |
|---|---|---|
| `aws_glue_catalog_database.lakehouse_db` | `environments/dev/modules/glue/main.tf` | Metastore central |
| `aws_iam_role_policy.flink_glue_access` | idem | `glue:GetTable`, `CreateTable`, `UpdateTable`, `GetPartitions`, `BatchCreatePartition` |
| `aws_iam_role_policy.flink_lakehouse_s3_access` | idem | `s3:GetObject/PutObject/DeleteObject/ListBucket` sobre el bucket del lakehouse |
| `aws_dynamodb_table.iceberg_glue_lock` | idem | Lock manager explícito para commits concurrentes |
| `aws_s3_bucket_versioning.raw_bucket_versioning` | `environments/dev/main.tf` | Versionado habilitado (recomendado para Iceberg) |

El `account_id` de las políticas se resuelve con `data.aws_caller_identity.current` — ya no está hardcodeado.

```bash
cd environments/dev
terraform init && terraform plan && terraform apply
```

## 3. Estrategia de particionado y *partition pruning*

**Partición elegida: `PARTITIONED BY (product_id)`.**

La tabla es una agregación por ventana (`product_id`, `window_end`, `click_count`). El patrón de consulta dominante del negocio es *"¿cómo evolucionan los clicks de un producto?"* — es decir, el filtro casi siempre incluye `product_id`.

Iceberg mantiene, en los archivos de manifiesto, el valor de partición y las estadísticas por columna (min/max, null counts) de cada archivo de datos. Cuando Athena ejecuta:

```sql
SELECT SUM(click_count) FROM lakehouse_db.clicks_by_product WHERE product_id = 'product-3';
```

el planner resuelve el filtro **contra los metadatos**, descarta las particiones que no aplican y sólo abre los Parquet de `data/product_id=product-3/`. Eso es *partition pruning*: se reduce el `DataScannedInBytes` — que es exactamente lo que Athena factura — sin tocar el resto de la tabla.

Consideraciones que justifican la elección frente a las alternativas:

- **Cardinalidad controlada.** El catálogo tiene ~10 productos en el escenario de prueba. Es la zona útil: suficiente selectividad para podar, sin caer en el *small files problem* que produciría particionar por algo de cardinalidad alta (`user_id`, `event_id`).
- **`window_end` no se particiona explícitamente.** Iceberg ya guarda min/max de `window_end` por archivo, así que un filtro temporal se resuelve por *file pruning* con estadísticas, sin necesidad de una segunda dimensión de partición. Si el volumen creciera, la evolución natural sería `PARTITIONED BY (product_id, days(window_end))` — y una ventaja clave de Iceberg es que ese cambio se hace con **partition evolution**, sin reescribir los datos históricos ni romper las consultas existentes (a diferencia de Hive).
- **Alineado con el paralelismo de escritura.** Con `product_id` como clave de agrupación en el `GROUP BY`, cada writer de Flink escribe en un set acotado de particiones por checkpoint, lo que mantiene bajo el número de archivos por commit.

## 4. Ejecución de la prueba de persistencia

> El `IcebergSink` confirma los manifiestos **sólo cuando Flink completa un checkpoint**. Si el job se corta antes del primer checkpoint completo, se ven (o no) archivos en S3 pero la tabla del catálogo aparece vacía.

**Terminal A — job de Flink** (arranca primero; el source usa `scan.stream.initpos = LATEST`):

```powershell
python flink\iceberg_processor.py
```

El job corre `RUN_SECONDS` (7 min por defecto) y se **auto-cancela de forma limpia**. No usar `Ctrl+C`: mata la JVM vía py4j (`WinError 10054`).

**Terminal B — productor continuo** (arrancar apenas aparezca el `JobID`):

```powershell
python producers\producer_kinesis_stream.py 360 5
```

Emisión sostenida de 5 ev/s durante 6 min. Es lo que mantiene el **watermark avanzando**: con event-time, una ventana `TUMBLE` sólo cierra cuando llega un evento posterior al fin de la ventana. Un productor de ráfaga que envía 100 eventos y muere congela el watermark y la última ventana nunca dispara.

**Terminal C — verificación:**

```powershell
.\scripts\verify_iceberg.ps1
```

## 5. Evidencia esperada

| Check | Resultado esperado |
|---|---|
| `Table.Parameters.metadata_location` en Glue | avanza de `00000-*.metadata.json` a `00001-*`, `00002-*`… (un metadata nuevo por commit) |
| `s3://…/clicks_by_product/data/` | carpetas `product_id=product-N/` con archivos `.parquet` |
| `s3://…/clicks_by_product/metadata/` | `*.metadata.json`, `snap-*.avro` (snapshots) y manifiestos `*.avro` |
| Athena `SELECT *` | filas con `product_id`, `window_end`, `click_count` |
| Athena con `WHERE product_id = …` | `DataScannedInBytes` sensiblemente menor que el escaneo completo |

Capturas a incluir en el README: consola de AWS Glue → Data Catalog → Tables → `clicks_by_product` (mostrando `table_type = ICEBERG` y el `metadata_location`), y el resultado de la consulta en Athena.

## 6. Concurrencia

`GlueCatalog` de Iceberg implementa *optimistic concurrency control* nativo: cada commit hace un `UpdateTable` condicionado al `VersionId` actual de la tabla en Glue; si otro writer commiteó en el medio, el commit se reintenta sobre el nuevo snapshot en vez de sobrescribirlo. Sobre esa base se añadió `aws_dynamodb_table.iceberg_glue_lock` como lock manager explícito para escenarios multi-writer; se activa con:

```powershell
$env:USE_DYNAMO_LOCK = "1"
python flink\iceberg_processor.py
```

que agrega al catálogo las propiedades `lock-impl = org.apache.iceberg.aws.dynamodb.DynamoDbLockManager` y `lock.table = iceberg_glue_lock`.

## 7. Compatibilidad de dependencias y troubleshooting

| Componente | Versión |
|---|---|
| Flink / PyFlink | 1.15.4 |
| `flink-sql-connector-kinesis` | 1.15.4 |
| `iceberg-flink-runtime-1.15` | 1.4.2 |
| `iceberg-aws-bundle` | 1.4.2 |
| `hadoop-client-api` / `-runtime` | 3.3.4 |

### 7.1 `LinkageError` de Dropwizard Metrics — el bloqueante real

Durante la puesta en marcha, el job escribía correctamente los Parquet en S3 pero
**la tabla del catálogo quedaba siempre vacía**. El síntoma era engañoso:

- `data/` se llenaba de archivos Parquet válidos.
- `metadata/` sólo tenía el `00000-*.metadata.json` de la creación de la tabla.
- Athena devolvía la tabla con esquema correcto y cero filas.
- Los checkpoints figuraban como *completed* mientras no hubiera datos.

La causa raíz apareció recién al capturar la excepción con `TableResult.wait()`
en un hilo de vigilancia (los logs del MiniCluster no la mostraban):

```
java.lang.LinkageError: loader constraint violation:
loader 'app' wants to load class com.codahale.metrics.Histogram.
A different class with the same name was previously loaded by ChildFirstClassLoader
  at org.apache.flink.dropwizard.metrics.DropwizardHistogramWrapper.update
  at org.apache.iceberg.flink.sink.IcebergStreamWriterMetrics.updateFlushResult
  at org.apache.iceberg.flink.sink.IcebergStreamWriter.flush
  at IcebergStreamWriter.prepareSnapshotPreBarrier
```

`iceberg-flink-runtime` trae **bundleado** `com.codahale.metrics`, y PyFlink ya
expone `flink-metrics-dropwizard` en su classpath de sistema. La misma clase queda
cargada por dos classloaders distintos y la JVM rechaza la operación cuando el
writer de Iceberg registra las métricas del flush.

El fallo ocurre en `prepareSnapshotPreBarrier`, es decir **sólo cuando hay datos
reales que escribir** — por eso las corridas sin tráfico completaban checkpoints
sin problema y el error parecía intermitente. Con la estrategia de reinicio por
defecto, el job moría y revivía en bucle, dejando decenas de *orphan files*
(Parquet válidos que ningún snapshot referencia).

**Solución** — forzar resolución *parent-first* para esos paquetes, de modo que
ambos componentes usen la misma clase:

```python
conf.set_string(
    "classloader.parent-first-patterns.additional",
    "com.codahale.metrics;org.apache.flink.dropwizard",
)
```

Es un caso de libro del error común "mismatch de versiones de dependencias": no se
manifiesta como un fallo de resolución en tiempo de build, sino como una
`LinkageError` en runtime dentro del sink.

### 7.2 Lecciones operativas

| Síntoma | Causa | Qué hacer |
|---|---|---|
| Parquet en `data/` pero `metadata/` sin `.avro` | El checkpoint dispara la fase de snapshot (que cierra y sube los archivos) pero nunca completa → `IcebergFilesCommitter` no commitea | Capturar la excepción con `TableResult.wait()`; los logs del MiniCluster no la muestran |
| El job "se cuelga" sin errores | `restart-strategy` por defecto reinicia en silencio | `restart-strategy: none` durante el diagnóstico |
| La última ventana nunca aparece | Con event-time, `TUMBLE` cierra sólo al llegar un evento posterior al fin de ventana | Productor con emisión continua, no ráfagas |
| No se ve la salida en consola | Python pasa a *block buffering* al redirigir por pipe | `python -u` |
| Athena devuelve 0 filas con archivos presentes | Se borró `data/` dejando vivo el metadata: el snapshot apunta a archivos inexistentes | Borrar la tabla completa (Glue + prefijo S3), nunca sólo `data/` |

> En Windows, el warning `Did not find winutils.exe` es esperado y no bloquea:
> Iceberg escribe vía `S3FileIO` (SDK de AWS), no vía Hadoop FileSystem.

## 8. Resultado verificado

Corrida del 2026-09-08, 23:31–23:38 (7 min, ~5 eventos/s):

- **5 commits** en el catálogo: `metadata_location` avanzó de `00000-*` a `00005-*`.
- **5 snapshots** (`snap-*.avro`) y 5 manifiestos (`*-m0.avro`).
- **50 archivos Parquet** distribuidos en las 10 particiones `product_id=product-N/`.
- Athena devuelve las ventanas de un minuto con ~17 clicks por producto.
- Filtro `WHERE product_id = 'product-3'`: **230 bytes escaneados** gracias al
  partition pruning, frente al escaneo del total de particiones.

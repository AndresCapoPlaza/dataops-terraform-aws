"""
Pre-entrega 5 - Capa de Almacenamiento y Catalogo (Lakehouse)
Kinesis -> Flink (ventana de 1 min) -> Iceberg (S3) -> AWS Glue Data Catalog

Puntos criticos de esta version:
  * El sink de Iceberg SOLO hace commit de metadatos cuando Flink COMPLETA un
    checkpoint. Por eso el checkpointing esta configurado de forma explicita y
    con tolerable_checkpoint_failure_number(0): si un checkpoint falla, el job
    muere con la excepcion visible en vez de fallar en silencio.
  * El job corre RUN_SECONDS y se cancela de forma limpia desde el JobClient.
    Nunca cortar con Ctrl+C: eso mata la JVM via py4j (WinError 10054) y puede
    dejar el ultimo checkpoint a medias.
"""

import json
import os
import subprocess
import sys
import threading
import time
import traceback
import urllib.request

from pyflink.common import Configuration
from pyflink.datastream import StreamExecutionEnvironment, CheckpointingMode
from pyflink.table import StreamTableEnvironment, EnvironmentSettings

# ---------------------------------------------------------------- parametros
BUCKET_NAME = "datalake-raw-dev-123456789012"
REGION = "us-east-1"
GLUE_DATABASE = "lakehouse_db"
ICEBERG_TABLE = "clicks_by_product"
KINESIS_STREAM = "clicks-ecommerce"

CHECKPOINT_INTERVAL_MS = 30_000      # commit de Iceberg cada 30 s
WINDOW = "1"                         # minutos de la ventana TUMBLE
RUN_SECONDS = int(os.getenv("RUN_SECONDS", "420"))  # 7 min por defecto
REST_PORT = 8081

# El script lanza el producer solo, justo despues de enviar el job.
# Asi no hay que coordinar dos terminales a mano.
AUTO_PRODUCER = os.getenv("AUTO_PRODUCER", "1") == "1"
PRODUCER_SECONDS = int(os.getenv("PRODUCER_SECONDS", "330"))
PRODUCER_RATE = os.getenv("PRODUCER_RATE", "5")

# Lock manager externo (DynamoDB). Solo activar si ya aplicaste el modulo glue
# de Terraform que crea la tabla iceberg_glue_lock.
USE_DYNAMO_LOCK = os.getenv("USE_DYNAMO_LOCK", "0") == "1"
DYNAMO_LOCK_TABLE = "iceberg_glue_lock"

BASE = "file:///C:/Users/Usuario/Desktop/Nueva%20carpeta/.data11/mi-proyecto-dataops/app/flink"
JARS = [
    f"{BASE}/lib/flink-sql-connector-kinesis-1.15.4.jar",
    f"{BASE}/lib_iceberg/iceberg-flink-runtime-1.15-1.4.2.jar",
    f"{BASE}/lib_iceberg/iceberg-aws-bundle-1.4.2.jar",
    f"{BASE}/lib_iceberg/hadoop-client-api-3.3.4.jar",
    f"{BASE}/lib_iceberg/hadoop-client-runtime-3.3.4.jar",
]


def build_env() -> StreamExecutionEnvironment:
    conf = Configuration()
    conf.set_string("pipeline.name", "clicks-to-iceberg")
    # Web UI local -> http://localhost:8081 (pestana Checkpoints)
    conf.set_string("rest.port", str(REST_PORT))
    # Sin reintentos silenciosos: si algo falla, se ve
    conf.set_string("restart-strategy", "none")

    # --- FIX CRITICO: conflicto de classloaders con Dropwizard Metrics ---
    # iceberg-flink-runtime trae bundleado com.codahale.metrics, y PyFlink ya
    # tiene flink-metrics-dropwizard en su classpath. Al cargarse la misma clase
    # por dos classloaders distintos, IcebergStreamWriter.flush() explota con
    # java.lang.LinkageError: loader constraint violation, y el job muere en el
    # primer checkpoint que tenga datos reales que escribir.
    # Forzar parent-first para esos paquetes hace que ambos usen la misma clase.
    conf.set_string(
        "classloader.parent-first-patterns.additional",
        "com.codahale.metrics;org.apache.flink.dropwizard",
    )

    env = StreamExecutionEnvironment.get_execution_environment(conf)
    env.set_parallelism(1)
    env.add_jars(*JARS)

    # ---- checkpointing explicito: sin esto Iceberg NUNCA commitea ----
    env.enable_checkpointing(CHECKPOINT_INTERVAL_MS, CheckpointingMode.EXACTLY_ONCE)
    cc = env.get_checkpoint_config()
    cc.set_min_pause_between_checkpoints(5_000)
    cc.set_checkpoint_timeout(180_000)
    cc.set_max_concurrent_checkpoints(1)
    cc.set_tolerable_checkpoint_failure_number(0)   # falla ruidosa, no silenciosa
    return env


def catalog_props() -> str:
    props = [
        "'type' = 'iceberg'",
        "'catalog-impl' = 'org.apache.iceberg.aws.glue.GlueCatalog'",
        f"'warehouse' = 's3://{BUCKET_NAME}/lakehouse/'",
        "'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO'",
        f"'glue.region' = '{REGION}'",
        f"'client.region' = '{REGION}'",
    ]
    if USE_DYNAMO_LOCK:
        props += [
            "'lock-impl' = 'org.apache.iceberg.aws.dynamodb.DynamoDbLockManager'",
            f"'lock.table' = '{DYNAMO_LOCK_TABLE}'",
        ]
    return ",\n            ".join(props)


def report_checkpoints(job_id: str) -> None:
    """Lee el estado real de los checkpoints desde la REST API del minicluster."""
    url = f"http://localhost:{REST_PORT}/jobs/{job_id}/checkpoints"
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            data = json.loads(r.read().decode("utf-8"))
    except Exception as e:
        print(f"    [ckpt] REST no disponible ({e.__class__.__name__}) - mira el Web UI en http://localhost:{REST_PORT}")
        return

    c = data.get("counts", {})
    print(f"    [ckpt] triggered={c.get('total')} in_progress={c.get('in_progress')} "
          f"completed={c.get('completed')} failed={c.get('failed')}")

    latest = data.get("latest") or {}
    failed = latest.get("failed")
    if failed:
        print(f"    [ckpt] ULTIMO FALLO id={failed.get('id')} causa={failed.get('failure_message')}")
    done = latest.get("completed")
    if done:
        print(f"    [ckpt] ultimo OK id={done.get('id')} duracion={done.get('end_to_end_duration')}ms "
              f"size={done.get('state_size')}b")


def main():
    env = build_env()
    settings = EnvironmentSettings.new_instance().in_streaming_mode().build()
    t_env = StreamTableEnvironment.create(env, environment_settings=settings)

    # Si un shard queda sin trafico, no bloquea el avance del watermark
    t_env.get_config().set("table.exec.source.idle-timeout", "15 s")

    # ------------------------------------------------------------ source
    t_env.execute_sql(f"""
        CREATE TABLE clicks_source (
            raw_json STRING,
            product_id AS JSON_VALUE(raw_json, '$.product_id'),
            event_time AS CAST(
                SUBSTRING(REPLACE(JSON_VALUE(raw_json, '$.timestamp'), 'T', ' '), 1, 23)
                AS TIMESTAMP(3)
            ),
            WATERMARK FOR event_time AS event_time - INTERVAL '10' SECOND
        ) WITH (
            'connector' = 'kinesis',
            'stream' = '{KINESIS_STREAM}',
            'aws.region' = '{REGION}',
            'scan.stream.initpos' = 'LATEST',
            'format' = 'raw'
        )
    """)

    # ------------------------------------------------- catalogo Glue/Iceberg
    t_env.execute_sql(f"""
        CREATE CATALOG glue_catalog WITH (
            {catalog_props()}
        )
    """)

    t_env.execute_sql(f"CREATE DATABASE IF NOT EXISTS glue_catalog.{GLUE_DATABASE}")

    # Particionado por product_id: es la clave de filtro dominante en las
    # consultas analiticas -> habilita partition pruning en Athena.
    t_env.execute_sql(f"""
        CREATE TABLE IF NOT EXISTS glue_catalog.{GLUE_DATABASE}.{ICEBERG_TABLE} (
            product_id STRING,
            window_end TIMESTAMP(3),
            click_count BIGINT
        ) PARTITIONED BY (product_id)
        WITH (
            'format-version' = '2',
            'write.format.default' = 'parquet',
            'write.parquet.compression-codec' = 'zstd',
            'write.metadata.delete-after-commit.enabled' = 'true',
            'write.metadata.previous-versions-max' = '20'
        )
    """)

    print(">>> Catalogo y tabla listos. Enviando job de streaming...")

    result = t_env.execute_sql(f"""
        INSERT INTO glue_catalog.{GLUE_DATABASE}.{ICEBERG_TABLE}
        SELECT
            product_id,
            TUMBLE_END(event_time, INTERVAL '{WINDOW}' MINUTE) AS window_end,
            COUNT(*) AS click_count
        FROM clicks_source
        GROUP BY TUMBLE(event_time, INTERVAL '{WINDOW}' MINUTE), product_id
    """)

    job_client = result.get_job_client()
    print(f">>> JobID: {job_client.get_job_id()}")
    print(f">>> Corriendo {RUN_SECONDS}s. Checkpoint cada {CHECKPOINT_INTERVAL_MS // 1000}s.")
    print(">>> NO cortes con Ctrl+C: el job se cancela solo al terminar.")

    job_id = str(job_client.get_job_id())

    # Vigila el job en segundo plano: result.wait() propaga la causa raiz real
    # si el job falla. Sin esto, el MiniCluster se apaga sin dejar rastro.
    job_end = {}

    def _await_job():
        try:
            result.wait()
            job_end["estado"] = "FINISHED"
            job_end["detalle"] = "El job termino por su cuenta (no deberia: es streaming)."
        except BaseException:
            job_end["estado"] = "FAILED"
            job_end["detalle"] = traceback.format_exc()

    threading.Thread(target=_await_job, daemon=True).start()

    producer = None
    if AUTO_PRODUCER:
        script = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                              "producers", "producer_kinesis_stream.py")
        print(f">>> Lanzando producer: {PRODUCER_SECONDS}s a {PRODUCER_RATE} ev/s")
        producer = subprocess.Popen(
            [sys.executable, "-u", script, str(PRODUCER_SECONDS), str(PRODUCER_RATE)],
            stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT,
        )

    deadline = time.time() + RUN_SECONDS
    while time.time() < deadline:
        time.sleep(20)
        if job_end:
            print("\n" + "=" * 70)
            print(f"!!! EL JOB TERMINO ANTES DE TIEMPO - estado: {job_end['estado']}")
            print("=" * 70)
            print(job_end["detalle"])
            print("=" * 70)
            break
        report_checkpoints(job_id)
        print(f"    ... quedan {int(deadline - time.time())}s")

    if producer is not None and producer.poll() is None:
        producer.terminate()

    print(">>> Cancelando job de forma limpia...")
    try:
        job_client.cancel().result()
        print(">>> Job cancelado. Los commits ya quedaron en el catalogo de Glue.")
    except Exception as e:
        print(f">>> El job ya no estaba activo ({e.__class__.__name__}).")

    if job_end:
        print(f">>> ATENCION: el job no llego al final. Estado: {job_end['estado']}")


if __name__ == "__main__":
    main()

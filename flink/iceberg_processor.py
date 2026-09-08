from pyflink.datastream import StreamExecutionEnvironment
from pyflink.table import StreamTableEnvironment, EnvironmentSettings


BUCKET_NAME = "datalake-raw-dev-123456789012"
REGION = "us-east-1"
GLUE_DATABASE = "lakehouse_db"
ICEBERG_TABLE = "clicks_by_product"
KINESIS_STREAM = "clicks-ecommerce"

JARS = [
    "file:///C:/Users/Usuario/Desktop/Nueva%20carpeta/.data11/mi-proyecto-dataops/flink/lib/flink-sql-connector-kinesis-1.15.4.jar",
    "file:///C:/Users/Usuario/Desktop/Nueva%20carpeta/.data11/mi-proyecto-dataops/flink/lib_iceberg/iceberg-flink-runtime-1.15-1.4.2.jar",
    "file:///C:/Users/Usuario/Desktop/Nueva%20carpeta/.data11/mi-proyecto-dataops/flink/lib_iceberg/iceberg-aws-bundle-1.4.2.jar",
    "file:///C:/Users/Usuario/Desktop/Nueva%20carpeta/.data11/mi-proyecto-dataops/flink/lib_iceberg/hadoop-client-api-3.3.4.jar",
    "file:///C:/Users/Usuario/Desktop/Nueva%20carpeta/.data11/mi-proyecto-dataops/flink/lib_iceberg/hadoop-client-runtime-3.3.4.jar",
]


def main():
    env = StreamExecutionEnvironment.get_execution_environment()
    env.set_parallelism(1)
    env.add_jars(*JARS)
    env.enable_checkpointing(30000)  # checkpoint cada 30 segundos

    settings = EnvironmentSettings.new_instance().in_streaming_mode().build()
    t_env = StreamTableEnvironment.create(env, environment_settings=settings)

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

    t_env.execute_sql(f"""
        CREATE CATALOG glue_catalog WITH (
            'type' = 'iceberg',
            'catalog-impl' = 'org.apache.iceberg.aws.glue.GlueCatalog',
            'warehouse' = 's3://{BUCKET_NAME}/lakehouse/',
            'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
            'glue.region' = '{REGION}'
        )
    """)

    t_env.execute_sql(f"CREATE DATABASE IF NOT EXISTS glue_catalog.{GLUE_DATABASE}")

    t_env.execute_sql(f"""
        CREATE TABLE IF NOT EXISTS glue_catalog.{GLUE_DATABASE}.{ICEBERG_TABLE} (
            product_id STRING,
            window_end TIMESTAMP(3),
            click_count BIGINT
        ) PARTITIONED BY (product_id)
    """)

    print(">>> Enviando job de streaming (INSERT INTO)...")

    result = t_env.execute_sql(f"""
        INSERT INTO glue_catalog.{GLUE_DATABASE}.{ICEBERG_TABLE}
        SELECT
            product_id,
            TUMBLE_END(event_time, INTERVAL '1' MINUTE) AS window_end,
            COUNT(*) AS click_count
        FROM clicks_source
        GROUP BY TUMBLE(event_time, INTERVAL '1' MINUTE), product_id
    """)

    print(">>> Job enviado. Esperando resultados (esto debe quedarse corriendo)...")
    result.wait()


if __name__ == "__main__":
    main()

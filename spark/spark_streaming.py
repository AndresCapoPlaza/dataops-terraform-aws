from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col,
    from_json,
    avg,
    window,
)
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    DoubleType,
    IntegerType,
    TimestampType,
)


KAFKA_BOOTSTRAP_SERVERS = "kafka:9092"
KAFKA_TOPIC = "urban_sensors"


spark = (
    SparkSession.builder
    .appName("urban-sensor-stream")
    .getOrCreate()
)

spark.sparkContext.setLogLevel("WARN")


schema = StructType([
    StructField("sensor_id", StringType(), False),
    StructField("temperature", DoubleType(), False),
    StructField("humidity", DoubleType(), False),
    StructField("air_quality_index", IntegerType(), False),
    StructField("timestamp", TimestampType(), False),
])


raw_stream = (
    spark.readStream
    .format("kafka")
    .option("kafka.bootstrap.servers", "kafka:9092")
    .option("subscribe", "urban_sensors")
    .option("startingOffsets", "earliest")
    .load()
)


sensor_data = (
    raw_stream
    .select(
        from_json(
            col("value").cast("string"),
            schema
        ).alias("data")
    )
    .select("data.*")
)


aggregated_data = (
    sensor_data
    .withWatermark("timestamp", "2 minutes")
    .groupBy(
        col("sensor_id"),
        window(col("timestamp"), "1 minute")
    )
    .agg(
        avg("temperature").alias("avg_temperature"),
        avg("air_quality_index").alias("avg_air_quality_index")
    )
)


query = (
    aggregated_data
    .writeStream
    .outputMode("append")
    .format("console")
    .option("truncate", "false")
    .option("numRows", 100)
    .option("checkpointLocation", "/tmp/urban-sensor-checkpoint")
    .start()
)


query.awaitTermination()
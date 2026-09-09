import json
from datetime import timedelta
from pyflink.common.watermark_strategy import TimestampAssigner
from pyflink.common import Types, WatermarkStrategy, Duration
from pyflink.common.serialization import SimpleStringSchema
from pyflink.datastream import StreamExecutionEnvironment
from pyflink.datastream.connectors.kinesis import (
    FlinkKinesisConsumer,
)
from pyflink.datastream.window import TumblingEventTimeWindows
from pyflink.common.time import Time
from pyflink.datastream.functions import MapFunction, ReduceFunction
from pyflink.common.typeinfo import RowTypeInfo


STREAM_NAME = "clicks-ecommerce"
REGION = "us-east-1"


class ParseClickEvent(MapFunction):
    """Parsea el JSON crudo de Kinesis y extrae (product_id, event_time_ms, count=1)."""

    def map(self, value):
        data = json.loads(value)
        product_id = data["product_id"]
        # timestamp viene en formato ISO 8601 -> lo convertimos a epoch millis
        from datetime import datetime
        ts = datetime.fromisoformat(data["timestamp"])
        event_time_ms = int(ts.timestamp() * 1000)
        return (product_id, event_time_ms, 1)


class SumClicks(ReduceFunction):
    """Suma los clics dentro de la misma ventana para el mismo product_id."""

    def reduce(self, a, b):
        return (a[0], max(a[1], b[1]), a[2] + b[2])


class ClickTimestampAssigner(TimestampAssigner):
    def extract_timestamp(self, value, record_timestamp):
        return value[1]



def main():
    env = StreamExecutionEnvironment.get_execution_environment()
    env.set_parallelism(1)
    #env.add_jars("file:///C:/Users/Usuario/Desktop/Nueva%20carpeta/.data11/mi-proyecto-dataops/flink/lib/flink-sql-connector-kinesis-1.15.4.jar")
    
    # Configuración del consumidor de Kinesis
    consumer_config = {
        "aws.region": REGION,
        "flink.stream.initpos": "LATEST",
    }

    kinesis_consumer = FlinkKinesisConsumer(
        STREAM_NAME,
        SimpleStringSchema(),
        consumer_config,
    )

    raw_stream = env.add_source(kinesis_consumer)

    # Parseamos cada evento a (product_id, event_time_ms, count)
    parsed_stream = raw_stream.map(
        ParseClickEvent(),
        output_type=Types.TUPLE([Types.STRING(), Types.LONG(), Types.INT()]),
    )

    # Watermark: tolerancia de 10 segundos de desorden en la red
    watermark_strategy = (
        WatermarkStrategy
        .for_bounded_out_of_orderness(Duration.of_seconds(10))
        .with_timestamp_assigner(ClickTimestampAssigner())
        .with_idleness(Duration.of_seconds(20))
    )
    

    timestamped_stream = parsed_stream.assign_timestamps_and_watermarks(
        watermark_strategy
    )

    # KeyedState por product_id + Tumbling Window de 1 minuto + suma de clics
    result_stream = (
        timestamped_stream
        .key_by(lambda event: event[0])
        .window(TumblingEventTimeWindows.of(Time.minutes(1)))
        .reduce(SumClicks())
    )

    # with result_stream.execute_and_collect() as results:
        # for result in results:
            # print(f"Resultado: producto={result[0]} | ventana_fin={result[1]} | clics={result[2]}")

    result_stream.print()

    env.execute("clicks-por-producto-tumbling-1min")
if __name__ == "__main__":
    main()
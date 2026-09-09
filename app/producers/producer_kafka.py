import json
import random
import time
from datetime import datetime, timezone

from kafka import KafkaProducer


KAFKA_BOOTSTRAP_SERVERS = "localhost:29092"
KAFKA_TOPIC = "urban_sensors"


producer = KafkaProducer(
    bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
    value_serializer=lambda value: json.dumps(value).encode("utf-8"),
)


sensors = [
    "sensor-001",
    "sensor-002",
    "sensor-003",
    "sensor-004",
    "sensor-005",
]


try:
    while True:
        sensor_id = random.choice(sensors)

        message = {
            "sensor_id": sensor_id,
            "temperature": round(random.uniform(15.0, 35.0), 2),
            "humidity": round(random.uniform(30.0, 90.0), 2),
            "air_quality_index": random.randint(20, 150),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

        future = producer.send(KAFKA_TOPIC, value=message)
        metadata = future.get(timeout=10)

        print(
            f"Enviado | topic={metadata.topic} "
            f"partition={metadata.partition} "
            f"offset={metadata.offset} | {message}"
        )

        time.sleep(2)

except KeyboardInterrupt:
    print("\nProductor detenido.")

finally:
    producer.flush()
    producer.close()
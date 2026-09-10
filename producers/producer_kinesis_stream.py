"""
Productor CONTINUO para la prueba de persistencia Iceberg.

Por que no sirve el producer de rafagas:
  con event-time + watermark, una ventana TUMBLE solo cierra cuando llega un
  evento POSTERIOR al fin de la ventana. Si el productor manda 100 eventos en
  2 segundos y muere, el watermark se congela y la ultima ventana NUNCA dispara
  -> no hay filas -> no hay archivos -> no hay commit en Glue.

Uso:
    python producers\producer_kinesis_stream.py           # 6 min, 5 ev/s
    python producers\producer_kinesis_stream.py 480 10    # 8 min, 10 ev/s
"""

import json
import sys
import time
import uuid
from datetime import datetime, timezone

import boto3

STREAM_NAME = "clicks-ecommerce"
REGION = "us-east-1"
N_PRODUCTS = 10

duration_s = int(sys.argv[1]) if len(sys.argv) > 1 else 360
rate_per_s = float(sys.argv[2]) if len(sys.argv) > 2 else 5.0

kinesis = boto3.client("kinesis", region_name=REGION)

deadline = time.time() + duration_s
sent = 0
i = 0

print(f"Emitiendo {rate_per_s} ev/s durante {duration_s}s hacia {STREAM_NAME}...")

while time.time() < deadline:
    i += 1
    event = {
        "event_id": str(uuid.uuid4()),
        "user_id": f"user-{i}",
        "event_type": "click",
        "product_id": f"product-{(i % N_PRODUCTS) + 1}",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    kinesis.put_record(
        StreamName=STREAM_NAME,
        Data=json.dumps(event),
        PartitionKey=event["user_id"],
    )
    sent += 1
    if sent % 50 == 0:
        print(f"  {sent} eventos enviados - restan {int(deadline - time.time())}s")
    time.sleep(1.0 / rate_per_s)

print(f"Ingesta finalizada: {sent} eventos enviados.")

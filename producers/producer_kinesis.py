import boto3
import json
import uuid
from datetime import datetime, timezone


STREAM_NAME = "clicks-ecommerce"
REGION = "us-east-1"


kinesis = boto3.client(
    "kinesis",
    region_name=REGION
)


for i in range(100):

    event = {
        "event_id": str(uuid.uuid4()),
        "user_id": f"user-{i + 1}",
        "event_type": "click",
        "product_id": f"product-{(i % 10) + 1}",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

    response = kinesis.put_record(
        StreamName=STREAM_NAME,
        Data=json.dumps(event),
        PartitionKey=event["user_id"]
    )

    print(
        f"{i + 1}/100 - "
        f"User: {event['user_id']} - "
        f"Shard: {response['ShardId']}"
    )

print("Ingesta finalizada: 100 eventos enviados.")
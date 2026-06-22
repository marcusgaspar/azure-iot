"""
main.py

Edge video analytics module (simulation mode).

Simulates an object-detection pipeline: at a fixed interval it generates
random detection results and publishes them to the AIO MQTT broker. No camera
or video file is required – this is a self-contained demo workload.

Environment variables (all optional – defaults shown):
  DETECTION_INTERVAL  Seconds between detections           (default: 1.0)
  FRAME_WIDTH         Simulated frame width in pixels      (default: 1280)
  FRAME_HEIGHT        Simulated frame height in pixels     (default: 720)
  MQTT_HOST           AIO MQTT broker service hostname
                      (default: aio-broker)
  MQTT_PORT           MQTT broker port                     (default: 1883)
  MQTT_TOPIC          Topic to publish detections to
                      (default: video-analytics/detections)
  DEVICE_ID           Identifier reported in every message
                      (default: edge-device-01)
  APP_VERSION         Application version (set at build time via the
                      Docker build-arg APP_VERSION)        (default: dev)
  LOG_LEVEL           Python logging level                  (default: INFO)
"""

import json
import logging
import os
import random
import time
import uuid
from datetime import datetime, timezone

import paho.mqtt.client as mqtt

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DETECTION_INTERVAL = float(os.environ.get("DETECTION_INTERVAL", "1.0"))
FRAME_WIDTH = int(os.environ.get("FRAME_WIDTH", "1280"))
FRAME_HEIGHT = int(os.environ.get("FRAME_HEIGHT", "720"))
MQTT_HOST = os.environ.get("MQTT_HOST", "aio-broker")
MQTT_PORT = int(os.environ.get("MQTT_PORT", "1883"))
MQTT_TOPIC = os.environ.get("MQTT_TOPIC", "video-analytics/detections")
DEVICE_ID = os.environ.get("DEVICE_ID", "edge-device-01")
APP_VERSION = os.environ.get("APP_VERSION", "dev")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s %(levelname)s %(name)s – %(message)s",
)
log = logging.getLogger("video-analytics")

# ---------------------------------------------------------------------------
# Object detection (placeholder – swap in your real model)
# ---------------------------------------------------------------------------

def detect_objects() -> list[dict]:
    """
    Stub detector.  Replace this function with a real model call, e.g.
    ONNX Runtime, TensorFlow Lite, or an Azure Cognitive Services call.

    Returns a list of detection dicts with keys:
      label      – class label string
      confidence – float in [0, 1]
      bbox       – [x, y, width, height] in pixels
    """
    # Demo: randomly emit a detection so the demo produces visible output
    # without a real model or video source.
    if random.random() > 0.4:
        return []

    w, h = FRAME_WIDTH, FRAME_HEIGHT
    return [
        {
            "label": random.choice(["person", "vehicle", "package"]),
            "confidence": round(random.uniform(0.65, 0.99), 3),
            "bbox": [
                random.randint(0, w // 2),
                random.randint(0, h // 2),
                random.randint(50, w // 2),
                random.randint(50, h // 2),
            ],
        }
    ]


# ---------------------------------------------------------------------------
# MQTT helpers
# ---------------------------------------------------------------------------

def build_mqtt_client() -> mqtt.Client:
    client_id = f"{DEVICE_ID}-{uuid.uuid4().hex[:8]}"
    client = mqtt.Client(client_id=client_id)

    def on_connect(client, userdata, flags, rc):
        if rc == 0:
            log.info("Connected to MQTT broker %s:%d", MQTT_HOST, MQTT_PORT)
        else:
            log.error("MQTT connection failed with code %d", rc)

    def on_disconnect(client, userdata, rc):
        if rc != 0:
            log.warning("Unexpected MQTT disconnect (rc=%d). Will reconnect.", rc)

    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    return client


def connect_with_retry(client: mqtt.Client, max_retries: int = 10) -> None:
    for attempt in range(1, max_retries + 1):
        try:
            client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
            client.loop_start()
            return
        except Exception as exc:
            wait = min(2 ** attempt, 30)
            log.warning(
                "MQTT connect attempt %d/%d failed: %s. Retrying in %ds.",
                attempt,
                max_retries,
                exc,
                wait,
            )
            time.sleep(wait)
    raise RuntimeError(f"Could not connect to MQTT broker after {max_retries} attempts")


def publish_detection(client: mqtt.Client, detections: list[dict], frame_id: int) -> None:
    payload = {
        "deviceId": DEVICE_ID,
        "version": APP_VERSION,
        "messageId": str(uuid.uuid4()),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "frameId": frame_id,
        "detections": detections,
    }
    info = client.publish(MQTT_TOPIC, json.dumps(payload), qos=1)
    if info.rc != mqtt.MQTT_ERR_SUCCESS:
        log.warning("Failed to publish detection (rc=%d)", info.rc)
    else:
        log.debug("Published %d detection(s) for frame %d", len(detections), frame_id)
        log.debug("Payload: %s", json.dumps(payload))


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

def run() -> None:
    log.info(
        "Starting video analytics (simulation mode, device=%s, version=%s)",
        DEVICE_ID,
        APP_VERSION,
    )

    mqtt_client = build_mqtt_client()
    connect_with_retry(mqtt_client)

    frame_id = 0

    try:
        while True:
            frame_id += 1
            detections = detect_objects()
            if detections:
                log.info("Frame %d: %d object(s) detected", frame_id, len(detections))
                publish_detection(mqtt_client, detections, frame_id)
            time.sleep(DETECTION_INTERVAL)

    except KeyboardInterrupt:
        log.info("Shutting down.")
    finally:
        mqtt_client.loop_stop()
        mqtt_client.disconnect()


if __name__ == "__main__":
    run()

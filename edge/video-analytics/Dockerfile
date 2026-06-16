# ---------------------------------------------------------------------------
# Multi-stage Dockerfile for the video-analytics edge component
# ---------------------------------------------------------------------------

# ── Build stage ──────────────────────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /build

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM python:3.11-slim AS runtime

# Install OS-level packages needed by OpenCV
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libglib2.0-0 \
      libgl1 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy installed Python packages from builder
COPY --from=builder /install /usr/local

# Copy application source
COPY src/ ./src/

# Non-root user for security
RUN useradd --uid 1000 --no-create-home appuser
USER appuser

# Default environment (override via Kubernetes ConfigMap / Secret)
ENV VIDEO_SOURCE=0 \
    DETECTION_INTERVAL=1.0 \
    MQTT_HOST=aio-broker \
    MQTT_PORT=1883 \
    MQTT_TOPIC=video-analytics/detections \
    DEVICE_ID=edge-device-01 \
    LOG_LEVEL=INFO

ENTRYPOINT ["python", "src/main.py"]

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


WORKDIR /app

# Copy installed Python packages from builder
COPY --from=builder /install /usr/local

# Copy application source
COPY src/ ./src/

# Non-root user for security
RUN useradd --uid 1000 --no-create-home appuser
USER appuser

# Application version, injected at build time:
#   az acr build --build-arg APP_VERSION=0.1.0 ...
ARG APP_VERSION=0.1.6

# Default environment (override via Kubernetes ConfigMap / Secret)
ENV DETECTION_INTERVAL=3.0 \
    MQTT_HOST=aio-broker \
    MQTT_PORT=1883 \
    MQTT_TOPIC=video-analytics/detections \
    DEVICE_ID=edge-device-01 \
    APP_VERSION=${APP_VERSION} \
    LOG_LEVEL=INFO

ENTRYPOINT ["python", "src/main.py"]

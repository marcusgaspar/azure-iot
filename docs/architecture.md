# Architecture: Azure IoT Hub + Azure IoT Operations (Video Analytics Demo)

## Overview

This solution deploys video analytics on edge Kubernetes clusters while
providing centralised control through Azure IoT Hub.  Azure IoT Operations
(AIO) acts as the messaging layer, routing telemetry from the edge to the
cloud via MQTT.

The main operational pain addressed is **automated container image updates on
edge devices**, solved end-to-end through a GitOps pipeline powered by
[Flux CD](https://fluxcd.io/).

---

## High-Level Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│                          AZURE CLOUD                                       │
│                                                                            │
│  ┌──────────────┐    telemetry    ┌──────────────────────────────────┐    │
│  │  Azure IoT   │◄───────────────│  Azure Container Registry (ACR)  │    │
│  │     Hub      │                └──────────────────────────────────┘    │
│  └──────┬───────┘                         ▲  container images            │
│         │ device twin / C2D commands       │                              │
│         │                        ┌─────────┴────────────┐                │
│         │                        │   GitHub Actions CI   │                │
│         │                        │  (build-push-image)   │                │
│         │                        └──────────────────────┘                │
└─────────┼──────────────────────────────────────────────────────────────────┘
          │ MQTT (via AIO connector)
┌─────────┼──────────────────────────────────────────────────────────────────┐
│         │          EDGE KUBERNETES CLUSTER (Arc-enrolled)                  │
│  ┌──────┴─────────────────────────────────────┐                           │
│  │        Azure IoT Operations (AIO)           │                           │
│  │                                             │                           │
│  │  ┌─────────────┐    ┌────────────────────┐ │                           │
│  │  │ MQTT Broker │◄───│  Data Processor     │ │                           │
│  │  │  (aio-broker│    │  (video-analytics-  │ │                           │
│  │  │  :1883)     │    │   pipeline)         │ │                           │
│  │  └──────▲──────┘    └────────────────────┘ │                           │
│  │         │ MQTT publish                      │                           │
│  └─────────┼───────────────────────────────────┘                           │
│            │                                                               │
│  ┌─────────┴──────────────────────────────────┐                           │
│  │     video-analytics Deployment              │                           │
│  │     (Pod: captures frames → detects →       │                           │
│  │      publishes to AIO MQTT broker)          │                           │
│  └─────────────────────────────────────────────┘                           │
│                                                                            │
│  ┌─────────────────────────────────────────────┐                           │
│  │  Flux CD  (image-reflector + image-automation│                           │
│  │  + source-controller + kustomize-controller) │                           │
│  │                                             │                           │
│  │  Watches ACR → detects new image tag →      │                           │
│  │  commits updated deployment.yaml → reconciles│                           │
│  └─────────────────────────────────────────────┘                           │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Components

### Azure Resources (`infra/`)

| Resource | Purpose |
|---|---|
| **Azure IoT Hub** | Centralized device management, twin synchronisation, D2C telemetry ingest |
| **Azure Container Registry (ACR)** | Private registry for edge container images |
| **Azure Arc-connected cluster** | Brings the edge Kubernetes cluster under Azure management |
| **AIO Extension** | Deploys MQTT broker + data processor + IoT Hub connector |

### Edge Components (`edge/`)

| Component | Path | Description |
|---|---|---|
| **video-analytics** app | `edge/video-analytics/` | Python app: captures frames, runs object detection, publishes results via MQTT |
| **Kubernetes manifests** | `edge/k8s/` | Namespace, Deployment, ConfigMap, Service |
| **AIO MQTT broker** | `edge/k8s/aio/mqtt-broker.yaml` | BrokerListener + DataPipeline to IoT Hub |

### GitOps (`gitops/`)

| Resource | Description |
|---|---|
| **GitRepository** | Flux source pointing at this repo |
| **Kustomization** | Reconciles `edge/k8s/` onto the cluster |
| **ImageRepository** | Polls ACR for new image tags every minute |
| **ImagePolicy** | Selects the newest semver tag (`>=0.1.0`) |
| **ImageUpdateAutomation** | Commits the updated image tag back to Git; triggers a rolling update |

---

## Container Image Update Flow (GitOps)

The key pain addressed is the manual process of SSHing into edge devices to
pull and restart containers.  The automated flow is:

```
Developer pushes code
        │
        ▼
GitHub Actions (build-push-image.yml)
  • builds the container image
  • tags it with a semver (e.g., 1.2.3) and SHA
  • pushes to ACR
        │
        ▼
Flux ImageRepository (polls ACR every 1 min)
  • detects new tag 1.2.3
        │
        ▼
Flux ImagePolicy
  • selects 1.2.3 as the latest matching semver
        │
        ▼
Flux ImageUpdateAutomation
  • updates the image tag in edge/k8s/video-analytics/deployment.yaml
  • commits: "chore: update video-analytics image to 1.2.3"
  • pushes to main branch
        │
        ▼
Flux Kustomization (watches main branch)
  • detects new commit
  • applies updated Deployment to the edge cluster
        │
        ▼
Kubernetes rolling update
  • pulls new image from ACR
  • replaces the running pod with zero downtime
```

**No manual SSH or kubectl access to edge devices required.**

---

## MQTT Message Flow

```
video-analytics pod
  → PUBLISH to "video-analytics/detections" (QoS 1)
      → AIO MQTT Broker (aio-broker:1883)
          → AIO Data Processor (video-analytics-pipeline)
              → AIO IoT Hub Connector
                  → Azure IoT Hub (D2C messages)
```

Sample detection message published by the app:

```json
{
  "deviceId": "edge-device-01",
  "messageId": "3f2e1a0b-...",
  "timestamp": "2024-06-16T12:00:00.000Z",
  "frameId": 42,
  "detections": [
    {
      "label": "person",
      "confidence": 0.93,
      "bbox": [120, 80, 200, 350]
    }
  ]
}
```

---

## Repository Structure

```
azure-iot/
├── infra/                        Infrastructure as Code (Bicep)
│   ├── main.bicep
│   ├── modules/
│   │   ├── iothub.bicep
│   │   ├── acr.bicep
│   │   └── aio.bicep
│   └── parameters/
│       └── dev.bicepparam
├── edge/
│   ├── video-analytics/          Container image source
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   └── src/main.py
│   └── k8s/                      Kubernetes manifests
│       ├── namespace.yaml
│       ├── video-analytics/
│       │   ├── configmap.yaml
│       │   ├── deployment.yaml   ← image tag updated by Flux
│       │   └── service.yaml
│       └── aio/
│           └── mqtt-broker.yaml  AIO broker + pipeline config
├── gitops/
│   └── clusters/edge-cluster/    Flux configuration
│       ├── gitrepository.yaml
│       ├── kustomization.yaml
│       ├── image-repository.yaml
│       ├── image-policy.yaml
│       └── image-update-automation.yaml
├── .github/
│   └── workflows/
│       ├── build-push-image.yml  CI: build & push image to ACR
│       └── deploy-infra.yml      CD: deploy Bicep infrastructure
├── scripts/
│   └── bootstrap.sh              One-shot cluster bootstrap
└── docs/
    └── architecture.md           This document
```

---

## Prerequisites

- Azure subscription with Contributor access
- Azure CLI (`az`) ≥ 2.55
- `kubectl` pointing at an existing Kubernetes cluster (k3s, k8s, AKS-edge, etc.)
- Flux CLI ≥ 2.x
- GitHub account and a PAT with `repo` scope (for Flux bootstrap)

## Quick Start

See [`scripts/bootstrap.sh`](../scripts/bootstrap.sh) for a guided
one-shot setup, or follow the manual steps below.

```bash
# 1. Set environment variables (see bootstrap.sh header for the full list)
export SUBSCRIPTION_ID="<your-sub>"
export RESOURCE_GROUP="rg-azure-iot-demo"
export CLUSTER_NAME="my-edge-cluster"
export GITHUB_TOKEN="<pat>"
export GITHUB_OWNER="<your-gh-org>"

# 2. Run bootstrap
bash scripts/bootstrap.sh

# 3. Trigger first image build
az acr build \
  --registry aiotdemoacr \
  --image video-analytics:0.1.0 \
  edge/video-analytics

# 4. Watch Flux reconcile
flux get all -A

# 5. Monitor IoT Hub telemetry
az iot hub monitor-events --hub-name aiotdemo-iothub
```

---

## Security Notes

- Container images run as non-root (`runAsUser: 1000`).
- ACR is accessed via a scoped token (`_repositories_pull`), never admin credentials.
- OIDC federated identity is used for GitHub Actions → Azure authentication (no long-lived secrets).
- For production, enable TLS on the AIO MQTT BrokerListener and configure mTLS client authentication.

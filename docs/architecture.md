# Architecture: Azure IoT Operations (Video Analytics Demo)

## Overview

This solution deploys video analytics on edge Kubernetes clusters. Azure IoT
Operations (AIO) acts as the edge data plane: it processes detections locally on
the MQTT broker and forwards only the relevant data to the cloud via a dataflow
to **Azure Event Hubs**. From there, the telemetry is ingested into
**Microsoft Fabric** (Eventstream → Eventhouse) and visualised in near real time
through a **Real-Time Dashboard**. Centralised management of the edge cluster
itself is handled by **Azure Arc**, not by a cloud device-management service.

The **automated container image updates on
edge devices** is solved end-to-end through a GitOps pipeline powered by
[Flux CD](https://fluxcd.io/) and GitHub Actions.

---

## How It Works

1. **Video analytics app** runs on the edge cluster, processes video frames, and
   publishes detection results to the **AIO MQTT broker**.
2. **AIO Dataflow** forwards the processed messages to **Azure Event Hubs** in
   the cloud for downstream consumption.
3. **Microsoft Fabric Eventstream** connects to the Event Hub as a source and
   streams the detection events into the platform.
4. **Fabric Eventhouse (KQL Database)** persists the events, making them
   queryable with KQL.
5. **Real-Time Dashboard** runs KQL queries against the Eventhouse to display
   live detections, throughput, and per-class metrics (see
   [`dashboards/realtime-detections.kql`](../dashboards/realtime-detections.kql)).
6. When a developer pushes code, **GitHub Actions** builds a new container image
   and pushes it to **Azure Container Registry (ACR)**.
7. **Flux Image Automation** detects the new tag in ACR, updates the image
   reference in the deployment manifest, and commits the change to Git.
8. **Flux Kustomization** reconciles the cluster — no SSH, no manual `kubectl`
   commands needed on edge devices.

---

## High-Level Architecture

```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                                  AZURE CLOUD                                          │
│                                                                                       │
│  ┌──────────────────────  MICROSOFT FABRIC  ────────────────────┐                     │
│  │  ┌───────────────┐   ┌───────────────┐   ┌───────────────┐   │                     │
│  │  │  Eventstream  │ → │   Eventhouse  │ → │   Real-Time   │   │                     │
│  │  │ (event-stream-│   │ (KQL Database │   │   Dashboard   │   │                     │
│  │  │     iot)      │   │  'detections')│   │               │   │                     │
│  │  └───────────────┘   └───────────────┘   └───────────────┘   │                     │
│  └──────▲───────────────────────────────────────────────────────┘                     │
│         │ source                                                                      │
│  ┌──────┴──────┐                          ┌──────────────────────────────┐            │
│  │ Azure Event │                          │   Azure Container Registry   │            │
│  │    Hubs     │                          │            (ACR)             │            │
│  └──────▲──────┘                          └─────────▲───────────────┬────┘            │
│         │                                           │ push image    │ pull image      │
│         │ AIO Dataflow                     ┌────────┴──────────┐    │                 │
│         │ (MQTT → Event Hubs)              │  GitHub Actions   │    │                 │
│         │                                  │ (build-push-image)│    │                 │
│         │                                  └───────────────────┘    │                 │
└─────────┼───────────────────────────────────────────────────────────┼─────────────────┘
          │                                                           │
          │ AIO Dataflow                                              │ image pull
          │                                                           │ (by Kubernetes)
┌─────────┼───────────────────────────────────────────────────────────▼─────────────────┐
│         │           EDGE KUBERNETES CLUSTER (Arc-enrolled)                            │
│  ┌──────┴─────────────────────────────────────┐                                       │
│  │        Azure IoT Operations (AIO)          │                                       │
│  │                                            │                                       │
│  │  ┌─────────────┐    ┌────────────────────┐ │                                       │
│  │  │ MQTT Broker │◄───│  Data Processor    │ │                                       │
│  │  │  (aio-broker│    │  (video-analytics- │ │                                       │
│  │  │  :1883)     │    │   pipeline)        │ │                                       │
│  │  └──────▲──────┘    └────────────────────┘ │                                       │
│  │         │ MQTT publish                     │                                       │
│  └─────────┼──────────────────────────────────┘                                       │
│            │                                                                          │
│  ┌─────────┴──────────────────────────────────┐                                       │
│  │     video-analytics Deployment             │                                       │
│  │     (Pod: captures frames → detects →      │                                       │
│  │      publishes to AIO MQTT broker)         │                                       │
│  └────────────────────────────────────────────┘                                       │
│  ┌───────────────────────────────────────────────┐                                    │
│  │  Flux CD  (image-reflector + image-automation │                                    │
│  │  + source-controller + kustomize-controller)  │                                    │
│  │                                               │                                    │
│  │  Watches ACR → detects new image tag →        │                                    │
│  │  commits updated deployment.yaml → reconciles │                                    │
│  └───────────────────────────────────────────────┘                                    │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Real-Time Telemetry Flow (Edge → Fabric Dashboard)

Once a detection leaves the edge, it travels through the following stages before
it appears on the dashboard:

```
AIO Dataflow
  → Azure Event Hubs (detections)            ← cloud ingestion endpoint
      → Fabric Eventstream (event-stream-iot) ← connects to Event Hub as source
          → Fabric Eventhouse / KQL DB        ← persists events in table 'detections'
              → Real-Time Dashboard            ← KQL tiles render live metrics
```

| Stage               | Service                        | What happens                                                                                                                                                         |
| ------------------- | ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. Edge forwarding  | **AIO Dataflow**               | Subscribes to the MQTT topic and forwards each detection message to Azure Event Hubs.                                                                                |
| 2. Cloud ingestion  | **Azure Event Hubs**           | Acts as the scalable buffer/ingestion endpoint. The `detections` event hub receives the raw JSON events.                                                             |
| 3. Stream ingestion | **Fabric Eventstream**         | The `event-stream-iot` Eventstream uses the Event Hub as a source and streams events into Fabric.                                                                    |
| 4. Storage & query  | **Fabric Eventhouse (KQL DB)** | Events land in the `detections` table (the `detections` array stays as a `dynamic` column). Queryable via KQL.                                                       |
| 5. Visualisation    | **Real-Time Dashboard**        | Each tile runs a KQL query (see `dashboards/realtime-detections.kql`) to show counts, per-class stats, timelines, and per-request views, with optional auto-refresh. |

---

## Components

### Azure Resources (`infra/`)

| Resource                           | Purpose                                                                |
| ---------------------------------- | ---------------------------------------------------------------------- |
| **Azure Event Hubs**               | Cloud ingestion endpoint for processed telemetry from the AIO dataflow |
| **Microsoft Fabric Eventstream**   | Streams events from the Event Hub source into Fabric                   |
| **Microsoft Fabric Eventhouse**    | KQL Database that persists detection events for querying               |
| **Real-Time Dashboard**            | KQL-driven dashboard visualising live detections and metrics           |
| **Azure Container Registry (ACR)** | Private registry for edge container images                             |
| **Azure Arc-connected cluster**    | Brings the edge Kubernetes cluster under Azure management              |
| **AIO Extension**                  | Deploys MQTT broker + data processor + dataflow to Event Hubs          |

### Edge Components (`edge/`)

| Component                | Path                            | Description                                                                    |
| ------------------------ | ------------------------------- | ------------------------------------------------------------------------------ |
| **video-analytics** app  | `edge/video-analytics/`         | Python app: captures frames, runs object detection, publishes results via MQTT |
| **Kubernetes manifests** | `edge/k8s/`                     | Namespace, Deployment, ConfigMap, Service                                      |
| **AIO MQTT broker**      | `edge/k8s/aio/mqtt-broker.yaml` | BrokerListener + Dataflow to Event Hubs                                        |

### GitOps (`gitops/`)

| Resource                  | Description                                                          |
| ------------------------- | -------------------------------------------------------------------- |
| **GitRepository**         | Flux source pointing at this repo                                    |
| **Kustomization**         | Reconciles `edge/k8s/` onto the cluster                              |
| **ImageRepository**       | Polls ACR for new image tags every minute                            |
| **ImagePolicy**           | Selects the newest semver tag (`>=0.1.0`)                            |
| **ImageUpdateAutomation** | Commits the updated image tag back to Git; triggers a rolling update |

---

## Container Image Update Flow (GitOps)

The key pain addressed is the manual process of SSHing into edge devices to
pull and restart containers. The automated flow is:

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
              → AIO Dataflow
                  → Azure Event Hubs (cloud ingestion)
                      → Fabric Eventstream (event-stream-iot)
                          → Fabric Eventhouse / KQL DB (table 'detections')
                              → Real-Time Dashboard (KQL tiles)
```

Sample detection message published by the app:

```json
{
  "deviceId": "edge-device-01",
  "version": "1.2.3",
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
│   │   ├── eventhubs.bicep
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
│           └── mqtt-broker.yaml  AIO broker + dataflow config
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

# 5. Monitor cloud telemetry on Event Hubs
az eventhubs eventhub consumer-group show \
  --resource-group rg-azure-iot-demo \
  --namespace-name aiotdemo-eventhubs \
  --eventhub-name detections \
  --name '$Default'
```

---

## Security Notes

- Container images run as non-root (`runAsUser: 1000`).
- ACR is accessed via a scoped token (`_repositories_pull`), never admin credentials.
- OIDC federated identity is used for GitHub Actions → Azure authentication (no long-lived secrets).
- For production, enable TLS on the AIO MQTT BrokerListener and configure mTLS client authentication.

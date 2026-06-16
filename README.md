# Azure IoT Hub + Azure IoT Operations — Video Analytics Demo

A reference solution that deploys **video analytics on edge Kubernetes devices**
with centralised control through **Azure IoT Hub** and messaging via
**Azure IoT Operations (AIO) MQTT**.  The solution specifically addresses the
operational pain of **updating container images on edge devices** through a
fully automated GitOps pipeline.

---

## What's in This Repo

| Folder | Contents |
|---|---|
| `infra/` | Bicep templates — IoT Hub, ACR, AIO extension on Arc cluster |
| `edge/video-analytics/` | Python container app (OpenCV + paho-mqtt) |
| `edge/k8s/` | Kubernetes manifests (namespace, deployment, AIO MQTT broker) |
| `gitops/` | Flux CD resources for automated image updates |
| `.github/workflows/` | CI/CD pipelines (build image, deploy infra) |
| `scripts/` | One-shot bootstrap script |
| `docs/` | Architecture documentation |

---

## How It Works

1. **Video analytics app** runs on the edge cluster, processes video frames, and
   publishes detection results to the **AIO MQTT broker**.
2. **AIO Data Processor** forwards messages to **Azure IoT Hub** for centralised
   monitoring and control.
3. When a developer pushes code, **GitHub Actions** builds a new container image
   and pushes it to **Azure Container Registry (ACR)**.
4. **Flux Image Automation** detects the new tag in ACR, updates the image
   reference in the deployment manifest, and commits the change to Git.
5. **Flux Kustomization** reconciles the cluster — no SSH, no manual `kubectl`
   commands needed on edge devices.

See [docs/architecture.md](docs/architecture.md) for the full architecture
diagram and component descriptions.

---

## Quick Start

### Prerequisites

- Azure subscription with Contributor rights
- Azure CLI ≥ 2.55, Flux CLI ≥ 2.x, `kubectl`
- Kubernetes cluster (k3s, AKS Edge Essentials, or any K8s distro)
- GitHub PAT with `repo` scope

### Deploy

```bash
# 1. Configure variables (see scripts/bootstrap.sh for the full list)
export SUBSCRIPTION_ID="<your-sub>"
export RESOURCE_GROUP="rg-azure-iot-demo"
export CLUSTER_NAME="my-edge-cluster"
export GITHUB_TOKEN="<pat>"
export GITHUB_OWNER="<your-gh-org>"

# 2. Bootstrap everything (infra + Arc + Flux)
bash scripts/bootstrap.sh

# 3. Build and push the first image
az acr build \
  --registry aiotdemoacr \
  --image video-analytics:0.1.0 \
  edge/video-analytics

# 4. Watch Flux roll it out automatically
flux get all -A

# 5. Monitor IoT Hub telemetry
az iot hub monitor-events --hub-name aiotdemo-iothub
```

### GitHub Actions secrets/variables required

| Name | Type | Description |
|---|---|---|
| `AZURE_CLIENT_ID` | Secret | App registration client ID (OIDC) |
| `AZURE_TENANT_ID` | Secret | Azure tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Secret | Azure subscription ID |
| `ACR_NAME` | Variable | ACR name (e.g. `aiotdemoacr`) |
| `RESOURCE_GROUP` | Variable | Resource group name |

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
│   └── parameters/dev.bicepparam
├── edge/
│   ├── video-analytics/          Container image source
│   └── k8s/                      Kubernetes manifests
├── gitops/clusters/edge-cluster/ Flux configuration
├── .github/workflows/            CI/CD pipelines
├── scripts/bootstrap.sh          One-shot bootstrap
└── docs/architecture.md          Architecture details
```
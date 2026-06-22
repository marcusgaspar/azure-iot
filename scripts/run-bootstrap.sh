#!/bin/bash

# 1. Pré-requisitos instalados
az version          # Azure CLI
kubectl version --client
flux --version      # se faltar: https://fluxcd.io/flux/installation/

# 2. Autenticar no Azure
 az login --skip-sub

# 3. Apontar o KUBECONFIG para o cluster edge
# Esse é o passo que conecta sua máquina ao cluster. Copie o kubeconfig da VM edge (ajuste o IP):
#IP_VM="20.65.253.160"
#ssh -i ~/.ssh/id_edge azureadmin@$IP_VM "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/KUBECONFIG.edge
#sed -i "s/127.0.0.1/$IP_VM/" ~/.kube/KUBECONFIG.edge
#export KUBECONFIG=~/.kube/KUBECONFIG.edge
#unset KUBECONFIG

# valide a conexão:
#kubectl get nodes

# 4. Configurar as variáveis (via .env)
cd /mnt/c/_repo/azure-iot/video-analytics-demo/azure-iot   # raiz do repo no WSL
#gh auth login
#gh api user --jq .login

# 5. Rodar o bootstrap pulando o deploy
SKIP_DEPLOY=1 bash scripts/bootstrap.sh

# Troubleshooting

source scripts/.env
kubectl create secret generic git-credentials \
  -n flux-system \
  --from-literal=username=git \
  --from-literal=password=$GITHUB_TOKEN \
  --dry-run=client -o yaml | kubectl apply -f -

flux reconcile source git azure-iot-demo -n flux-system
flux get all -A


kubectl get secret git-credentials -n flux-system

kubectl get secret acr-credentials -n flux-system


ACR_NAME=aiotdemoacr
ACR_TOKEN=$(az acr token create \
  --name flux-image-pull \
  --registry $ACR_NAME \
  --scope-map _repositories_pull \
  --query "credentials.passwords[0].value" -o tsv)

kubectl create secret docker-registry acr-credentials \
  --namespace flux-system \
  --docker-server=$ACR_NAME.azurecr.io \
  --docker-username=flux-image-pull \
  --docker-password="$ACR_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
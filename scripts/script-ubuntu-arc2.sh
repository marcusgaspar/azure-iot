#!/bin/bash

# Atualizar os pacotes existentes
apt update -y

# Instalar os pré-requisitos para o Azure CLI
apt install -y ca-certificates curl apt-transport-https lsb-release gnupg jq

# Adicionar a chave de assinatura da Microsoft
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null

# Adicionar o repositório do Azure CLI
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list

# Atualizar os pacotes novamente e instalar o Azure CLI
apt update -y
apt install -y azure-cli

# Instala o k3s
curl -sfL https://get.k3s.io | sh -

az config set extension.use_dynamic_install=yes_without_prompt

az config set extension.dynamic_install_allow_preview=true

az extension add --upgrade --name azure-iot-ops

az extension add --name connectedk8s

az extension add --name k8s-extension

az extension add --name customlocation

az extension update --name connectedk8s

az extension update --name k8s-extension

az extension update --name customlocation

az provider register --namespace Microsoft.ExtendedLocation

az provider register --namespace Microsoft.Kubernetes 

az provider register --namespace Microsoft.KubernetesConfiguration

curl -LO https://dl.k8s.io/release/v1.29.3/bin/linux/amd64/kubectl

install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

chmod +x kubectl

mkdir -p ~/.local/bin

mv ./kubectl ~/.local/bin/kubectl

mkdir ~/.kube

KUBECONFIG=~/.kube/config:/etc/rancher/k3s/k3s.yaml kubectl config view --flatten > ~/.kube/merged

mv ~/.kube/merged ~/.kube/config

chmod  0600 ~/.kube/config

export KUBECONFIG=~/.kube/config
#switch to k3s context

kubectl config use-context default

chmod 644 /etc/rancher/k3s/k3s.yaml

echo fs.inotify.max_user_instances=8192 | sudo tee -a /etc/sysctl.conf

echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf

sudo sysctl -p

echo fs.file-max = 100000 | sudo tee -a /etc/sysctl.conf

sudo sysctl -p

az login --service-principal --username $CLIENT_ID --password $CLIENT_SECRET --tenant $TENANT

az connectedk8s connect --name $CLUSTER_NAME -l $LOCATION --resource-group $RESOURCE_GROUP --subscription $SUBSCRIPTION --enable-oidc-issuer --enable-workload-identity --disable-auto-upgrade

az connectedk8s enable-features -n $CLUSTER_NAME -g $RESOURCE_GROUP --features cluster-connect custom-locations

echo "export OIDC_ISSUER_URL=$(az connectedk8s show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --query oidcIssuerProfile.issuerUrl --output tsv)" >> ~/.bash_profile

source ~/.bash_profile

echo "kube-apiserver-arg:" >> /etc/rancher/k3s/k3s.yaml

echo "- service-account-issuer=$OIDC_ISSUER_URL >> /etc/rancher/k3s/k3s.yaml" >> /etc/rancher/k3s/k3s.yaml

echo "- service-account-max-token-expiration=24h >> /etc/rancher/k3s/k3s.yaml"

export OBJECT_ID=$(az ad sp show --id bc313c14-388c-4e7d-a58e-70017303ee3b --query id -o tsv)

echo $OBJECT_ID

echo "export OBJECT_ID=$OBJECT_ID" >> ~/.bash_profile

source ~/.bash_profile

kubectl create serviceaccount demo-user -n default

kubectl create clusterrolebinding demo-user-binding --clusterrole cluster-admin --serviceaccount default:demo-user

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: demo-user-secret
  annotations:
    kubernetes.io/service-account.name: demo-user
type: kubernetes.io/service-account-token
EOF

TOKEN=$(kubectl get secret demo-user-secret -o jsonpath='{$.data.token}' | base64 -d | sed 's/$/\n/g')

echo "export TOKEN=$TOKEN" >> ~/.bash_profile

source ~/.bash_profile

echo "**********************************************************************"
echo "*"                                                                  "*"
echo " TOKEN Para conexão com o cluster: $TOKEN"    
echo "*"                                                                  "*"
echo "**********************************************************************"

az customlocation create --name CustomLocationPetro --resource-group $RESOURCE_GROUP --namespace default --cluster-extension-ids "/subscriptions/247f1805-23e4-49df-8359-ce71728346a3/resourceGroups/rg-poc-petro/providers/Microsoft.Kubernetes/connectedClusters/cluster-poc-petro/providers/Microsoft.KubernetesConfiguration/extensions/wiextension" --location $LOCATION --host-resource-id "/subscriptions/$SUBSCRIPTION/resourceGroups/rg-poc-petro/providers/Microsoft.Kubernetes/connectedClusters/$CLUSTER_NAME" 

az k8s-extension list --cluster-name $CLUSTER_NAME --resource-group $RESOURCE_GROUP  --cluster-type connectedClusters

az connectedk8s show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --query id --output tsv

$extensionId=$(az k8s-extension show --cluster-type connectedClusters --cluster-name $CLUSTER_NAME --resource-group $RESOURCE_GROUP --name $extensionName --query id --output tsv)

az k8s-extension show --cluster-type connectedClusters --cluster-name $CLUSTER_NAME --resource-group $RESOURCE_GROUP --query id --output tsv


az iot ops create  --subscription 247f1805-23e4-49df-8359-ce71728346a3 -g rg-poc-petro --cluster cluster-poc-petro --custom-location cluster-poc-petro-cl-7325 -n cluster-poc-petro-ops-instance --sr-resource-id /subscriptions/247f1805-23e4-49df-8359-ce71728346a3/resourceGroups/rg-poc-petro/providers/Microsoft.DeviceRegistry/schemaRegistries/scr-poc-petro --broker-frontend-replicas 1 --broker-frontend-workers 1 --broker-backend-part 1 --broker-backend-workers 1  --broker-backend-rf 2 --broker-mem-profile Low
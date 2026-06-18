#!/bin/bash

###############################################################
# Autor: Thiago Bongiovani (port Ubuntu)
# Data: 29/04/2025 09:00:00
# Versão: 1.3-ubuntu
# Descrição: Script para instalar o Azure Arc em Ubuntu 22.04/24.04
#
# Variáveis de ambiente obrigatórias:
# TENANT, SUBSCRIPTION, CLIENT_ID, CLIENT_SECRET, CLUSTER_NAME, LOCATION, PREFIX, RESOURCE_GROUP, PATH_WHL_EXTENSIONS
# OFFLINE_INSTALL=true ou false
#
# Pré-requisitos: executar como root (sudo -i) em Ubuntu 22.04 ou 24.04.
###############################################################

# Evitar prompts interativos do apt durante a instalação
export DEBIAN_FRONTEND=noninteractive

###############################################################
# Definir variáveis de ambiente para o agente Copilot
###############################################################
export TENANT=""
export SUBSCRIPTION=""
export SUBSCRIPTION_ID=""
# Service Principal Application com Permissao de Application.Read.All no Microsoft Graph (para obter o OBJECT_ID necessário para custom locations) 
## e Owner no subscription scope (para criar recursos) 
export CLIENT_ID=""
export CLIENT_SECRET=""
export CLUSTER_NAME="my-edge-cluster" 
export LOCATION="southcentralus" 
export PREFIX="aiotdemo"
export RESOURCE_GROUP="rg-iot-demo"
export CUSTOM_LOCATION_NAME="CustomLocationVale"
export EXTENSION_NAME="wiextension"
export ADR_SCHEMA_REGISTRY_NAME="scr-demo-vale"
export ADR_SCHEMA_NAMESPACE="default"
export AIO_INSTANCE_NAME="cluster-demo-vale-ops-instance"
export STORAGE_ACCOUNT="saaiotdemovale001"
export STORAGE_CONTAINER_NAME="iot-ops"
export ADR_NAMESPACE_NAME="default"
export OFFLINE_INSTALL="false"
export PATH_WHL_EXTENSIONS=""

echo "Variáveis de ambiente para o agente Copilot foram definidas."

LOG_FILE="/tmp/arc_install_$(date +%Y%m%d_%H%M%S).log"
echo "✔ Atualizando lista de pacotes (apt)..." | tee -a "$LOG_FILE"
apt-get update -y >> "$LOG_FILE" 2>&1
# Pacotes mínimos exigidos pelo restante do script
apt-get install -y curl ca-certificates gnupg lsb-release apt-transport-https >> "$LOG_FILE" 2>&1

###############################################################
# Validação das variáveis de ambiente obrigatórias
required_vars=(TENANT SUBSCRIPTION SUBSCRIPTION_ID CLIENT_ID CLUSTER_NAME LOCATION RESOURCE_GROUP ADR_SCHEMA_REGISTRY_NAME ADR_SCHEMA_NAMESPACE AIO_INSTANCE_NAME STORAGE_ACCOUNT STORAGE_CONTAINER_NAME OFFLINE_INSTALL)
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Erro: Variável de ambiente $var não está definida." | tee -a "$LOG_FILE"
        exit 1
    fi
done

if [ "$OFFLINE_INSTALL" = "false" ]; then

    echo "⏳ Ajustando sincronia do clock (NTP)..." | tee -a "$LOG_FILE"
    timedatectl
    timedatectl set-ntp true
    echo "✔ Sincronia do clock (NTP) ajustado." | tee -a "$LOG_FILE"

    if command -v az &> /dev/null
    then
        echo "✔ Azure CLI já está instalado." | tee -a "$LOG_FILE"
    else
        echo "⏳ Instalando Azure CLI (instalador oficial Microsoft para Debian/Ubuntu)..." | tee -a "$LOG_FILE"
        if curl -sL https://aka.ms/InstallAzureCLIDeb | bash >> "$LOG_FILE" 2>&1; then
            echo "✔ Azure CLI instalado com sucesso." | tee -a "$LOG_FILE"
        else
            echo "X Erro ao instalar Azure CLI." | tee -a "$LOG_FILE"
            exit 1
        fi
    fi

    echo "⏳ Verificando se k3s está instalado..." | tee -a "$LOG_FILE"
    if [ -f "/usr/local/bin/k3s" ]; then
    echo "✔ K3s já está instalado." | tee -a "$LOG_FILE"
    else
    echo "⏳ Instalando k3s..." | tee -a "$LOG_FILE"
        if curl -sfL https://get.k3s.io | sh - >> "$LOG_FILE" 2>&1; then
            echo "✔ K3s instalado com sucesso." | tee -a "$LOG_FILE"
        else
            echo "X Erro ao instalar k3s." | tee -a "$LOG_FILE"
            exit 1
        fi
    fi
    # Passo separado: Instalação do kubectl
    echo "⏳ Instalando kubectl..." | tee -a "$LOG_FILE"
    if curl -LO https://dl.k8s.io/release/v1.29.3/bin/linux/amd64/kubectl >> "$LOG_FILE" 2>&1 && [ -f kubectl ]; then
        if install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl >> "$LOG_FILE" 2>&1; then
            chmod +x kubectl >> "$LOG_FILE" 2>&1
            mkdir -p ~/.local/bin >> "$LOG_FILE" 2>&1
            mv ./kubectl ~/.local/bin/kubectl >> "$LOG_FILE" 2>&1
            echo "✔ Kubectl instalado com sucesso." | tee -a "$LOG_FILE"
        else
            echo "X Erro ao instalar o binário do kubectl." | tee -a "$LOG_FILE"
            exit 1
        fi
    else
    echo "X Erro ao baixar o kubectl." | tee -a "$LOG_FILE"
        exit 1
    fi


    kubectl config use-context default >> "$LOG_FILE" 2>&1

    chmod 644 /etc/rancher/k3s/k3s.yaml >> "$LOG_FILE" 2>&1
    echo "⏳ Configurando limites do sistema..." | tee -a "$LOG_FILE"
    echo fs.inotify.max_user_instances=8192 | tee -a /etc/sysctl.conf >> "$LOG_FILE" 2>&1
    echo fs.inotify.max_user_watches=524288 | tee -a /etc/sysctl.conf >> "$LOG_FILE" 2>&1
    echo fs.file-max=100000 | tee -a /etc/sysctl.conf >> "$LOG_FILE" 2>&1
    sysctl -p >> "$LOG_FILE" 2>&1
    echo "✔ Limites do sistema configurados." | tee -a "$LOG_FILE"
    echo "⏳ Instalando K9s (.deb)..." | tee -a "$LOG_FILE"
    if curl -LO https://github.com/derailed/k9s/releases/download/v0.32.4/k9s_linux_amd64.deb >> "$LOG_FILE" 2>&1; then
        if apt-get install -y ./k9s_linux_amd64.deb >> "$LOG_FILE" 2>&1; then
            echo "✔ K9s instalado com sucesso." | tee -a "$LOG_FILE"
        else
            echo "X Erro ao instalar K9s." | tee -a "$LOG_FILE"
        fi
    else
    echo "X Erro ao baixar K9s." | tee -a "$LOG_FILE"
    fi
elif [ "$OFFLINE_INSTALL" = "true" ] && ! [ -f ~/.pip/pip.conf ]; then
    echo "⏳ Configurando pip para instalação offline..." | tee -a "$LOG_FILE"
    mkdir -p ~/.pip >> "$LOG_FILE" 2>&1
    chmod 0700 ~/.pip >> "$LOG_FILE" 2>&1
    echo "[global]" >> ~/.pip/pip.conf
    echo "disable-pip-version-check = true" >> ~/.pip/pip.conf
    echo "timeout = 60" >> ~/.pip/pip.conf
    echo "✔ Pip configurado para instalação offline." | tee -a "$LOG_FILE"
else
    echo "✔ Arquivo de configuração do pip já existe. Pulando a configuração." | tee -a "$LOG_FILE"
fi

###############################################################
# Passo separado: Configuração do kubeconfig
echo "⏳ Configurando kubeconfig como root..." | tee -a "$LOG_FILE"

echo "✔ Criando arquivo Kubeconfig em /root/.kube/config." | tee -a "$LOG_FILE"
rm -f /root/.kube/config ~/.kube/config >> "$LOG_FILE" 2>&1
mkdir -p /root/.kube >> "$LOG_FILE" 2>&1
KUBECONFIG=/root/.kube/config:/etc/rancher/k3s/k3s.yaml kubectl config view --flatten > /root/.kube/merged 2>> "$LOG_FILE"
if [ -s /root/.kube/merged ]; then
    mv /root/.kube/merged /root/.kube/config >> "$LOG_FILE" 2>&1
    chmod 0600 /root/.kube/config >> "$LOG_FILE" 2>&1
else
    echo "Arquivo merge vazio, copiando /etc/rancher/k3s/k3s.yaml para /root/.kube/config" | tee -a "$LOG_FILE"
    cp /etc/rancher/k3s/k3s.yaml /root/.kube/config >> "$LOG_FILE" 2>&1
    chmod 0600 /root/.kube/config >> "$LOG_FILE" 2>&1
fi

export KUBECONFIG=/root/.kube/config



echo "⏳ Instalando pip e jq..." | tee -a "$LOG_FILE"
if apt-get install -y python3-pip jq >> "$LOG_FILE" 2>&1; then
    echo "✔ Pip e jq instalados com sucesso." | tee -a "$LOG_FILE"
else
    echo "X Erro ao instalar pip e jq." | tee -a "$LOG_FILE"
    exit 1
fi

echo "⏳ Configurando extensões do Azure CLI..." | tee -a "$LOG_FILE"
az config set extension.use_dynamic_install=yes_without_prompt >> "$LOG_FILE" 2>&1
az config set extension.dynamic_install_allow_preview=true >> "$LOG_FILE" 2>&1

if [ "$OFFLINE_INSTALL" = "false" ]; then
    echo "⏳ Instalando extensões do Azure CLI online..." | tee -a "$LOG_FILE"
    az extension add --name azure-iot -y >> "$LOG_FILE" 2>&1
    az extension add --name azure-iot-ops -y >> "$LOG_FILE" 2>&1
    az extension add --name connectedk8s -y >> "$LOG_FILE" 2>&1
    az extension add --name k8s-extension -y >> "$LOG_FILE" 2>&1
    az extension add --name customlocation -y >> "$LOG_FILE" 2>&1
    echo "✔ Extensões do Azure CLI instaladas com sucesso." | tee -a "$LOG_FILE"
else
    echo "⏳ Instalando extensões do Azure CLI offline..." | tee -a "$LOG_FILE"
    mkdir -p "$PATH_WHL_EXTENSIONS" >> "$LOG_FILE" 2>&1
    az extension add --source "$PATH_WHL_EXTENSIONS"/azure_iot_ops*.whl -y >> "$LOG_FILE" 2>&1
    az extension add --source "$PATH_WHL_EXTENSIONS"/azure_iot-*.whl -y >> "$LOG_FILE" 2>&1
    az extension add --source "$PATH_WHL_EXTENSIONS"/connec*.whl -y >> "$LOG_FILE" 2>&1
    az extension add --source "$PATH_WHL_EXTENSIONS"/custom*.whl -y >> "$LOG_FILE" 2>&1
    az extension add --source "$PATH_WHL_EXTENSIONS"/k8s*.whl -y >> "$LOG_FILE" 2>&1
    echo "✔ Extensões do Azure CLI instaladas offline com sucesso." | tee -a "$LOG_FILE"
fi

echo "⏳ Autenticando no Azure usando Service Principal..." | tee -a "$LOG_FILE"
az account get-access-token --resource https://management.azure.com/ > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✔ Você já está logado no Azure CLI." | tee -a "$LOG_FILE"
else
    if [ "$CLIENT_SECRET" = "" ]; then
    echo "X CLIENT_SECRET não está definido. Por favor, defina-o para realizar o login." | tee -a "$LOG_FILE"
        exit 1
    else
        echo "⏳ Você não está logado no Azure CLI. Realizando login..." | tee -a "$LOG_FILE"
        if az login --service-principal --username "$CLIENT_ID" --password "$CLIENT_SECRET" --tenant "$TENANT" >> "$LOG_FILE" 2>&1; then
            echo "✔ Login realizado com sucesso." | tee -a "$LOG_FILE"
        else
            echo "X Erro ao realizar login no Azure CLI." | tee -a "$LOG_FILE"
            exit 1
        fi
    fi
fi

echo "⏳ Verificando se o cluster já está conectado ao Azure Arc..." | tee -a "$LOG_FILE"
az connectedk8s show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION" >> "$LOG_FILE" 2>&1
if [ $? -eq 0 ]; then
    echo "✔ O cluster '$CLUSTER_NAME' já está conectado ao Azure Arc." | tee -a "$LOG_FILE"
else
    echo "⏳ Conectando o cluster ao Azure Arc..." | tee -a "$LOG_FILE"
    if az connectedk8s connect --name "$CLUSTER_NAME" -l "$LOCATION" --resource-group "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION" --enable-oidc-issuer --enable-workload-identity --disable-auto-upgrade >> "$LOG_FILE" 2>&1; then
        echo "✔ Cluster conectado ao Azure Arc com sucesso." | tee -a "$LOG_FILE"
    else
        echo "X Erro ao conectar o cluster ao Azure Arc." | tee -a "$LOG_FILE"
        echo "--- Últimas 100 linhas do log ---" | tee -a "$LOG_FILE"
        tail -n 100 "$LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
    fi
fi

echo "⏳ Recuperando OIDC Issuer URL..." | tee -a "$LOG_FILE"
OIDC_ISSUER_URL=$(az connectedk8s show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --query oidcIssuerProfile.issuerUrl --output tsv 2>> "$LOG_FILE")
if [ ! -f ~/.bash_profile ] || ! grep -q "OIDC_ISSUER_URL=" ~/.bash_profile; then
    echo "export OIDC_ISSUER_URL=$OIDC_ISSUER_URL" >> ~/.bash_profile
    source ~/.bash_profile >> "$LOG_FILE" 2>&1
    echo "✔ OIDC_ISSUER_URL definido em ~/.bash_profile" | tee -a "$LOG_FILE"
else
    echo "✔ OIDC_ISSUER_URL já está definido em ~/.bash_profile" | tee -a "$LOG_FILE"
fi

echo "⏳ Configurando OIDC Issuer no k3s..." | tee -a "$LOG_FILE"
# Verificar se OIDC já está configurado
if ! grep -q "service-account-issuer=" /etc/rancher/k3s/k3s.yaml 2>/dev/null; then
    # Remove configurações antigas de OIDC se existirem
    sed -i '/^kube-apiserver-arg:/d' /etc/rancher/k3s/k3s.yaml 2>/dev/null
    sed -i '/service-account-issuer=/d' /etc/rancher/k3s/k3s.yaml 2>/dev/null
    sed -i '/service-account-max-token-expiration=/d' /etc/rancher/k3s/k3s.yaml 2>/dev/null

    # Adiciona as novas configurações
    echo "kube-apiserver-arg:" >> /etc/rancher/k3s/k3s.yaml
    echo "- service-account-issuer=$OIDC_ISSUER_URL" >> /etc/rancher/k3s/k3s.yaml
    echo "- service-account-max-token-expiration=24h" >> /etc/rancher/k3s/k3s.yaml
    echo "✔ OIDC_ISSUER_URL atualizado em /etc/rancher/k3s/k3s.yaml" | tee -a "$LOG_FILE"

    # Reinicia o k3s para aplicar as mudanças
    systemctl restart k3s >> "$LOG_FILE" 2>&1
    echo "✔ K3s reiniciado para aplicar configurações OIDC" | tee -a "$LOG_FILE"
else
    echo "✔ OIDC_ISSUER_URL já está configurado em /etc/rancher/k3s/k3s.yaml" | tee -a "$LOG_FILE"
fi

echo "⏳ Recuperando Azure AD Object ID..." | tee -a "$LOG_FILE"
OBJECT_ID=$(az ad sp show --id bc313c14-388c-4e7d-a58e-70017303ee3b --query id -o tsv 2>> "$LOG_FILE")
if [ ! -f ~/.bash_profile ] || ! grep -q "OBJECT_ID=" ~/.bash_profile; then
    echo "export OBJECT_ID=$OBJECT_ID" >> ~/.bash_profile
    source ~/.bash_profile >> "$LOG_FILE" 2>&1
    echo "✔ OBJECT_ID definido em ~/.bash_profile" | tee -a "$LOG_FILE"
else
    echo "✔ OBJECT_ID já está definido em ~/.bash_profile" | tee -a "$LOG_FILE"
fi


if kubectl get serviceaccount secrect-user -n default >> "$LOG_FILE" 2>&1; then
    # Se o código de saída for 0 (sucesso), este bloco é executado.
    echo "✔ O ServiceAccount secrect-user já existe no namespace default." | tee -a "$LOG_FILE"
else
    echo "⏳ Criando service account e role binding no Kubernetes..." | tee -a "$LOG_FILE"
    kubectl create serviceaccount secrect-user -n default >> "$LOG_FILE" 2>&1
    kubectl create clusterrolebinding secrect-user-binding --clusterrole cluster-admin --serviceaccount default:secrect-user >> "$LOG_FILE" 2>&1
    echo "⏳ Criando secret para secrect-user..." | tee -a "$LOG_FILE"
    kubectl apply -f - <<EOF >> "$LOG_FILE" 2>&1
apiVersion: v1
kind: Secret
metadata:
  name: secrect-user-secret
  annotations:
    kubernetes.io/service-account.name: secrect-user
type: kubernetes.io/service-account-token
EOF
    echo "✔ ServiceAccount e secret criados com sucesso." | tee -a "$LOG_FILE"
fi


echo "⏳ Recuperando token do secrect-user..." | tee -a "$LOG_FILE"

# Valida se o secret 'secrect-user-secret' já existe no cluster antes de recuperar o token
if ! kubectl get secret secrect-user-secret -n default >> "$LOG_FILE" 2>&1; then
    echo "X O secret 'secrect-user-secret' não existe no namespace 'default'. Não é possível recuperar o token." | tee -a "$LOG_FILE"
    exit 1
fi

# Aguarda o token ser populado no secret (o controlador pode levar alguns segundos)
TOKEN=""
for attempt in $(seq 1 12); do
    TOKEN=$(kubectl get secret secrect-user-secret -n default -o jsonpath='{.data.token}' 2>> "$LOG_FILE" | base64 -d | sed 's/$/\n/g')
    if [ -n "$TOKEN" ]; then
        break
    fi
    echo "  Tentativa $attempt/12: token ainda não disponível no secret. Aguardando..." | tee -a "$LOG_FILE"
    sleep 5
done

if [ -z "$TOKEN" ]; then
    echo "X Não foi possível recuperar o token do secret 'secrect-user-secret' (token vazio)." | tee -a "$LOG_FILE"
    exit 1
fi
echo "✔ Token do secrect-user recuperado com sucesso." | tee -a "$LOG_FILE"
if [ ! -f ~/.bash_profile ] || ! grep -q "TOKEN=" ~/.bash_profile; then
    echo "export TOKEN=$TOKEN" >> ~/.bash_profile
    source ~/.bash_profile >> "$LOG_FILE" 2>&1
    echo "✔ TOKEN definido em ~/.bash_profile" | tee -a "$LOG_FILE"
else
    echo "✔ TOKEN já está definido em ~/.bash_profile" | tee -a "$LOG_FILE"
fi

echo "**********************************************************************" | tee -a "$LOG_FILE"
echo "*                                                                    *" | tee -a "$LOG_FILE"
echo "* TOKEN para conexão com o cluster: $TOKEN" | tee -a "$LOG_FILE"
echo "*                                                                    *" | tee -a "$LOG_FILE"
echo "**********************************************************************" | tee -a "$LOG_FILE"

echo "⏳ Montando IDs dinâmicos para Custom Location..." | tee -a "$LOG_FILE"
HOST_RESOURCE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Kubernetes/connectedClusters/$CLUSTER_NAME"
CLUSTER_EXTENSION_ID=$(az k8s-extension show \
  --cluster-type connectedClusters \
  --cluster-name "$CLUSTER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --name "$EXTENSION_NAME" \
  --query id --output tsv 2>> "$LOG_FILE")

if [ -z "$CLUSTER_EXTENSION_ID" ]; then
    echo "X Não foi possível obter o cluster-extension-id da extensão '$EXTENSION_NAME'." | tee -a "$LOG_FILE"
    exit 1
fi

#az k8s-extension list --cluster-name $CLUSTER_NAME --resource-group $RESOURCE_GROUP  --cluster-type connectedClusters

#az connectedk8s show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --query id --output tsv

echo "⏳ Garantindo Storage Account com HNS habilitado..." | tee -a "$LOG_FILE"
if az storage account show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$STORAGE_ACCOUNT" \
    --subscription "$SUBSCRIPTION_ID" >> "$LOG_FILE" 2>&1; then
        echo "✔ Storage Account '$STORAGE_ACCOUNT' já existe." | tee -a "$LOG_FILE"
else
        az storage account create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$STORAGE_ACCOUNT" \
            --subscription "$SUBSCRIPTION_ID" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --hierarchical-namespace true \
            --https-only true \
            --allow-blob-public-access false \
            --min-tls-version TLS1_2 >> "$LOG_FILE" 2>&1
        if [ $? -ne 0 ]; then
                echo "X Erro ao criar Storage Account '$STORAGE_ACCOUNT'." | tee -a "$LOG_FILE"
                exit 1
        fi
        echo "✔ Storage Account '$STORAGE_ACCOUNT' criada com sucesso." | tee -a "$LOG_FILE"
fi

echo "⏳ Criando/garantindo container '$STORAGE_CONTAINER_NAME'..." | tee -a "$LOG_FILE"
STORAGE_KEY=$(az storage account keys list \
    --resource-group "$RESOURCE_GROUP" \
    --account-name "$STORAGE_ACCOUNT" \
    --subscription "$SUBSCRIPTION_ID" \
    --query "[0].value" -o tsv 2>> "$LOG_FILE")

if [ -z "$STORAGE_KEY" ]; then
        echo "X Não foi possível obter a chave da Storage Account '$STORAGE_ACCOUNT'." | tee -a "$LOG_FILE"
        exit 1
fi

az storage container create \
    --name "$STORAGE_CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$STORAGE_KEY" >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
        echo "X Erro ao criar container '$STORAGE_CONTAINER_NAME'." | tee -a "$LOG_FILE"
        exit 1
fi
echo "✔ Container '$STORAGE_CONTAINER_NAME' garantido com sucesso." | tee -a "$LOG_FILE"

STORAGE_ID=$(az storage account show \
    -g "$RESOURCE_GROUP" \
    -n "$STORAGE_ACCOUNT" \
    --subscription "$SUBSCRIPTION_ID" \
  --query id -o tsv)

echo "⏳ Verificando se Schema Registry '$ADR_SCHEMA_REGISTRY_NAME' já existe..." | tee -a "$LOG_FILE"
if az iot ops schema registry show \
    --name "$ADR_SCHEMA_REGISTRY_NAME" \
    --resource-group "$RESOURCE_GROUP" >> "$LOG_FILE" 2>&1; then
    echo "✔ Schema Registry '$ADR_SCHEMA_REGISTRY_NAME' já existe. Pulando criação." | tee -a "$LOG_FILE"
else
    echo "⏳ Criando Schema Registry '$ADR_SCHEMA_REGISTRY_NAME'..." | tee -a "$LOG_FILE"
    az iot ops schema registry create \
      --name "$ADR_SCHEMA_REGISTRY_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --registry-namespace "$ADR_SCHEMA_NAMESPACE" \
      --sa-resource-id "$STORAGE_ID"
    if [ $? -ne 0 ]; then
        echo "X Erro ao criar Schema Registry '$ADR_SCHEMA_REGISTRY_NAME'." | tee -a "$LOG_FILE"
        exit 1
    fi
    echo "✔ Schema Registry '$ADR_SCHEMA_REGISTRY_NAME' criado com sucesso." | tee -a "$LOG_FILE"
fi

ADR_SR_RESOURCE_ID=$(az iot ops schema registry show --name $ADR_SCHEMA_REGISTRY_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)

echo "⏳ Verificando se IoT Ops Namespace '$ADR_NAMESPACE_NAME' já existe..." | tee -a "$LOG_FILE"
if az iot ops ns show \
    --name "$ADR_NAMESPACE_NAME" \
    --resource-group "$RESOURCE_GROUP" >> "$LOG_FILE" 2>&1; then
    echo "✔ IoT Ops Namespace '$ADR_NAMESPACE_NAME' já existe. Pulando criação." | tee -a "$LOG_FILE"
else
    echo "⏳ Criando IoT Ops Namespace '$ADR_NAMESPACE_NAME'..." | tee -a "$LOG_FILE"
    az iot ops ns create \
       -g "$RESOURCE_GROUP" \
       -n "$ADR_NAMESPACE_NAME" \
       -l "$LOCATION"
    if [ $? -ne 0 ]; then
        echo "X Erro ao criar IoT Ops Namespace '$ADR_NAMESPACE_NAME'." | tee -a "$LOG_FILE"
        exit 1
    fi
    echo "✔ IoT Ops Namespace '$ADR_NAMESPACE_NAME' criado com sucesso." | tee -a "$LOG_FILE"
fi

ADR_NS_RESOURCE_ID=$(az iot ops ns show --name "$ADR_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)

echo "⏳ Enabling connectedk8s features (cluster-connect e custom-locations)" | tee -a "$LOG_FILE"
if [ -z "$OBJECT_ID" ]; then
    echo "X OBJECT_ID (Custom Locations OID) não está definido. Não é possível habilitar custom-locations." | tee -a "$LOG_FILE"
    exit 1
fi

az connectedk8s enable-features -n $CLUSTER_NAME -g $RESOURCE_GROUP --features cluster-connect custom-locations

az connectedk8s enable-features \
    --features cluster-connect custom-locations \
    --custom-locations-oid "$OBJECT_ID" \
    -n $CLUSTER_NAME \
    -g $RESOURCE_GROUP \
    --subscription "$SUBSCRIPTION" >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    echo "X Erro ao habilitar as features do connectedk8s (cluster-connect/custom-locations)." | tee -a "$LOG_FILE"
    exit 1
fi
echo "✔ Features cluster-connect e custom-locations habilitadas." | tee -a "$LOG_FILE"

echo "⏳ Aguardando os pods do Azure Arc ficarem prontos..." | tee -a "$LOG_FILE"
if kubectl wait --for=condition=Ready pod --all -n azure-arc --timeout=30m >> "$LOG_FILE" 2>&1; then
    echo "✔ Os pods do Azure Arc estão prontos." | tee -a "$LOG_FILE"
else
    echo "X Os pods do Azure Arc não ficaram prontos dentro do tempo esperado." | tee -a "$LOG_FILE"
    echo "--- Estado atual do namespace azure-arc ---" | tee -a "$LOG_FILE"
    kubectl get pods -n azure-arc >> "$LOG_FILE" 2>&1
    exit 1
fi

echo "⏳ Aguardando o cluster Arc reportar connectivityStatus 'Connected'..." | tee -a "$LOG_FILE"
ARC_CONNECTED=false
for attempt in $(seq 1 60); do
    CONNECTIVITY_STATUS=$(az connectedk8s show \
        --name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --subscription "$SUBSCRIPTION" \
        --query connectivityStatus -o tsv 2>> "$LOG_FILE")
    echo "  Tentativa $attempt/60: connectivityStatus='$CONNECTIVITY_STATUS'" | tee -a "$LOG_FILE"
    if [ "$CONNECTIVITY_STATUS" = "Connected" ]; then
        ARC_CONNECTED=true
        break
    fi
    sleep 30
done

if [ "$ARC_CONNECTED" = "true" ]; then
    echo "✔ O cluster Arc está 'Connected'." | tee -a "$LOG_FILE"
else
    echo "X O cluster Arc não ficou 'Connected' (último status: '$CONNECTIVITY_STATUS')." | tee -a "$LOG_FILE"
    echo "--- Diagnóstico do agente Arc ---" | tee -a "$LOG_FILE"
    kubectl get pods -n azure-arc >> "$LOG_FILE" 2>&1
    echo "Verifique: NTP/relógio do host, requisitos de rede de saída do Arc e os pods 'clusterconnect-agent'/'kube-aad-proxy'." | tee -a "$LOG_FILE"
    exit 1
fi

echo "⏳ Running iot ops init" | tee -a "$LOG_FILE"
az iot ops init --subscription $SUBSCRIPTION_ID -g $RESOURCE_GROUP --cluster $CLUSTER_NAME --check-cluster
az iot ops init --subscription $SUBSCRIPTION_ID -g $RESOURCE_GROUP --cluster $CLUSTER_NAME --debug 
echo "✔ Iot ops init executed" | tee -a "$LOG_FILE"

echo "⏳ Running iot ops create" | tee -a "$LOG_FILE"
az iot ops create  --subscription $SUBSCRIPTION_ID -g $RESOURCE_GROUP --cluster $CLUSTER_NAME --custom-location "$CUSTOM_LOCATION_NAME" -n "$AIO_INSTANCE_NAME" --sr-resource-id $ADR_SR_RESOURCE_ID --ns-resource-id $ADR_NS_RESOURCE_ID --broker-frontend-replicas 1 --broker-frontend-workers 1 --broker-backend-part 1 --broker-backend-workers 1  --broker-backend-rf 2 --broker-mem-profile Low --debug
#!/bin/bash

###############################################################
# Autor: Thiago Bongiovani
# Data: 29/04/2025 09:00:00
# Versão: 1.2
# Descrição: Script para instalar o Azure Arc no Red Hat 9.0
#
# Variáveis de ambiente obrigatórias:
# TENANT, SUBSCRIPTION, CLIENT_ID, CLIENT_SECRET, CLUSTER_NAME, LOCATION, PREFIX, RESOURCE_GROUP, PATH_WHL_EXTENSIONS
# NEXUS_URL=http://4.246.88.75:8081
# NEXUS_REPO=/repository/pypi-group/simple
# OFFLINE_INSTALL=true ou false
###############################################################

###############################################################
# Definir variáveis de ambiente para o agente Copilot
###############################################################
export TENANT="df0bdbbd-1869-4000-8422-bb40a00c140f"
export SUBSCRIPTION="ME-MngEnvMCAP312459-marcusga-1"
export SUBSCRIPTION_ID="2ae272f2-e0e3-45ad-8f99-ed177bf90937"
export CLIENT_ID="15f4e64b-71d2-4e84-ba66-6c96d9324092"
export CLIENT_SECRET="${CLIENT_SECRET:?ERROR: CLIENT_SECRET environment variable must be set}"
export CLUSTER_NAME="cluster"
export LOCATION="eastus"
export PREFIX="poc-petro"
export RESOURCE_GROUP="rg-aio"
export NEXUS_URL=""
export NEXUS_REPO=""
export OFFLINE_INSTALL="false"
export PATH_WHL_EXTENSIONS=""

echo "Variáveis de ambiente para o agente Copilot foram definidas."

LOG_FILE="/tmp/arc_install_$(date +%Y%m%d_%H%M%S).log"
echo "✔ Atualizando sistema..." | tee -a "$LOG_FILE"
yum update -y >> "$LOG_FILE" 2>&1

###############################################################
# Validação das variáveis de ambiente obrigatórias
required_vars=(TENANT SUBSCRIPTION CLIENT_ID CLUSTER_NAME LOCATION RESOURCE_GROUP OFFLINE_INSTALL)
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Erro: Variável de ambiente $var não está definida." | tee -a "$LOG_FILE"
        exit 1
    fi
done

if [ -z "$PATH_WHL_EXTENSIONS" ] && [ -z "$NEXUS_URL" ] && [ -z "$NEXUS_REPO" ] && [ "$OFFLINE_INSTALL" = "true" ]; then
    echo "Erro: NEXUS_URL e NEXUS_REPO devem estar definidos para instalação offline." | tee -a "$LOG_FILE"
    exit 1
fi

if [ "$OFFLINE_INSTALL" = "false" ]; then


    if command -v az &> /dev/null
    then
        echo "✔ Azure CLI já está instalado." | tee -a "$LOG_FILE"
    else
        echo "⏳ Instalando Azure CLI..." | tee -a "$LOG_FILE"
        rpm --import https://packages.microsoft.com/keys/microsoft.asc >> "$LOG_FILE" 2>&1
        dnf install -y https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm >> "$LOG_FILE" 2>&1
        if dnf install -y azure-cli >> "$LOG_FILE" 2>&1; then
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
    echo "⏳ Instalando K9s..." | tee -a "$LOG_FILE"
    if curl -LO https://github.com/derailed/k9s/releases/download/v0.32.4/k9s_Linux_amd64.rpm >> "$LOG_FILE" 2>&1; then
        if yum install ./k9s_Linux_amd64.rpm -y >> "$LOG_FILE" 2>&1; then
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
    echo "trusted-host = $NEXUS_URL" >> ~/.pip/pip.conf
    echo "index-url = $NEXUS_URL$NEXUS_REPO" >> ~/.pip/pip.conf
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
if dnf install -y python3-pip jq >> "$LOG_FILE" 2>&1; then
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
TOKEN=$(kubectl get secret secrect-user-secret -o jsonpath='{.data.token}' 2>> "$LOG_FILE" | base64 -d | sed 's/$/\n/g')
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
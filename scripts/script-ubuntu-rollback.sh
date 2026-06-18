#!/bin/bash

# Author: Thiago Bongiovani
# Date: 2025-08-06
# Version: 1.0
# Description: Rollback script for Azure Arc installation in Ubuntu 22.04/24.04
# This script removes all components installed by script-ubuntu-arc.sh except Azure CLI and system dependencies

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

# Evitar prompts interativos do apt/dpkg
export DEBIAN_FRONTEND=noninteractive

# Log file
LOG_FILE="/var/log/script-ubuntu-rollback.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Log de rollback salvo em $LOG_FILE"

echo "**********************************************************************"
echo "*                                                                    *"
echo "*              Azure Arc Rollback Script                            *"
echo "*              Removing all Arc components...                       *"
echo "*                                                                    *"
echo "**********************************************************************"

# Required environment variables for rollback
required_vars=(CLUSTER_NAME RESOURCE_GROUP SUBSCRIPTION)
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Error: $var environment variable is not set."
        echo "Required variables: CLUSTER_NAME, RESOURCE_GROUP, SUBSCRIPTION"
        exit 1
    fi
done

echo "⏳ Disconnecting cluster from Azure Arc..."
if az connectedk8s show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION" > /dev/null 2>&1; then
    if az connectedk8s delete --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION" --yes > /dev/null 2>&1; then
        echo "✅ Cluster disconnected from Azure Arc successfully."
    else
        echo "❌ Error disconnecting cluster from Azure Arc."
    fi
else
    echo "✅ Cluster was not connected to Azure Arc."
fi

echo "⏳ Removing Kubernetes ServiceAccount and secrets..."
if kubectl get serviceaccount secrect-user -n default > /dev/null 2>&1; then
    kubectl delete serviceaccount secrect-user -n default > /dev/null 2>&1
    echo "✅ ServiceAccount 'secrect-user' removed."
else
    echo "✅ ServiceAccount 'secrect-user' not found."
fi

if kubectl get clusterrolebinding secrect-user-binding > /dev/null 2>&1; then
    kubectl delete clusterrolebinding secrect-user-binding > /dev/null 2>&1
    echo "✅ ClusterRoleBinding 'secrect-user-binding' removed."
else
    echo "✅ ClusterRoleBinding 'secrect-user-binding' not found."
fi

if kubectl get secret secrect-user-secret -n default > /dev/null 2>&1; then
    kubectl delete secret secrect-user-secret -n default > /dev/null 2>&1
    echo "✅ Secret 'secrect-user-secret' removed."
else
    echo "✅ Secret 'secrect-user-secret' not found."
fi

echo "⏳ Removing Azure CLI extensions..."
extensions_to_remove=("azure-iot-ops" "connectedk8s" "k8s-extension" "customlocation")
for ext in "${extensions_to_remove[@]}"; do
    if az extension show --name "$ext" > /dev/null 2>&1; then
        az extension remove --name "$ext" > /dev/null 2>&1
        echo "✅ Extension '$ext' removed."
    else
        echo "✅ Extension '$ext' not installed."
    fi
done

echo "⏳ Removing Python packages..."
if pip show azure-graphrbac > /dev/null 2>&1; then
    pip uninstall azure-graphrbac -y > /dev/null 2>&1
    echo "✅ Python package 'azure-graphrbac' removed."
else
    echo "✅ Python package 'azure-graphrbac' not installed."
fi

echo "⏳ Removing kubectl..."

# Se OFFLINE_INSTALL=true, não remover k3s e kubectl
if [ "$OFFLINE_INSTALL" == "true" ]; then
    echo "OFFLINE_INSTALL=true: preservando instalação do K3s e kubectl."
else
    echo "⏳ Stopping and removing K3s..."
    if systemctl is-active --quiet k3s; then
        systemctl stop k3s > /dev/null 2>&1
        echo "✅ K3s service stopped."
    fi

    if systemctl is-enabled --quiet k3s > /dev/null 2>&1; then
        systemctl disable k3s > /dev/null 2>&1
        echo "✅ K3s service disabled."
    fi

    if [ -f "/usr/local/bin/k3s-uninstall.sh" ]; then
        /usr/local/bin/k3s-uninstall.sh > /dev/null 2>&1
        echo "✅ K3s uninstalled using official uninstall script."
    elif [ -f "/usr/local/bin/k3s" ]; then
        rm -f /usr/local/bin/k3s > /dev/null 2>&1
        echo "✅ K3s binary removed."
    fi

    echo "⏳ Removing kubectl..."
    if [ -f "/usr/local/bin/kubectl" ]; then
        rm -f /usr/local/bin/kubectl > /dev/null 2>&1
        echo "✅ kubectl removed from /usr/local/bin/"
    fi

    if [ -f "~/.local/bin/kubectl" ]; then
        rm -f ~/.local/bin/kubectl > /dev/null 2>&1
        echo "✅ kubectl removed from ~/.local/bin/"
    fi

    if [ -f "./kubectl" ]; then
        rm -f ./kubectl > /dev/null 2>&1
        echo "✅ kubectl binary removed from current directory."
    fi
fi

echo "⏳ Removing K9s..."
if dpkg -s k9s > /dev/null 2>&1; then
    apt-get remove -y k9s > /dev/null 2>&1
    echo "✅ K9s package removed."
fi

if [ -f "./k9s_linux_amd64.deb" ]; then
    rm -f ./k9s_linux_amd64.deb > /dev/null 2>&1
    echo "✅ K9s DEB file removed."
fi

echo "⏳ Removing configuration files and directories..."

# Remove kubeconfig
if [ -d "$HOME/.kube" ]; then
    rm -rf ~/.kube > /dev/null 2>&1
    echo "✅ ~/.kube directory removed."
fi

# Remove K3s configuration
if [ -d "/etc/rancher" ]; then
    rm -rf /etc/rancher > /dev/null 2>&1
    echo "✅ /etc/rancher directory removed."
fi

# Remove K3s data
if [ -d "/var/lib/rancher" ]; then
    rm -rf /var/lib/rancher > /dev/null 2>&1
    echo "✅ /var/lib/rancher directory removed."
fi

# Remove pip configuration for offline installation
if [ -f "$HOME/.pip/pip.conf" ]; then
    rm -f ~/.pip/pip.conf > /dev/null 2>&1
    echo "✅ pip configuration file removed."
fi

if [ -d "$HOME/.pip" ] && [ -z "$(ls -A ~/.pip 2>/dev/null)" ]; then
    rmdir ~/.pip > /dev/null 2>&1
    echo "✅ Empty ~/.pip directory removed."
fi

echo "⏳ Cleaning environment variables from ~/.bash_profile..."
if [ -f "$HOME/.bash_profile" ]; then
    # Create backup
    cp ~/.bash_profile ~/.bash_profile.backup.$(date +%Y%m%d_%H%M%S)
    
    # Remove Arc-related environment variables
    sed -i '/export OIDC_ISSUER_URL=/d' ~/.bash_profile
    sed -i '/export OBJECT_ID=/d' ~/.bash_profile
    sed -i '/export TOKEN=/d' ~/.bash_profile
    echo "✅ Arc-related environment variables removed from ~/.bash_profile"
    echo "✅ Backup created: ~/.bash_profile.backup.$(date +%Y%m%d_%H%M%S)"
fi

echo "⏳ Reverting system configuration changes..."

# Revert sysctl changes (restore original if backup exists)
if [ -f "/etc/sysctl.conf.backup" ]; then
    mv /etc/sysctl.conf.backup /etc/sysctl.conf > /dev/null 2>&1
    sysctl -p > /dev/null 2>&1
    echo "✅ sysctl.conf restored from backup."
else
    # Remove the specific lines we added
    sed -i '/fs.inotify.max_user_instances=8192/d' /etc/sysctl.conf
    sed -i '/fs.inotify.max_user_watches=524288/d' /etc/sysctl.conf
    sed -i '/fs.file-max=100000/d' /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
    echo "✅ Arc-related sysctl settings removed."
fi

echo "⏳ Cleaning up temporary files..."
# Remove any leftover installation files
rm -f ./kubectl > /dev/null 2>&1
rm -f ./k9s_linux_amd64.deb > /dev/null 2>&1
rm -f ./k9s_*linux_amd64* > /dev/null 2>&1

echo "⏳ Resetting Azure CLI configuration..."
az config unset extension.use_dynamic_install > /dev/null 2>&1
az config unset extension.dynamic_install_allow_preview > /dev/null 2>&1

echo "✅ Azure CLI extension configuration reset."

if systemctl list-unit-files | grep -q '^k3s\.service'; then
    systemctl restart k3s > /dev/null 2>&1 || true
    echo "✅ K3s service restarted (if present)."
fi

echo ""
echo "**********************************************************************"
echo "*                                                                    *"
echo "*                     ROLLBACK COMPLETED                            *"
echo "*                                                                    *"
echo "* The following components have been REMOVED:                       *"
echo "* - Azure Arc cluster connection                                     *"
echo "* - K3s Kubernetes cluster                                          *"
echo "* - kubectl                                                          *"
echo "* - K9s                                                              *"
echo "* - Kubernetes ServiceAccounts and secrets                          *"
echo "* - Azure CLI extensions (azure-iot-ops, connectedk8s, etc.)        *"
echo "* - Python package azure-graphrbac                                  *"
echo "* - Arc-related configuration files                                  *"
echo "* - Arc-related environment variables                               *"
echo "*                                                                    *"
echo "* The following components have been PRESERVED:                     *"
echo "* - Azure CLI                                                        *"
echo "* - System packages (python3-pip, jq)                               *"
echo "* - Base Ubuntu packages                                             *"
echo "*                                                                    *"
echo "* NOTE: You may need to restart your shell session to clear         *"
echo "* environment variables from the current session.                   *"
echo "*                                                                    *"
echo "**********************************************************************"

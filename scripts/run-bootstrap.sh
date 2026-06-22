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

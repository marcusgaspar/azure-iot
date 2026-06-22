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


  # O secret existe?
kubectl get secret acr-credentials -n flux-system

# O token está habilitado?
az acr token show --name flux-image-pull --registry aiotdemoacr \
  --query "{status:status, scopeMap:scopeMapId}" -o jsonc


ACR_NAME=aiotdemoacr
ACR_TOKEN=$(az acr token credential generate \
  --name flux-image-pull \
  --registry $ACR_NAME \
  --password1 \
  --query "passwords[0].value" -o tsv)

kubectl create secret docker-registry acr-credentials \
  --namespace flux-system \
  --docker-server=$ACR_NAME.azurecr.io \
  --docker-username=flux-image-pull \
  --docker-password="$ACR_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

flux reconcile image repository video-analytics -n flux-system

az acr scope-map show --name _repositories_pull --registry aiotdemoacr \
  --query actions -o jsonc

ACR_NAME=aiotdemoacr
ACR_TOKEN=$(az acr token credential generate \
  --name flux-image-pull --registry $ACR_NAME --password1 \
  --query "passwords[0].value" -o tsv)

kubectl create secret docker-registry acr-credentials \
  --namespace flux-system \
  --docker-server=$ACR_NAME.azurecr.io \
  --docker-username=flux-image-pull \
  --docker-password="$ACR_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

flux reconcile image repository video-analytics -n flux-system
flux get image all -A

flux get image repository video-analytics -n flux-system
kubectl describe imagerepository video-analytics -n flux-system | tail -30

az acr scope-map show --name _repositories_pull --registry aiotdemoacr \
  --query actions -o jsonc

# A) O repositório existe no ACR? (se nenhum build foi feito, ele NÃO existe)
az acr repository show-tags --name aiotdemoacr --repository video-analytics -o table

# B) O scope-map concede metadata_read?
az acr scope-map show --name _repositories_pull --registry aiotdemoacr \
  --query actions -o jsonc

# C) A credencial em si funciona? (testa o token fora do Flux)
ACR_NAME=aiotdemoacr
ACR_TOKEN=$(az acr token credential generate \
  --name flux-image-pull --registry $ACR_NAME --password1 \
  --query "passwords[0].value" -o tsv)
echo "$ACR_TOKEN" | docker login aiotdemoacr.azurecr.io -u flux-image-pull --password-stdin  


kubectl rollout restart deployment image-reflector-controller -n flux-system





ACR_NAME=aiotdemoacr

# 1) Gera UMA senha e guarda na variável
ACR_TOKEN=$(az acr token credential generate \
  --name flux-image-pull --registry $ACR_NAME --password1 \
  --query "passwords[0].value" -o tsv)

# 2) Aplica ESSA MESMA senha no secret
kubectl create secret docker-registry acr-credentials \
  --namespace flux-system \
  --docker-server=$ACR_NAME.azurecr.io \
  --docker-username=flux-image-pull \
  --docker-password="$ACR_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3) Reinicia o controller para descartar credencial em cache
kubectl rollout restart deployment image-reflector-controller -n flux-system
kubectl rollout status deployment image-reflector-controller -n flux-system

# 4) Reconcilia (NÃO rode generate/docker login depois disto)
flux reconcile image repository video-analytics -n flux-system
flux get image all -A

# Para testar sem quebrar (futuro)
TEST_TOKEN=$(az acr token credential generate \
  --name flux-image-pull --registry aiotdemoacr --password2 \
  --query "passwords[1].value" -o tsv)
echo "$TEST_TOKEN" | docker login aiotdemoacr.azurecr.io -u flux-image-pull --password-stdin



# Mensagem real do recurso
flux get image repository video-analytics -n flux-system

# Logs do controller (a verdade sobre a autenticação)
kubectl -n flux-system logs deploy/image-reflector-controller --tail=50

# Confirma que o secret no cluster bate com o token atual
kubectl -n flux-system get secret acr-credentials \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d; echo



az acr scope-map show --name _repositories_pull --registry aiotdemoacr \
  --query actions -o jsonc


ACR_NAME=aiotdemoacr

# 1) Scope-map com content/read E metadata/read no repositório
az acr scope-map create --name flux-pull --registry $ACR_NAME \
  --repository video-analytics content/read metadata/read \
  || az acr scope-map update --name flux-pull --registry $ACR_NAME \
       --add-repository video-analytics content/read metadata/read

# 2) Aponta o token para o novo scope-map
az acr token update --name flux-image-pull --registry $ACR_NAME \
  --scope-map flux-pull

# 3) Gera UMA senha nova (o scope mudou) e atualiza o secret
ACR_TOKEN=$(az acr token credential generate \
  --name flux-image-pull --registry $ACR_NAME --password1 \
  --query "passwords[0].value" -o tsv)

kubectl create secret docker-registry acr-credentials -n flux-system \
  --docker-server=$ACR_NAME.azurecr.io \
  --docker-username=flux-image-pull \
  --docker-password="$ACR_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

# 4) Reinicia o controller e reconcilia
kubectl rollout restart deployment image-reflector-controller -n flux-system
kubectl rollout status deployment image-reflector-controller -n flux-system
flux reconcile image repository video-analytics -n flux-system
flux get image all -A

az acr scope-map show --name _repositories_pull --registry aiotdemoacr --query actions -o jsonc


az acr repository show-tags --name aiotdemoacr --repository video-analytics \
  --orderby time_desc -o table

cd /home/azureadmin/azure-iot/edge/video-analytics

az acr build --registry aiotdemoacr \
  --image video-analytics:0.1.0 \
  --image video-analytics:latest \
  .

# espera o scan automático (intervalo de 1m) ou força com timeout maior
flux reconcile image repository video-analytics -n flux-system --timeout=2m
flux get image all -A


flux get all -A                                   # tudo READY=True
kubectl get pods -n video-analytics               # pod rodando
kubectl logs -n video-analytics deployment/video-analytics -f   # detecções
git -C /home/azureadmin/azure-iot log --oneline -3              # commit automático do Flux


# 1. Todos os recursos Flux READY=True
flux get all -A

# 2. Pod da aplicação rodando com a imagem 0.1.0
kubectl get pods -n video-analytics
kubectl get deployment video-analytics -n video-analytics \
  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo

# 3. Logs gerando detecções
kubectl logs -n video-analytics deployment/video-analytics --tail=20

# 4. Commit automático do Flux atualizando o deployment.yaml para 0.1.0
git -C /home/azureadmin/azure-iot log --oneline -5

# 5. Mensagens chegando no broker MQTT (demo1883)
kubectl run mqtt-sub --rm -it --restart=Never \
  -n azure-iot-operations \
  --image=eclipse-mosquitto -- \
  mosquitto_sub -h demo1883 -p 1883 -t "video-analytics/detections" -v

kubectl delete pod mqtt-sub -n azure-iot-operations --ignore-not-found



# Teste de atualização de imagem
# 1. Build com a versão (incremente o semver a cada build):
cd /home/azureadmin/azure-iot/edge/video-analytics

VERSION=0.1.1
az acr build --registry aiotdemoacr \
  --image video-analytics:$VERSION \
  --image video-analytics:latest \
  --build-arg APP_VERSION=$VERSION \
  .

# 2. Deixe o GitOps fazer o trabalho — o Flux vai detectar a tag, 
# reescrever o deployment.yaml:26 para 0.1.1, commitar no Git e reconciliar o cluster:
# acompanhe a detecção da nova imagem
flux reconcile image repository video-analytics -n flux-system --timeout=2m
flux get image policy video-analytics -n flux-system          # deve mostrar 0.1.1

# acompanhe o commit automático do Flux
git -C /home/azureadmin/azure-iot pull
git -C /home/azureadmin/azure-iot log --oneline -3

# 3. Veja a versão no log:
# acompanhe o rollout no cluster
kubectl rollout status deployment/video-analytics -n video-analytics

# Saída esperada:
# ... INFO video-analytics – Starting video analytics (simulation mode, device=edge-device-01, version=0.1.1)


# 4. Ver a versão no payload via assinante MQTT
kubectl delete pod mqtt-sub -n azure-iot-operations --ignore-not-found
kubectl run mqtt-sub --rm -it --restart=Never \
  -n azure-iot-operations \
  --image=eclipse-mosquitto -- \
  mosquitto_sub -h demo1883 -p 1883 -t "video-analytics/detections" -v
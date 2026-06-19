###############################################
# Teste na maquina local (Windows WSL2, Linux, MacOS)
###############################################
cd /mnt/c/_repo/azure-iot/video-analytics-demo/azure-iot/edge/video-analytics

# 1. Build da imagem
docker build --no-cache -t video-analytics:local .

# 2. Rodar conectando ao broker local (host.docker.internal = sua máquina)
#    Modo simulação: gera detecções aleatórias, sem necessidade de vídeo/câmera.
docker run --rm \
  -e MQTT_HOST=host.docker.internal \
  -e MQTT_PORT=1883 \
  -e DEVICE_ID=edge-device-local \
  -e LOG_LEVEL=DEBUG \
  video-analytics:local

# Teste local da aplicacao - subir o Mosquitto em outro terminal
docker run -it --rm --name mosquitto -p 1883:1883 eclipse-mosquitto

# Teste local da aplicacao - subir o Mosquitto assinando um topico para receber as mensagens em outro terminal 
docker exec -it mosquitto mosquitto_sub -t "video-analytics/detections" -v


###############################################
# Criar um Broker Listerner for LoadBalance (no TLS, no authentication)
###############################################
az login

# Criar um Broker Listerner for LoadBalance (no TLS, no authentication)
az iot ops broker listener port add \
  --resource-group rg-iot-demo \
  --instance cluster-demo-vale-ops-instance \
  --listener demo1883 \
  --service-type LoadBalancer \
  --port 1883

az iot ops broker listener list \
  -g rg-iot-demo \
  --instance cluster-demo-vale-ops-instance


###############################################
# Teste na VM edge
###############################################
git clone https://github.com/marcusgaspar/azure-iot.git
cd azure-iot/

# 1. Build e push da imagem para o ACR
# a partir da raiz do repo
cd /home/azureadmin/azure-iot/edge/video-analytics

sudo su 

# tag única para rastrear o deploy
TAG="ver-$(date +%Y%m%d-%H%M%S)"
echo $TAG

az acr build \
  --registry aiotdemoacr \
  --image video-analytics:$TAG \
  --image video-analytics:latest \
  .

# 2. Aplicar os manifestos (namespace + config + deploy + service)
kubectl apply -f /home/azureadmin/azure-iot/edge/k8s/namespace.yaml
kubectl apply -f /home/azureadmin/azure-iot/edge/k8s/video-analytics/
kubectl apply -f /home/azureadmin/azure-iot/edge/k8s/video-analytics/configmap.yaml

# 3. Criar o secret de pull do ACR (uma única vez)
# habilite o admin no ACR se ainda não estiver (ou use um service principal com AcrPull)
az acr update -n aiotdemoacr --admin-enabled true

ACR_NAME=aiotdemoacr
ACR_USER=$(az acr credential show -n $ACR_NAME --query username -o tsv)
ACR_PASS=$(az acr credential show -n $ACR_NAME --query 'passwords[0].value' -o tsv)

kubectl create secret docker-registry acr-pull-secret \
  --namespace video-analytics \
  --docker-server=$ACR_NAME.azurecr.io \
  --docker-username=$ACR_USER \
  --docker-password=$ACR_PASS \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. Apontar o Deployment para a tag desta build e reiniciar

kubectl set image deployment/video-analytics \
  video-analytics=aiotdemoacr.azurecr.io/video-analytics:$TAG \
  -n video-analytics

kubectl rollout restart deployment/video-analytics -n video-analytics

# 5. Verificar
kubectl rollout status deployment/video-analytics -n video-analytics
kubectl get pods -n video-analytics
kubectl get pods -n azure-iot-operations
kubectl logs -n video-analytics deployment/video-analytics -f
kubectl api-resources | grep -i broker
kubectl get brokerlistener -A
kubectl get brokerlistener default -n azure-iot-operations -o yaml
kubectl get svc -n azure-iot-operations
kubectl get svc -n azure-iot-operations -o wide
kubectl get brokerlistener brokerlistener -n azure-iot-operations -o yaml
kubectl get svc aio-broker -n azure-iot-operations

# Em caso de alteracoes, restart:
kubectl apply -f /home/azureadmin/azure-iot/edge/k8s/video-analytics/configmap.yaml
kubectl rollout restart deployment/video-analytics -n video-analytics
kubectl rollout status deployment/video-analytics -n video-analytics

# 6. Confirmar as mensagens MQTT no broker AIO
# assinar o tópico usando um pod temporário no namespace do broker
kubectl run mqtt-sub --rm -it --restart=Never \
  -n azure-iot-operations \
  --image=eclipse-mosquitto -- \
  mosquitto_sub -h aio-broker -p 1883 -t "video-analytics/detections" -v





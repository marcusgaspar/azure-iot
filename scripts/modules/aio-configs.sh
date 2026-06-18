# Set up a user-assigned managed identity for cloud connections
# https://learn.microsoft.com/en-us/azure/iot-operations/secure-iot-ops/howto-enable-secure-settings?tabs=bash#set-up-a-user-assigned-managed-identity-for-cloud-connections

az login
# Variable block
AIO_INSTANCE_NAME="cluster-demo-vale-ops-instance"
RESOURCE_GROUP="rg-iot-demo"
USER_ASSIGNED_MI_NAME="umi-aio-cluster-demo-vale-ops"

az extension add --name cdn

az identity create -g $RESOURCE_GROUP -n $USER_ASSIGNED_MI_NAME

#Get the resource ID of the user-assigned managed identity
USER_ASSIGNED_MI_RESOURCE_ID=$(az identity show --name $USER_ASSIGNED_MI_NAME --resource-group $RESOURCE_GROUP --query id --output tsv)

#Assign the identity to the Azure IoT Operations instance
az iot ops identity assign --name $AIO_INSTANCE_NAME --resource-group $RESOURCE_GROUP --mi-user-assigned $USER_ASSIGNED_MI_RESOURCE_ID

# Now grant Storage Blob Data Contributor role to the user-assigned managed identity on the storage account that will be used for Azure IoT Operations data storage. Replace <storage-account-name> and <storage-account-resource-group> with the appropriate values.


# K9S
# 1. Conecte na VM como root (o script roda como root)
sudo -i

# 2. Garanta o KUBECONFIG (o script já cria /root/.kube/config)
export KUBECONFIG=/root/.kube/config

# 3. Verifique se o kubectl enxerga o cluster
kubectl get nodes

# 4. Rode o k9s
k9s

Tecla	Ação
: + pods ↵	Lista pods
: + ns ↵	Troca/lista namespaces
0	Mostra todos os namespaces
d	Describe do recurso selecionado
l	Ver logs do pod
s	Shell dentro do container
Ctrl+C ou :q	Sair
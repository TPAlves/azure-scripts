#!/bin/bash
set -e

ACR_NAME="acrestudos"
AKS_NAME="aksestudos"
APPGW_NAME="appgw-estudos"
DNS_ZONE="acrestudos.com.br"
RG_NAME="rg-estudos"
RG_NAME_AKS_ADDONS="MC_rg-estudos_aksestudos_brazilsouth"
LOCATION="brazilsouth"
DESTROY_ENVIRONMENT=${1:-false}
COMMAND_TAG='az tag create --resource-id /subscriptions/$code --tags estudos=devops Status=Normal'
VINCULE_TAG='az tag add-value --name estudos --value devops --resource-id /subscriptions/$code'


replace_subscription_id() {
  CODE=$(az resource list --resource-group $RG_NAME --query "[?name=='$1'].id" -o tsv | cut -d'/' -f3)
  # Replace $code com o valor de CODE na variável COMMAND_TAG
  COMMAND_TAG=${COMMAND_TAG//\$code/$CODE}
  eval $COMMAND_TAG
  if [ $? -eq 0 ]; then
    echo "Tags adicionadas com sucesso ao recurso '$1'."
  else
    echo "Falha ao adicionar tags ao recurso '$1'."
    exit 1
  fi
}

if [ "$DESTROY_ENVIRONMENT" = true ]; then
  read -p "Tem certeza que deseja destruir o ambiente? Esta ação é irreversível! (s/n): " CONFIRM
  if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
    echo "Ação cancelada. O ambiente não será destruído."
    exit 0
  fi
  echo "Destruindo o ambiente..."
  az group delete --name $RG_NAME --yes --no-wait
  az group delete --name NetworkWatcherRG --yes --no-wait
  echo "Ambiente destruído."
  exit 0
fi

echo "Criando o grupo de recursos '$RG_NAME' na localização '$LOCATION'..."

az group create --name $RG_NAME --location $LOCATION 

if [ $? -eq 0 ]; then
  echo "Grupo de recursos '$RG_NAME' criado com sucesso."
else
  echo "Falha ao criar o grupo de recursos '$RG_NAME'."
  exit 1
fi

echo "Criando o Azure Container Registry '$ACR_NAME'..."

az acr create \
  --resource-group $RG_NAME \
  --name $ACR_NAME \
  --sku Basic \
  --admin-enabled true \
  --location $LOCATION


if [ $? -eq 0 ]; then
  echo "Azure Container Registry '$ACR_NAME' criado com sucesso."
else
  echo "Falha ao criar o Azure Container Registry '$ACR_NAME'."
  exit 1
fi

echo "Aguardando o ACR '$ACR_NAME' ficar disponível..."
sleep 30

echo "Realizando login no ACR '$ACR_NAME'..."
az acr login --name $ACR_NAME

echo "Criando o cluster AKS 'aks-estudos'..."

az aks create \
  --resource-group $RG_NAME \
  --name $AKS_NAME \
  --node-count 1 \
  --enable-managed-identity \
  --network-plugin kubenet \
  --kubernetes-version 1.30.14 \
  --dns-name-prefix $AKS_NAME \
  --load-balancer-sku standard \
  --network-policy none \
  --enable-app-routing \
  --appgw-name $APPGW_NAME \
  --appgw-subnet-cidr "10.225.0.0/24" \
  --enable-addons ingress-appgw \
  --generate-ssh-keys \
  --location $LOCATION

if [ $? -eq 0 ]; then
  echo "Cluster AKS '$AKS_NAME' criado com sucesso."
else
  echo "Falha ao criar o cluster AKS '$AKS_NAME'."
  exit 1
fi

echo "Aguardando o AKS '$AKS_NAME' ficar disponível..."
sleep 60

echo "Criando a zona DNS $DNS_ZONE"
az network dns zone create --resource-group $RG_NAME_AKS_ADDONS --name $DNS_ZONE
if [ $? -eq 0 ]; then
  echo "Zona DNS '$DNS_ZONE' criada com sucesso."
else
  echo "Falha ao criar a zona DNS '$DNS_ZONE'."
  exit 1
fi

echo "Configurando permissões do AKS para acessar o ACR e DNS..."
APPGW_IDENTITY=$(az aks show \
  --resource-group $RG_NAME \
  --name $AKS_NAME \
  --query "addonProfiles.ingressApplicationGateway.identity.objectId" \
  -o tsv)

echo "Identidade do Application Gateway: $APPGW_IDENTITY"

DNS_ZONE_ID=$(az network dns zone show -g $RG_NAME_AKS_ADDONS -n $DNS_ZONE --query "id" -o tsv)

echo "Atribuindo a função DNS Zone Contributor à identidade do Application Gateway..."
az role assignment create \
  --assignee $APPGW_IDENTITY \
  --role "DNS Zone Contributor" \
  --scope $DNS_ZONE_ID

echo "Concedendo permissão ao AKS para acessar o ACR..."
az aks update \
  --name $AKS_NAME \
  --resource-group $RG_NAME \
  --attach-acr $ACR_NAME

if [ $? -eq 0 ]; then
  echo "Permissão concedida com sucesso."
else
  echo "Falha ao conceder permissão ao AKS para acessar o ACR."
  exit 1
fi

echo "Obtendo credenciais do cluster AKS '$AKS_NAME'..."
az aks get-credentials --resource-group $RG_NAME --name $AKS_NAME | yes
if [ $? -eq 0 ]; then
  echo "Credenciais obtidas com sucesso."
else
  echo "Falha ao obter as credenciais do cluster AKS '$AKS_NAME'."
  exit 1
fi

echo "Realizando o push da imagem Docker para o ACR..."
docker push acrestudos.azurecr.io/simple-add:1.0.2

if [ $? -eq 0 ]; then
  echo "Imagem Docker enviada com sucesso para o ACR."
else
  echo "Falha ao enviar a imagem Docker para o ACR."
  exit 1
fi

echo "Adicionando tags aos recursos..."
replace_subscription_id $ACR_NAME
replace_subscription_id $AKS_NAME
replace_subscription_id $APPGW_NAME
replace_subscription_id $DNS_ZONE

echo "Ambiente criado com sucesso!"
#!/bin/bash
set -e

ACR_NAME="acrestudos"
AKS_NAME="aksestudos"
RG_NAME="rg-estudos"
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
  --node-vm-size Standard_B2s \
  --generate-ssh-keys \
  --enable-managed-identity \
  --location $LOCATION \
  --kubernetes-version 1.30.14 \
  --network-plugin kubenet

if [ $? -eq 0 ]; then
  echo "Cluster AKS '$AKS_NAME' criado com sucesso."
else
  echo "Falha ao criar o cluster AKS '$AKS_NAME'."
  exit 1
fi

echo "Aguardando o AKS '$AKS_NAME' ficar disponível..."
sleep 60

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
az aks get-credentials --resource-group $RG_NAME --name $AKS_NAME
if [ $? -eq 0 ]; then
  echo "Credenciais obtidas com sucesso."
else
  echo "Falha ao obter as credenciais do cluster AKS '$AKS_NAME'."
  exit 1
fi

echo "Adicionando tags aos recursos..."
replace_subscription_id $RG_NAME
replace_subscription_id $ACR_NAME
replace_subscription_id $AKS_NAME



echo "Ambiente criado com sucesso!"
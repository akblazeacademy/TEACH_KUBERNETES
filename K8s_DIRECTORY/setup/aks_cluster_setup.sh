#!/bin/bash
set -e

# ---------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------
RG="aks-rg"
LOCATION="centralus"
VNET_NAME="aks-vnet"
VNET_CIDR="10.0.0.0/8"
SUBNET_NAME="aks-subnet"
SUBNET_CIDR="10.240.0.0/16"

AKS_NAME="myAKSCluster"
NODE_SIZE="Standard_B2s"
NODE_COUNT=2

NODEPORT=30080
INBOUND_PUBLIC_IP_NAME="aks-nodeport-ip"

APP_NAME="nodeport-test"
IMAGE="nginx"

# ---------------------------------------------------------
# FUNCTIONS
# ---------------------------------------------------------
install_kubectl() {
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "=== kubectl not found, installing ==="
    az aks install-cli
  else
    echo "=== kubectl already installed ==="
  fi
}

# ---------------------------------------------------------
# AZURE LOGIN
# ---------------------------------------------------------
echo "=== Login to Azure ==="
az login --use-device-code

# ---------------------------------------------------------
# RESOURCE GROUP
# ---------------------------------------------------------
echo "=== Create Resource Group ==="
az group create --name $RG --location $LOCATION

# ---------------------------------------------------------
# NETWORK
# ---------------------------------------------------------
echo "=== Create VNET/Subnet ==="
az network vnet create \
  -g $RG \
  -n $VNET_NAME \
  --address-prefix $VNET_CIDR \
  --subnet-name $SUBNET_NAME \
  --subnet-prefix $SUBNET_CIDR

SUBNET_ID=$(az network vnet subnet show \
  -g $RG \
  --vnet-name $VNET_NAME \
  -n $SUBNET_NAME \
  --query id -o tsv)

# ---------------------------------------------------------
# AKS
# ---------------------------------------------------------
echo "=== Create AKS Cluster ==="
az aks create \
  -g $RG \
  -n $AKS_NAME \
  --node-count $NODE_COUNT \
  --node-vm-size $NODE_SIZE \
  --vnet-subnet-id $SUBNET_ID \
  --network-plugin azure \
  --generate-ssh-keys \
  --load-balancer-sku standard

# ---------------------------------------------------------
# KUBECTL
# ---------------------------------------------------------
install_kubectl

echo "=== Fetch kubeconfig ==="
az aks get-credentials -g $RG -n $AKS_NAME --overwrite-existing

kubectl get nodes

# ---------------------------------------------------------
# MANAGED RG
# ---------------------------------------------------------
MC_RG=$(az aks show -g $RG -n $AKS_NAME --query nodeResourceGroup -o tsv)
echo "Managed RG: $MC_RG"

# ---------------------------------------------------------
# PUBLIC IP
# ---------------------------------------------------------
echo "=== Create Public IP for NodePort ==="
az network public-ip create \
  -g $MC_RG \
  -n $INBOUND_PUBLIC_IP_NAME \
  --sku Standard \
  --allocation-method static

# ---------------------------------------------------------
# LOAD BALANCER
# ---------------------------------------------------------
LB_NAME=$(az network lb list -g $MC_RG --query "[?name=='kubernetes'].name" -o tsv)
echo "Using LB: $LB_NAME"

echo "=== Create LB Frontend ==="
az network lb frontend-ip create \
  -g $MC_RG \
  --lb-name $LB_NAME \
  -n nodeport-frontend \
  --public-ip-address $INBOUND_PUBLIC_IP_NAME

BP_NAME=$(az network lb address-pool list \
  -g $MC_RG \
  --lb-name $LB_NAME \
  --query "[0].name" -o tsv)

echo "=== Create Health Probe ==="
az network lb probe create \
  -g $MC_RG \
  --lb-name $LB_NAME \
  -n probe-$NODEPORT \
  --protocol Tcp \
  --port $NODEPORT

echo "=== Create LB Rule ==="
az network lb rule create \
  -g $MC_RG \
  --lb-name $LB_NAME \
  -n nodeport-rule-$NODEPORT \
  --protocol Tcp \
  --frontend-port $NODEPORT \
  --backend-port $NODEPORT \
  --frontend-ip-name nodeport-frontend \
  --backend-pool-name $BP_NAME \
  --probe-name probe-$NODEPORT \
  --disable-outbound-snat true

# ---------------------------------------------------------
# NSG
# ---------------------------------------------------------
NSG_NAME=$(az network nsg list -g $MC_RG --query "[0].name" -o tsv)
echo "Using NSG: $NSG_NAME"

az network nsg rule create \
  -g $MC_RG \
  --nsg-name $NSG_NAME \
  -n AllowNodePort30080 \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes Internet \
  --destination-port-ranges $NODEPORT

# ---------------------------------------------------------
# KUBERNETES APP (NO YAML)
# ---------------------------------------------------------
echo "=== Deploy App (imperative) ==="

kubectl create deployment $APP_NAME \
  --image=$IMAGE \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl expose deployment $APP_NAME \
  --name=${APP_NAME}-svc \
  --type=NodePort \
  --port=80 \
  --target-port=80 \
  --node-port=$NODEPORT \
  --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------
# FINAL INFO
# ---------------------------------------------------------
FINAL_IP=$(az network public-ip show \
  -g $MC_RG \
  -n $INBOUND_PUBLIC_IP_NAME \
  --query ipAddress -o tsv)

echo "=============================================="
echo " ✅ AKS NODEPORT SETUP COMPLETE"
echo " 🌍 Public IP : $FINAL_IP"
echo " 🔌 NodePort  : $NODEPORT"
echo " 🧪 Test: curl http://$FINAL_IP:$NODEPORT"
echo "=============================================="


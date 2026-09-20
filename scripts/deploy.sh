#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "🔎 Reading Terraform outputs..."
export AKS_RESOURCE_GROUP=$(terraform -chdir=terraform output -raw resource_group_name)
export AKS_CLUSTER_NAME=$(terraform -chdir=terraform output -raw aks_cluster_name)
STORAGE_ACCOUNT_NAME=$(terraform -chdir=terraform output -raw storage_account_name)
WI_CLIENT_ID=$(terraform -chdir=terraform output -raw workload_identity_client_id)

echo "🌐 Applying Kubernetes-native policies and storage class (via command invoke)..."
./scripts/aks-invoke.sh "kubectl apply -f k8s/storage-class-premium.yaml -f k8s/policies/"

echo "🗄️  Deploying MySQL (stateful, Premium SSD, ClusterIP only)..."
MYSQL_ROOT_PASSWORD=$(az keyvault secret show --vault-name "$(terraform -chdir=terraform output -raw key_vault_name)" --name mysql-admin-password --query value -o tsv)
./scripts/aks-invoke.sh "helm repo add bitnami https://charts.bitnami.com/bitnami && helm repo update && helm upgrade --install mysql bitnami/mysql -n data --create-namespace --values helm/mysql/values.yaml --set auth.rootPassword=${MYSQL_ROOT_PASSWORD} --set auth.password=${MYSQL_ROOT_PASSWORD} --wait --timeout 5m" helm/mysql

echo "🌐 Deploying nginx (stateless, internal LB, NetworkPolicy-restricted)..."
./scripts/aks-invoke.sh "helm upgrade --install nginx-app helm/nginx --namespace apps --create-namespace --wait --timeout 5m" helm/nginx

echo "🪪 Deploying the Workload Identity demo (replace placeholders in k8s/workload-identity-demo/*.yaml first!)..."
sed -i "s#<PASTE terraform output workload_identity_client_id HERE>#${WI_CLIENT_ID}#" k8s/workload-identity-demo/serviceaccount.yaml
sed -i "s#<PASTE terraform output storage_account_name HERE>#${STORAGE_ACCOUNT_NAME}#" k8s/workload-identity-demo/job.yaml
./scripts/aks-invoke.sh "kubectl apply -f k8s/workload-identity-demo/" k8s/workload-identity-demo

echo "✅ Deploy complete. Verify with:"
echo "   ./scripts/verify-private-access.sh"
echo "   ./scripts/verify-ledger.sh   (after you've run terraform apply for the SQL Ledger DB and worked through sql/)"

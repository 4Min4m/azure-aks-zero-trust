#!/usr/bin/env bash
# Tear down in the reverse order of deploy.sh, then destroy infra.
set -euo pipefail
cd "$(dirname "$0")/.."

export AKS_RESOURCE_GROUP=$(terraform -chdir=terraform output -raw resource_group_name)
export AKS_CLUSTER_NAME=$(terraform -chdir=terraform output -raw aks_cluster_name)

echo "🧹 Removing Kubernetes resources..."
./scripts/aks-invoke.sh "helm uninstall nginx-app -n apps || true"
./scripts/aks-invoke.sh "helm uninstall mysql -n data || true"
./scripts/aks-invoke.sh "kubectl delete -f k8s/workload-identity-demo/ || true"
./scripts/aks-invoke.sh "kubectl delete -f k8s/policies/ || true"

echo "🧨 Destroying infrastructure..."
terraform -chdir=terraform destroy
echo "✅ Cleanup complete."

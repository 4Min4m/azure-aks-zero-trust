#!/usr/bin/env bash
# Phase 1 checkpoint: prove the API server is genuinely unreachable from
# the public internet, AND that command invoke still works. Run both from
# Codespaces (which has no VNet access) to get a meaningful negative result
# on the first check.
set -uo pipefail
cd "$(dirname "$0")/.."

PRIVATE_FQDN=$(terraform -chdir=terraform output -raw aks_private_fqdn)
export AKS_RESOURCE_GROUP=$(terraform -chdir=terraform output -raw resource_group_name)
export AKS_CLUSTER_NAME=$(terraform -chdir=terraform output -raw aks_cluster_name)

echo "1) Confirming the private API server is NOT reachable from here (this SHOULD fail/time out)..."
if timeout 8 curl -sk "https://${PRIVATE_FQDN}:443" >/dev/null 2>&1; then
  echo "   ⚠️  UNEXPECTED: got a response. The cluster may not be truly private — investigate."
else
  echo "   ✅ Expected: no route to ${PRIVATE_FQDN} from Codespaces. The private endpoint has no public path."
fi

echo "2) Confirming command invoke DOES work (the intended access path)..."
./scripts/aks-invoke.sh "kubectl get nodes -o wide"
echo "   ✅ If node output printed above, the intended access path (ARM control plane, not the network path) works."

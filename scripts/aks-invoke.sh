#!/usr/bin/env bash
# Thin wrapper around `az aks command invoke` so every other script and the
# CI pipeline call the cluster the same way. See docs/access.md for why
# this exists instead of a normal kubeconfig.
set -euo pipefail

RESOURCE_GROUP="${AKS_RESOURCE_GROUP:?set AKS_RESOURCE_GROUP}"
CLUSTER_NAME="${AKS_CLUSTER_NAME:?set AKS_CLUSTER_NAME}"
COMMAND="${1:?usage: aks-invoke.sh '<kubectl/helm command>' [attach-dir]}"
ATTACH_DIR="${2:-}"

if [[ -n "$ATTACH_DIR" ]]; then
  az aks command invoke \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --command "$COMMAND" \
    --file "$ATTACH_DIR"
else
  az aks command invoke \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --command "$COMMAND"
fi

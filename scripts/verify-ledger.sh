#!/usr/bin/env bash
# Runs the full Phase 2 tamper-evidence walkthrough end-to-end using
# sqlcmd against the Ledger DB's private endpoint. Must be run from
# somewhere with network access to the VNet (a `kubectl run`-based sqlcmd
# pod via command invoke is the Codespaces-friendly way — see the
# commented alternative below — since Codespaces itself isn't VNet-peered).
set -euo pipefail
cd "$(dirname "$0")/.."

SQL_SERVER_FQDN=$(terraform -chdir=terraform output -raw sql_ledger_server_fqdn)
SQL_DB_NAME=$(terraform -chdir=terraform output -raw sql_ledger_database_name)
KEY_VAULT_NAME=$(terraform -chdir=terraform output -raw key_vault_name)
SQL_ADMIN_USER="${TF_VAR_sql_admin_username:-ztaksledgeradmin}"
SQL_ADMIN_PASSWORD=$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name sql-ledger-admin-password --query value -o tsv)

run_sql() {
  sqlcmd -S "$SQL_SERVER_FQDN" -d "$SQL_DB_NAME" -U "$SQL_ADMIN_USER" -P "$SQL_ADMIN_PASSWORD" -i "$1"
}

# --- Option A: sqlcmd installed locally in Codespaces AND you've opened a
# temporary path to the private endpoint (e.g. via a VNet-joined Codespace,
# or a short-lived jumpbox). This is the straightforward path if you have
# it; otherwise see Option B below.
echo "Running Phase 2 walkthrough against $SQL_SERVER_FQDN / $SQL_DB_NAME"
run_sql sql/01_create_ledger_table.sql
run_sql sql/02_insert_rows_and_capture_digest.sql
echo "⚠️  Manual step: copy the digest JSON printed above into sql/04_verify_clean.sql"
echo "    and sql/06_verify_with_corrupted_digest.sql (see the comments in each file), then:"
echo "    run_sql sql/04_verify_clean.sql"
echo "    run_sql sql/05_engine_level_tamper_attempt.sql   (every statement should ERROR — that's the point)"
echo "    run_sql sql/06_verify_with_corrupted_digest.sql   (should print the expected hash-mismatch error)"

# --- Option B: no direct network path from Codespaces at all. Run the same
# scripts via `az aks command invoke`, using a throwaway pod with the
# mssql-tools image inside the VNet instead of sqlcmd on your own machine:
#
#   az aks command invoke -g <rg> -n <cluster> --file sql \
#     --command "kubectl run sqlcmd --rm -it --restart=Never \
#       --image=mcr.microsoft.com/mssql-tools \
#       --overrides='{\"spec\":{\"containers\":[{\"name\":\"sqlcmd\",
#       \"image\":\"mcr.microsoft.com/mssql-tools\",
#       \"command\":[\"sleep\",\"3600\"]}]}}' -- sleep 3600"
#
# then `kubectl cp`/`kubectl exec` the sql/ files in and run sqlcmd from
# inside that pod, which IS on the VNet the private endpoint lives on.

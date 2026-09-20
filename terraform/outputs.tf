output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "aks_oidc_issuer_url" {
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
  description = "Feed this into any additional federated_identity_credential you add later."
}

output "aks_private_fqdn" {
  value       = azurerm_kubernetes_cluster.main.private_fqdn
  description = "Only resolvable from inside the VNet (or via a peered network) — not from the public internet, and not from an un-peered Codespaces box. Use `az aks command invoke` from Codespaces instead (see docs/access.md)."
}

output "sql_ledger_server_fqdn" {
  value = azurerm_mssql_server.ledger.fully_qualified_domain_name
}

output "sql_ledger_database_name" {
  value = azurerm_mssql_database.ledger.name
}

output "storage_account_name" {
  value = azurerm_storage_account.audit.name
}

output "workload_identity_client_id" {
  value       = azurerm_user_assigned_identity.workload_blob_reader.client_id
  description = "Put this in the `azure.workload.identity/client-id` annotation on the blob-reader ServiceAccount (see k8s/workload-identity-demo/serviceaccount.yaml)."
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

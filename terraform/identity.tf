# ---------------------------------------------------------------------------
# Key Vault — holds the two admin passwords so they exist in exactly one
# place outside Terraform state (state still contains them; that's why
# state must be encrypted-at-rest + access-restricted, see study guide).
# ---------------------------------------------------------------------------
resource "random_id" "kv_suffix" {
  byte_length = 3
}

resource "azurerm_key_vault" "main" {
  name                       = "kv-${var.project_prefix}-${random_id.kv_suffix.hex}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = false # demo project — flip to true for anything real
  soft_delete_retention_days = 7
  enable_rbac_authorization  = true
  public_network_access_enabled = false
  tags                       = var.tags

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-${var.project_prefix}-kv"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-kv"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.vault.id]
  }
}

resource "azurerm_private_dns_zone" "vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "vault" {
  name                  = "link-vault"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.vault.name
  virtual_network_id    = azurerm_virtual_network.main.id
}

# to write these on the first apply. Find your object id with:
#   az ad signed-in-user show --query id -o tsv
resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.allowed_object_id_for_key_vault
}

resource "azurerm_key_vault_secret" "mysql_admin_password" {
  name         = "mysql-admin-password"
  value        = var.mysql_admin_password
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.kv_admin]
}

resource "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "sql-ledger-admin-password"
  value        = var.sql_admin_password
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.kv_admin]
}

# ---------------------------------------------------------------------------
# Azure AD Workload Identity — the concrete "no static credentials" example.
#
# A pod running as ServiceAccount `blob-reader` in namespace
# `workload-identity-demo` gets a short-lived Entra ID token, federated
# against THIS identity, with zero secrets stored in the cluster.

resource "azurerm_user_assigned_identity" "workload_blob_reader" {
  name                = "id-${var.project_prefix}-blob-reader"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "blob_reader" {
  name                = "fic-blob-reader-workload-identity-demo"
  resource_group_name = azurerm_resource_group.main.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.workload_blob_reader.id
  subject             = "system:serviceaccount:workload-identity-demo:blob-reader"
}

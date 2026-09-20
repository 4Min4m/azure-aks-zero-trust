# ---------------------------------------------------------------------------
# This is the tamper-evident audit trail. `ledger_enabled = true` on the
# database turns EVERY table you create with `LEDGER = ON` into a
# cryptographically chained, append-tracked table (see sql/ for the schema
# + tamper-detection scripts). The server itself has no public endpoint;
# access is exclusively via the Private Endpoint below, from inside the VNet
# (i.e. from AKS, or from Codespaces via `az aks command invoke` /
# a temporary `az sql db` firewall rule you open and close for admin work).
# ---------------------------------------------------------------------------
resource "azurerm_mssql_server" "ledger" {
  name                         = "sql-${var.project_prefix}-ledger-${random_id.kv_suffix.hex}"
  resource_group_name         = azurerm_resource_group.main.name
  location                    = azurerm_resource_group.main.location
  version                     = "12.0"
  administrator_login         = var.sql_admin_username
  administrator_login_password = var.sql_admin_password
  minimum_tls_version         = "1.2"
  public_network_access_enabled = false
  tags                        = var.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_mssql_database" "ledger" {
  name           = "payments-audit-ledger"
  server_id      = azurerm_mssql_server.ledger.id
  sku_name       = "S0" # demo-sized; bump to a GP/BC tier for anything real
  ledger_enabled = true
  tags           = var.tags

  # The schema itself (the ledger table, columns, and history-table wiring)
  # is applied with sqlcmd from sql/01_create_ledger_table.sql, not here —
  # Terraform provisions the database, T-SQL owns what's inside it.
}

resource "azurerm_private_endpoint" "sql" {
  name                = "pe-${var.project_prefix}-sql-ledger"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-sql-ledger"
    private_connection_resource_id = azurerm_mssql_server.ledger.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.sql.id]
  }
}

# ---------------------------------------------------------------------------
# Storage Account — target for the Workload Identity demo (Phase 1, item 3)
# and, optionally, where you point Azure SQL's "automatic digest storage"
# for the Ledger. No public network access; reached only via
# Private Endpoint from inside the VNet.
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "audit" {
  name                            = "st${var.project_prefix}audit${random_id.kv_suffix.hex}"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  shared_access_key_enabled       = false # forces Entra ID auth for every client — no account keys, no connection strings
  https_traffic_only_enabled      = true
  tags                            = var.tags
}

resource "azurerm_storage_container" "audit_exports" {
  name                  = "audit-exports"
  storage_account_id   = azurerm_storage_account.audit.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "ledger_digests" {
  name                  = "ledger-digests"
  storage_account_id   = azurerm_storage_account.audit.id
  container_access_type = "private"
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-${var.project_prefix}-blob"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-blob"
    private_connection_resource_id = azurerm_storage_account.audit.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

# The Workload Identity pod (namespace workload-identity-demo, SA
# blob-reader — see k8s/workload-identity-demo/ and identity.tf) gets
# exactly this, and nothing else: read access to blobs in this one storage
# account. No account key, no secret, no connection string anywhere.
resource "azurerm_role_assignment" "workload_identity_blob_read" {
  scope                = azurerm_storage_account.audit.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.workload_blob_reader.principal_id
}

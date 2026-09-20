resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_prefix}-${var.environment}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.project_prefix}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.vnet_address_space]
  tags                = var.tags
}

# --- AKS node subnet ---
# Azure CNI Overlay means pod IPs come from an internal overlay range, NOT
# this subnet — so we don't need to size this subnet for pod density, only
# for node count. This is one of the concrete wins of overlay mode vs.
# classic Azure CNI, which reserves a pod-sized IP block per node.
resource "azurerm_subnet" "aks" {
  name                 = "snet-aks-nodes"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_cidr]
}

resource "azurerm_network_security_group" "aks" {
  name                = "nsg-aks-nodes"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  # No inbound rules from Internet at all — this is a private cluster with
  # a private API server; node-to-node and control-plane-to-node traffic is
  # handled by AKS's own required system rules, not by anything we add here.
  security_rule {
    name                       = "deny-all-inbound-internet"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# --- Private Endpoints subnet ---
# Shared by Azure SQL (Ledger) and the Storage Account. Private Endpoint
# NICs don't need their own NSG-heavy rules (traffic arriving here is
# already inside the VNet by definition), but we disable the default
# "private endpoint network policies" so NSGs *can* apply if you add them
# later — a common early gotcha.
resource "azurerm_subnet" "private_endpoints" {
  name                                          = "snet-private-endpoints"
  resource_group_name                           = azurerm_resource_group.main.name
  virtual_network_name                          = azurerm_virtual_network.main.name
  address_prefixes                              = [var.private_endpoints_subnet_cidr]
  private_endpoint_network_policies             = "Enabled"
}

# --- Private DNS zones ---
# Required so in-cluster/in-VNet clients resolve the PaaS services' normal
# hostnames (e.g. *.database.windows.net) to the private IP instead of the
# public one — otherwise "private access" is configured on the server but
# nothing actually uses it.
#
# NOTE — MySQL is deliberately NOT here: per the plan, MySQL stays an
# in-cluster stateful workload (Helm + a Premium-SSD-backed StatefulSet, see
# helm/mysql), not an Azure Database for MySQL Flexible Server. It never had
# a public Azure endpoint to begin with, so there's no Private Endpoint to
# add for it — its "Phase 1 hardening" is a ClusterIP-only Service plus a
# NetworkPolicy restricting who can reach port 3306, done in Kubernetes, not
# ARM. See docs/access.md for why that's the correct comparison to draw in
# an interview (Private Link secures a PaaS control-plane endpoint;
# NetworkPolicy secures east-west traffic inside the cluster — different
# layers, both "zero trust", easy to conflate).
resource "azurerm_private_dns_zone" "sql" {
  name                = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql" {
  name                  = "link-sql"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.sql.name
  virtual_network_id    = azurerm_virtual_network.main.id
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "link-blob"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.main.id
}

# AKS also needs to resolve its own private API server FQDN. When
# private_dns_zone_id = "System" (see aks.tf), AKS creates and links this
# zone for you automatically — nothing to declare here. Called out in the
# study guide so it isn't a mystery when you look in the portal and see a
# privatelink.<region>.azmk8s.io zone you never wrote.

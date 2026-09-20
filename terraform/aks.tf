resource "azurerm_user_assigned_identity" "aks_control_plane" {
  name                = "id-${var.project_prefix}-control-plane"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# The control-plane identity needs Network Contributor on the VNet (not the
# whole subscription) so it can wire up the private API server's NIC and the
# system-assigned "Azure Policy"/OIDC plumbing without us granting it
# Contributor at a broader scope.
resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_virtual_network.main.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_control_plane.principal_id
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${var.project_prefix}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "aks-${var.project_prefix}-${var.environment}"
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Standard" # Free tier has no uptime SLA; Standard does.

  # --- Zero-trust: no public API server at all ---
  private_cluster_enabled             = true
  private_dns_zone_id                 = "System" # let AKS manage its own private DNS zone
  private_cluster_public_fqdn_enabled = false

  # --- Identity-based, not key-based, cluster access ---
  # local_account_disabled=true removes the static admin kubeconfig
  # entirely — the only way in is Entra ID auth (interactive/device-code
  # from an authorized identity) or `az aks command invoke`, which is the
  # access path we actually use from Codespaces (see docs/access.md).
  local_account_disabled = true

  azure_active_directory_role_based_access_control {
    managed                = true
    azure_rbac_enabled     = true
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks_control_plane.id]
  }

  default_node_pool {
    name                 = "system"
    vm_size              = var.aks_node_vm_size
    node_count           = var.aks_node_count
    vnet_subnet_id       = azurerm_subnet.aks.id
    os_disk_size_gb      = 64
    type                 = "VirtualMachineScaleSets"
    only_critical_addons_enabled = false
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay" # pods get IPs from an internal overlay, not the VNet subnet
    network_policy      = "calico"  # Azure CNI Overlay supports Calico/Cilium for NetworkPolicy, not azure-npm
    load_balancer_sku   = "standard"
    outbound_type        = "userDefinedRouting" # paired with the NAT gateway below — no default public LB egress
  }

  # --- Azure AD Workload Identity ---
  # This is the AKS-side half. The other half (federated credential trusting
  # this OIDC issuer, scoped to a specific namespace/ServiceAccount) lives in
  # identity.tf, alongside the actual identities pods will impersonate.
  oidc_issuer_enabled      = true
  workload_identity_enabled = true

  # --- Azure Policy add-on (Gatekeeper under the hood) ---
  azure_policy_enabled = true

  auto_scaler_profile {
    balance_similar_node_groups = true
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      kubernetes_version, # let `az aks upgrade` or auto-upgrade own this outside Terraform
    ]
  }
}

# --- Egress path ---
# A private cluster still needs a controlled way OUT (pulling images from
# MCR/your registry, hitting the AKS API for its own control loop, etc).
# outbound_type=userDefinedRouting means WE own that path explicitly via a
# NAT Gateway, instead of relying on an implicit default outbound public IP
# (a common "private cluster" checkbox trap: the API server is private, but
# nodes still egress through an undocumented default IP).
resource "azurerm_public_ip" "nat" {
  name                = "pip-${var.project_prefix}-nat"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "main" {
  name                = "natgw-${var.project_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "aks" {
  subnet_id      = azurerm_subnet.aks.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

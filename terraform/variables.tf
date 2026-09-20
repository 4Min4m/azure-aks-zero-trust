variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "westeurope"
}

variable "environment" {
  description = "Short environment tag used in resource names (demo/dev/prod)."
  type        = string
  default     = "demo"
}

variable "project_prefix" {
  description = "Naming prefix for every resource in this project."
  type        = string
  default     = "ztaks"
}

variable "vnet_address_space" {
  description = "CIDR for the project VNet."
  type        = string
  default     = "10.20.0.0/16"
}

variable "aks_subnet_cidr" {
  description = "Subnet for AKS nodes (Azure CNI Overlay, so this only needs to fit node IPs, not pod IPs)."
  type        = string
  default     = "10.20.1.0/24"
}

variable "private_endpoints_subnet_cidr" {
  description = "Subnet dedicated to Private Endpoints (SQL, Storage)."
  type        = string
  default     = "10.20.2.0/24"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version. Leave null to track the current AKS default."
  type        = string
  default     = null
}

variable "aks_node_vm_size" {
  description = "VM size for the AKS system node pool. Kept small/cheap for a demo cluster."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "aks_node_count" {
  description = "Fixed node count for the demo (no autoscaling, to keep cost predictable)."
  type        = number
  default     = 2
}

variable "mysql_admin_username" {
  description = "Administrator login for the in-cluster MySQL Helm release (NOT the Azure SQL Ledger DB)."
  type        = string
  default     = "ztaksadmin"
}

variable "mysql_admin_password" {
  description = "Administrator password for the in-cluster MySQL Helm release. Pass via TF_VAR_mysql_admin_password / CI secret variable — never commit a real value."
  type        = string
  sensitive   = true
}

variable "sql_admin_username" {
  description = "Administrator login for the Azure SQL logical server hosting the Ledger database."
  type        = string
  default     = "ztaksledgeradmin"
}

variable "sql_admin_password" {
  description = "Administrator password for the Azure SQL logical server. Pass via TF_VAR_sql_admin_password / CI secret variable — never commit a real value."
  type        = string
  sensitive   = true
}

variable "allowed_object_id_for_key_vault" {
  description = "Entra ID object ID (your user or Codespaces service principal) allowed to read secrets in Key Vault. Find it with `az ad signed-in-user show --query id -o tsv`."
  type        = string
}

variable "tags" {
  description = "Common tags applied to every resource."
  type        = map(string)
  default = {
    project    = "zero-trust-aks-platform"
    managed_by = "terraform"
    owner      = "amin-amini"
  }
}

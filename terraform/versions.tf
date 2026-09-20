terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state: same pattern as bootstrap-your-own-backend used in the
  # AWS/GCP projects. Create this storage account + container ONCE by hand
  # (or with a tiny separate bootstrap stack) before running `terraform init`
  # here — a backend block cannot reference resources from the same run.
  #
  #   az group create -n rg-tfstate -l westeurope
  #   az storage account create -n <globally-unique-name> -g rg-tfstate --sku Standard_LRS --encryption-services blob
  #   az storage container create -n tfstate --account-name <globally-unique-name>
  #
  backend "azurerm" {
    # Fill these in (or pass via `-backend-config=` flags / a backend.hcl
    # file that you keep OUT of git) before `terraform init`:
    # resource_group_name  = "rg-tfstate"
    # storage_account_name = "<globally-unique-name>"
    # container_name       = "tfstate"
    # key                  = "zero-trust-aks.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

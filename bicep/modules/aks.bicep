@description('Location for the cluster')
param location string

@description('Naming prefix')
param projectPrefix string

@description('Environment tag')
param environment string

@description('Subnet ID for the AKS node pool')
param aksSubnetId string

@description('VM size for the system node pool')
param nodeVmSize string = 'Standard_D2s_v5'

@description('Fixed node count')
param nodeCount int = 2

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${projectPrefix}-control-plane-bicep'
  location: location
}

// Mirrors terraform/aks.tf: private cluster, no local accounts, Entra-only
// RBAC, Azure CNI Overlay + Calico, OIDC issuer + Workload Identity, Azure
// Policy add-on. Kept as close to a 1:1 translation of the Terraform
// resource as Bicep's schema allows, so the parity story is honest rather
// than "two clusters that happen to both be called AKS."
resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' = {
  name: 'aks-${projectPrefix}-${environment}'
  location: location
  sku: {
    name: 'Base'
    tier: 'Standard'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    dnsPrefix: 'aks-${projectPrefix}-${environment}'
    apiServerAccessProfile: {
      enablePrivateCluster: true
      enablePrivateClusterPublicFQDN: false
    }
    disableLocalAccounts: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    addonProfiles: {
      azurepolicy: {
        enabled: true
      }
    }
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'calico'
      loadBalancerSku: 'standard'
      outboundType: 'userDefinedRouting'
    }
    agentPoolProfiles: [
      {
        name: 'system'
        vmSize: nodeVmSize
        count: nodeCount
        vnetSubnetID: aksSubnetId
        osDiskSizeGB: 64
        mode: 'System'
        type: 'VirtualMachineScaleSets'
      }
    ]
  }
}

output clusterName string = aks.name
output oidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL

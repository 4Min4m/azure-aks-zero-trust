targetScope = 'subscription'

@description('Location for all resources')
param location string = 'westeurope'

@description('Naming prefix — use a different value than the Terraform stack to avoid name collisions if deployed side by side')
param projectPrefix string = 'ztaks-bicep'

@description('Environment tag')
param environment string = 'demo'

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-${projectPrefix}-${environment}'
  location: location
}

module network 'modules/network.bicep' = {
  name: 'networkDeployment'
  scope: rg
  params: {
    location: location
    projectPrefix: projectPrefix
  }
}

module aks 'modules/aks.bicep' = {
  name: 'aksDeployment'
  scope: rg
  params: {
    location: location
    projectPrefix: projectPrefix
    environment: environment
    aksSubnetId: network.outputs.aksSubnetId
  }
}

output resourceGroupName string = rg.name
output clusterName string = aks.outputs.clusterName

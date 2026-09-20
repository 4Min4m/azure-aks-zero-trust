@description('Location for all networking resources')
param location string

@description('Naming prefix')
param projectPrefix string

@description('VNet address space')
param vnetAddressSpace string = '10.21.0.0/16'

@description('AKS node subnet CIDR')
param aksSubnetCidr string = '10.21.1.0/24'

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-${projectPrefix}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressSpace]
    }
    subnets: [
      {
        name: 'snet-aks-nodes'
        properties: {
          addressPrefix: aksSubnetCidr
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output aksSubnetId string = vnet.properties.subnets[0].id

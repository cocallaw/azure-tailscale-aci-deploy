param hasStorageEndpoint bool
param vnetName string
param subnetName string
param addressPrefix string
param networkSecurityGroupId string
param routeTableId string
param delegations array
param privateEndpointNetworkPolicies string
param privateLinkServiceNetworkPolicies string
param updatedServiceEndpoints array
param natGatewayId string
param serviceEndpointPolicies array

resource refvnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = if (!hasStorageEndpoint) {
  name: vnetName
}

resource updatedSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = if (!hasStorageEndpoint) {
  name: subnetName
  parent: refvnet
  properties: {
    addressPrefixes: [addressPrefix]
    networkSecurityGroup: !empty(networkSecurityGroupId)
      ? {
          id: networkSecurityGroupId
        }
      : null
    routeTable: !empty(routeTableId)
      ? {
          id: routeTableId
        }
      : null
    delegations: delegations
    privateEndpointNetworkPolicies: privateEndpointNetworkPolicies
    privateLinkServiceNetworkPolicies: privateLinkServiceNetworkPolicies
    serviceEndpoints: updatedServiceEndpoints
    natGateway: !empty(natGatewayId)
      ? {
          id: natGatewayId
        }
      : null
    serviceEndpointPolicies: serviceEndpointPolicies
  }
}

output subnetUpdated bool = true

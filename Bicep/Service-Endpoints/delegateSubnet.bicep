param vnetName string
param subnetName string
param subnetAddressPrefix string
param existingDelegations array = []
param networkSecurityGroupId string = ''
param routeTableId string = ''
param serviceEndpoints array = []
param privateEndpointNetworkPolicies string = 'Enabled'
param privateLinkServiceNetworkPolicies string = 'Enabled'

var hasCIDelegation = contains(
  map(existingDelegations, d => d.properties.serviceName),
  'Microsoft.ContainerInstance/containerGroups'
)

var updatedDelegations = hasCIDelegation
  ? existingDelegations
  : concat(existingDelegations, [
      {
        name: 'Microsoft.ContainerInstance.containerGroups'
        properties: {
          serviceName: 'Microsoft.ContainerInstance/containerGroups'
        }
      }
    ])

var addressPrefixesArray = empty(subnetAddressPrefix) ? [] : [subnetAddressPrefix]
var isValidAddressPrefix = !empty(subnetAddressPrefix) && contains(subnetAddressPrefix, '/')

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = if (!hasCIDelegation && isValidAddressPrefix) {
  name: '${vnetName}/${subnetName}'
  properties: {
    addressPrefixes: addressPrefixesArray
    delegations: updatedDelegations
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
    serviceEndpoints: serviceEndpoints
    privateEndpointNetworkPolicies: privateEndpointNetworkPolicies
    privateLinkServiceNetworkPolicies: privateLinkServiceNetworkPolicies
  }
}

output subnetId string = hasCIDelegation
  ? resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
  : subnet.id
output delegationAdded bool = !hasCIDelegation

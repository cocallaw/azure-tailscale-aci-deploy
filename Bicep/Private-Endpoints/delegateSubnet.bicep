// ACI Subnet Delegation Module
param vnetName string
param subnetName string
param subnetAddressPrefix string
param existingDelegations array = []
param networkSecurityGroupId string = ''
param routeTableId string = ''
param serviceEndpoints array = []
param privateEndpointNetworkPolicies string = 'Enabled'
param privateLinkServiceNetworkPolicies string = 'Enabled'

// Check if the subnet already has the required delegation
var hasCIDelegation = contains(map(existingDelegations, d => d.properties.serviceName), 'Microsoft.ContainerInstance/containerGroups')

// If not, add it to the existing delegations
var updatedDelegations = hasCIDelegation ? existingDelegations : concat(existingDelegations, [
  {
    name: 'Microsoft.ContainerInstance.containerGroups'
    properties: {
      serviceName: 'Microsoft.ContainerInstance/containerGroups'
    }
  }
])

// Convert the address prefix string to an array for addressPrefixes property
var addressPrefixesArray = empty(subnetAddressPrefix) ? [] : [subnetAddressPrefix]

// Only update the subnet if the delegation needs to be added
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  name: '${vnetName}/${subnetName}'
  properties: {
    addressPrefixes: addressPrefixesArray
    delegations: updatedDelegations
    networkSecurityGroup: !empty(networkSecurityGroupId) ? {
      id: networkSecurityGroupId
    } : null
    routeTable: !empty(routeTableId) ? {
      id: routeTableId
    } : null
    serviceEndpoints: serviceEndpoints
    privateEndpointNetworkPolicies: privateEndpointNetworkPolicies
    privateLinkServiceNetworkPolicies: privateLinkServiceNetworkPolicies
  }
}

output subnetId string = subnet.id
output delegationAdded bool = !hasCIDelegation

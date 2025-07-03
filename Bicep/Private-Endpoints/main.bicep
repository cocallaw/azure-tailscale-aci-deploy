param location string = resourceGroup().location
@description('The name of the existing resource group where the virtual network is located')
param vnetExistingResourceGroupName string
@description('The name of the existing virtual network')
param vnetExistingName string
@description('The name of the subnet in the existing virtual network that ACI will attach to')
param aciSubnetName string
@description('The name of the subnet in the existing virtual network for Private Endpoints')
param privateEndpointSubnetName string
@minLength(3)
@maxLength(24)
@description('The name of the storage account to be created to store ACI state information')
param aciStorageAccountName string
@minLength(3)
@maxLength(63)
@description('The name of the ACI Container Group to be created')
param aciContainerGroupName string
@description('The hostname for the Tailscale instance, that Tailscale will use to identify this instance on the Tailnet')
param tailscaleHostname string = 'aztailscale'
@description('The CIDR ranges to advertise to the Tailnet')
param tailscaleAdvertiseRoutes string

@description('The Tailscale Auth Key to be used to join the ACI instance to the Tailnet')
@secure()
param tailscaleAuthKey string

@description('Size of the ACI container to deploy')
@allowed([
  'Small'
  'Medium'
  'Large'
])
param containerSize string = 'Small'

@description('Use custom ACR instead of public GHCR image')
param useCustomAcr bool = false

@description('ACR repository (only used if useCustomAcr is true)')
param acrRepository string = ''

@description('ACR image tag (only used if useCustomAcr is true)')
param acrImageTag string = 'latest'

@description('ACR username (only used if useCustomAcr is true)')
param acrUsername string = ''

@secure()
@description('ACR password (only used if useCustomAcr is true)')
param acrPassword string = ''

param resourceTags object = {
  createdBy: 'Bicep'
  createdOn: utcNow()
}

var fileShareName = 'tailscale-data'
var ghcrImage = 'ghcr.io/cocallaw/tailscale-sr:latest'
var imageReference = useCustomAcr ? '${acrRepository}:${acrImageTag}' : ghcrImage
var containersizeReference = containersizeList[containerSize]
var containersizeList = {
  Small: {
    memoryInGB: 1
    cpu: 1
  }
  Medium: {
    memoryInGB: 2
    cpu: 2
  }
  Large: {
    memoryInGB: 4
    cpu: 4
  }
}

// Get the storage environment suffix for the current cloud
var storageEnvironmentSuffix = environment().suffixes.storage
var privateDnsZoneName = 'privatelink.file.${storageEnvironmentSuffix}'

// Reference existing virtual network
resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: vnetExistingName
  scope: resourceGroup(vnetExistingResourceGroupName)
}

// Reference existing subnet for ACI
resource aciSubnetResource 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' existing = {
  name: aciSubnetName
  parent: vnet
}

// Reference existing subnet for Private Endpoint
resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' existing = {
  name: privateEndpointSubnetName
  parent: vnet
}

// Create storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: aciStorageAccountName
  location: location
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
    accessTier: 'Hot'
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
    dnsEndpointType: 'Standard'
    encryption: {
      keySource: 'Microsoft.Storage'
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
        table: {
          enabled: true
        }
        queue: {
          enabled: true
        }
      }
      requireInfrastructureEncryption: false
    }
  }
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  tags: resourceTags
}

// Create file services
resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2024-01-01' = {
  name: 'default'
  parent: storageAccount
}

// Create file share
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2024-01-01' = {
  parent: fileServices
  name: fileShareName
}

// Create Private DNS Zone for Azure Files
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: resourceTags
}

// Link Private DNS Zone to VNet
resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: '${privateDnsZone.name}-link'
  parent: privateDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
  tags: resourceTags
}

// Create Private Endpoint for File Storage
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: '${aciStorageAccountName}-pe'
  location: location
  tags: resourceTags
  properties: {
    privateLinkServiceConnections: [
      {
        name: '${aciStorageAccountName}-plsc'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
    subnet: {
      id: privateEndpointSubnet.id
    }
  }
}

// Create DNS Zone Group for Private Endpoint
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  name: 'default'
  parent: privateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// Create the ACI Container Group
resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2024-10-01-preview' = {
  name: aciContainerGroupName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: 'Standard'
    containers: [
      {
        name: 'tailscaleaci'
        properties: {
          image: imageReference
          command: []
          ports: [
            {
              protocol: 'TCP'
              port: 443
            }
          ]
          environmentVariables: [
            {
              name: 'TAILSCALE_HOSTNAME'
              value: tailscaleHostname
            }
            {
              name: 'TAILSCALE_ADVERTISE_ROUTES'
              value: tailscaleAdvertiseRoutes
            }
            {
              name: 'TAILSCALE_AUTH_KEY'
              secureValue: tailscaleAuthKey
            }
            {
              name: 'DEBUG'
              value: 'true'
            }
          ]
          resources: {
            requests: containersizeReference
          }
          volumeMounts: [
            {
              name: 'tailscale-volume'
              mountPath: '/var/lib/tailscale'
              readOnly: false
            }
          ]
          livenessProbe: {
            exec: {
              command: ['/bin/sh', '-c', 'tailscale status || exit 1']
            }
            initialDelaySeconds: 60 // Wait 60s after container starts before first probe
            periodSeconds: 30 // Check every 30s thereafter
            failureThreshold: 3 // Restart after 3 consecutive failures
            successThreshold: 1 // One success to be considered healthy
            timeoutSeconds: 10 // Each probe has 10s to complete
          }
        }
      }
    ]
    imageRegistryCredentials: useCustomAcr
      ? [
          {
            server: first(split(acrRepository, '/'))
            username: acrUsername
            password: acrPassword
          }
        ]
      : []
    restartPolicy: 'Always'
    ipAddress: {
      ports: [
        {
          protocol: 'TCP'
          port: 443
        }
      ]
      type: 'Private'
    }
    subnetIds: [
      {
        id: delegateAciSubnet.outputs.subnetId
      }
    ]
    osType: 'Linux'
    volumes: [
      {
        name: 'tailscale-volume'
        azureFile: {
          readOnly: false
          shareName: fileShareName
          storageAccountKey: listKeys(aciStorageAccountName, '2024-01-01').keys[0].value
          storageAccountName: aciStorageAccountName
        }
      }
    ]
  }
  dependsOn: [
    fileShare
    privateEndpoint
    privateDnsZoneGroup
  ]
}

// Add Container Instance delegation to ACI subnet using a module
module delegateAciSubnet 'delegateSubnet.bicep' = {
  name: 'delegateAciSubnet'
  scope: resourceGroup(vnetExistingResourceGroupName)
  params: {
    vnetName: vnetExistingName
    subnetName: aciSubnetName
    subnetAddressPrefix: contains(aciSubnetResource.properties, 'addressPrefixes') && length(aciSubnetResource.properties.addressPrefixes) > 0
      ? aciSubnetResource.properties.addressPrefixes[0]
      : (aciSubnetResource.properties.?addressPrefix ?? '')
    existingDelegations: aciSubnetResource.properties.?delegations ?? []
    networkSecurityGroupId: contains(aciSubnetResource.properties, 'networkSecurityGroup')
      ? (aciSubnetResource.properties.networkSecurityGroup.id ?? '')
      : ''
    routeTableId: contains(aciSubnetResource.properties, 'routeTable')
      ? (aciSubnetResource.properties.routeTable.id ?? '')
      : ''
    serviceEndpoints: aciSubnetResource.properties.?serviceEndpoints ?? []
    privateEndpointNetworkPolicies: aciSubnetResource.properties.?privateEndpointNetworkPolicies ?? 'Enabled'
    privateLinkServiceNetworkPolicies: aciSubnetResource.properties.?privateLinkServiceNetworkPolicies ?? 'Enabled'
  }
}

// Add outputs for the deployed resources
output containerGroupId string = containerGroup.id
output storageAccountId string = storageAccount.id
output privateEndpointId string = privateEndpoint.id
output fileShareName string = fileShare.name
output delegationAdded bool = delegateAciSubnet.outputs.delegationAdded
output aciSubnetId string = delegateAciSubnet.outputs.subnetId

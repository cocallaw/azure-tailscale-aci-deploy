param region string = resourceGroup().location
param vnetExistingName string
param vnetExistingSubnet string
param aciStorageAccountName string
param aciContainerGroupName string
param tailscaleHoasname string = 'tailscale'
param tailscaleAdvertiseRoutes string

@secure()
param tailscaleAuthKey string

@description('Size of the ACI container to deploy')
@allowed([
  'Small'
  'Medium'
  'Large'
])
param containerSize string = 'Small'

@description('Selecting DockerHub will pull the Tailscale image from hub.docker.com/r/cocallaw/tailscale-sr.')
@allowed([
  'DockerHub'
  'ACR'
])
param containerRegistry string = 'DockerHub'

@description('If DockerHub is selcted as the Container Registry, leave as default value or empty')
param tailscaleImageRepository string = 'myacr.azurecr.io/tailscale'

@description('If DockerHub is selcted as the Container Registry, leave as default value or empty')
param tailscaleImageTag string = 'latest'

@description('If DockerHub is selcted as the Container Registry, leave as default value or empty')
param tailscaleRegistryUsername string = ''

@description('If DockerHub is selcted as the Container Registry, leave as default value or empty')
@secure()
param tailscaleRegistryPassword string = ''

var dh_image = 'cocallaw/tailscale-sr:latest'
var acr_image = '${tailscaleImageRepository}:${tailscaleImageTag}'
var tailscale_image_server = first(split(tailscaleImageRepository, '/'))
var registry_refrence = registry_list[containerRegistry]
var registry_list = {
  DockerHub: []
  ACR: {
    server: tailscale_image_server
    username: tailscaleRegistryUsername
    password: tailscaleRegistryPassword
  }
}
var image_refrence = image_list[containerRegistry]
var image_list = {
  DockerHub: dh_image
  ACR: acr_image
}
var containersize_refrence = containersize_list[containerSize]
var containersize_list = {
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

resource aciContainerGroupName_resource 'Microsoft.ContainerInstance/containerGroups@2021-10-01' = {
  name: aciContainerGroupName
  location: region
  identity: {
    type: 'None'
  }
  properties: {
    sku: 'Standard'
    containers: [
      {
        name: 'tailscaleaci'
        properties: {
          image: image_refrence
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
              value: tailscaleHoasname
            }
            {
              name: 'TAILSCALE_ADVERTISE_ROUTES'
              value: tailscaleAdvertiseRoutes
            }
            {
              name: 'TAILSCALE_AUTH_KEY'
              secureValue: tailscaleAuthKey
            }
          ]
          resources: {
            requests: containersize_refrence
          }
          volumeMounts: [
            {
              name: 'tailscale-volume'
              mountPath: '/var/lib/tailscale'
              readOnly: false
            }
          ]
        }
      }
    ]
    imageRegistryCredentials: registry_refrence
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
        id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetExistingName, vnetExistingSubnet)
      }
    ]
    osType: 'Linux'
    volumes: [
      {
        name: 'tailscale-volume'
        azureFile: {
          readOnly: false
          shareName: 'tailscale-data'
          storageAccountKey: listKeys(aciStorageAccountName, '2021-06-01').keys[0].value
          storageAccountName: aciStorageAccountName
        }
      }
    ]
  }
  dependsOn: [
    aciStorageAccountName_resource
  ]
}

resource aciStorageAccountName_resource 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: aciStorageAccountName
  location: region
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  properties: {
    allowCrossTenantReplication: true
    isNfsV3Enabled: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    isHnsEnabled: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

resource aciStorageAccountName_default_tailscale_data 'Microsoft.Storage/storageAccounts/fileServices/shares@2022-05-01' = {
  name: '${aciStorageAccountName}/default/tailscale-data'
  dependsOn: [
    aciStorageAccountName_resource
  ]
}

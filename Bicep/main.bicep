param vnetExistingName string
param vnetExistingSubnet string
param aciStorageAccountName string
param aciContainerGroupName string
param tailscaleImageRepository string = 'myacr.azurecr.io/tailscale'
param tailscaleImageTag string = 'latest'
param tailscaleHoasname string = 'tailscale'
param tailscaleAdvertiseRoutes string
param tailscaleRegistryUsername string

@secure()
param tailscaleAuthKey string

@secure()
param tailscaleRegistryPassword string

var aci_image = '${tailscaleImageRepository}:${tailscaleImageTag}'
var tailscale_image_server = first(split(tailscaleImageRepository, '/'))

resource aciContainerGroupName_resource 'Microsoft.ContainerInstance/containerGroups@2021-10-01' = {
  name: aciContainerGroupName
  location: resourceGroup().location
  identity: {
    type: 'None'
  }
  properties: {
    sku: 'Standard'
    containers: [
      {
        name: 'tailscaleaci'
        properties: {
          image: aci_image
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
            requests: {
              memoryInGB: 1
              cpu: 1
            }
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
    initContainers: []
    imageRegistryCredentials: [
      {
        server: tailscale_image_server
        username: tailscaleRegistryUsername
        password: tailscaleRegistryPassword
      }
    ]
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
  location: resourceGroup().location
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
      virtualNetworkRules: []
      ipRules: []
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

resource aciStorageAccount_tailscale_data_share 'Microsoft.Storage/storageAccounts/fileServices/shares@2021-09-01' = {
  name: '${aciStorageAccountName}/default/tailscale-data'
  dependsOn: [
    aciStorageAccountName_resource
  ]
}

@description('Name of the VNet')
param virtualNetworkName string = 'appservice-vnet'

@description('Name of the Web Farm')
param serverFarmName string = 'appserviceplan'

@description('Web App 1 name must be unique DNS name worldwide')
param site1_Name string = 'webapp-api-${uniqueString(resourceGroup().id)}'

@description('Web App 2 name must be unique DNS name worldwide')
param site2_Name string = 'webapp-front-${uniqueString(resourceGroup().id)}'

@description('CIDR of your VNet')
param virtualNetwork_CIDR string = '10.200.0.0/16'

@description('Name of the subnet')
param subnet1Name string = 'web-pe'

@description('Name of the subnet')
param subnet2Name string = 'web-out'

@description('CIDR of your subnet')
param subnet1_CIDR string = '10.200.1.0/24'

@description('CIDR of your subnet')
param subnet2_CIDR string = '10.200.2.0/24'

@description('Location for all resources.')
param location string = resourceGroup().location

param skuName string = 'S1'
param skuSize string = 'S1'
param skuFamily string = 'S'
param SKU_tier string = 'Standard'

@description('Name of your Private Endpoint')
param privateEndpointName string = 'webapp-api-pe'

@description('Link name between your Private Endpoint and your Web App')
param privateLinkConnectionName string = 'webapp-api-pe-plink'

var webapp_dns_name = '.azurewebsites.net'
var privateDNSZoneName = 'privatelink.azurewebsites.net'

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetwork_CIDR
      ]
    }
    subnets: [
      {
        name: subnet1Name
        properties: {
          addressPrefix: subnet1_CIDR
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
      {
        name: subnet2Name
        properties: {
          addressPrefix: subnet2_CIDR
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverfarms'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

resource serverFarm 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: serverFarmName
  location: location
  sku: {
    name: skuName
    tier: SKU_tier
    size: skuSize
    family: skuFamily
    capacity: 1
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

// API
resource webApp1 'Microsoft.Web/sites@2022-03-01' = {
  name: site1_Name
  location: location
  kind: 'app,linux,container'
  properties: {
    serverFarmId: serverFarm.id
    httpsOnly: true
    vnetRouteAllEnabled: true
    virtualNetworkSubnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, subnet2Name)
    siteConfig: {
      ftpsState: 'FtpsOnly'
      linuxFxVersion: 'DOCKER|docker.io/erjosito/yadaapi:1.0'
      appSettings: [
        {
          name: 'PORT'
          value: '443'
        }
      ]
    }
  }
}

// Web frontend
resource webApp2 'Microsoft.Web/sites@2022-03-01' = {
  name: site2_Name
  location: location
  kind: 'app,linux,container'
  properties: {
    serverFarmId: serverFarm.id
    httpsOnly: true
    vnetRouteAllEnabled: true
    virtualNetworkSubnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, subnet2Name)
    siteConfig: {
      ftpsState: 'FtpsOnly'
      linuxFxVersion: 'DOCKER|docker.io/erjosito/yadaweb:1.0'
      appSettings: [
        {
          name: 'API_URL'
          value: 'https://${webApp1.name}${webapp_dns_name}'
        }
      ]
    }
  }
}

resource webApp1Binding 'Microsoft.Web/sites/hostNameBindings@2022-03-01' = {
  parent: webApp1
  name: '${webApp1.name}${webapp_dns_name}'
  properties: {
    siteName: webApp1.name
    hostNameType: 'Verified'
  }
}

resource webApp2Binding 'Microsoft.Web/sites/hostNameBindings@2022-03-01' = {
  parent: webApp2
  name: '${webApp2.name}${webapp_dns_name}'
  properties: {
    siteName: webApp2.name
    hostNameType: 'Verified'
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2022-05-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, subnet1Name)
    }
    privateLinkServiceConnections: [
      {
        name: privateLinkConnectionName
        properties: {
          privateLinkServiceId: webApp1.id
          groupIds: [
            'sites'
          ]
        }
      }
    ]
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = {
  parent: privateEndpoint
  name: 'dnsgroupname'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: privateDnsZones.id
        }
      }
    ]
  }
}

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDNSZoneName
  location: 'global'
  dependsOn: [
    virtualNetwork
  ]
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZones
  name: '${privateDnsZones.name}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

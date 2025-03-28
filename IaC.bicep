@description('Resource prefix for all resources')
param prefix string = 'myapp'

@description('Location for all resources')
param location string = resourceGroup().location

@description('The container image tag to use from ACR')
param imageTag string = 'latest'

@description('The number of CPU cores for the container')
param cpuCores int = 1

@description('Memory (GB) for the container')
param memoryInGb int = 2

@description('Restart policy')
@allowed(['Always', 'Never', 'OnFailure'])
param restartPolicy string = 'Always'


resource acr 'Microsoft.ContainerRegistry/registries@2021-09-01' = {
  name: format('{0}acr', prefix)  // ✅ Correcte manier om een variabele in een string te gebruiken
  location: location
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: true }
}

var acrLoginServer = acr.properties.loginServer

// 🔹 2. Virtual Network (VNet) + Subnet
resource vnet 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: '${prefix}VNet'
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.0.0.0/16'] }
    subnets: [
      {
        name: 'mySubnet'
        properties: { addressPrefix: '10.0.1.0/24' }
      }
    ]
  }
}

// 🔹 3. Public IP Address
resource publicIP 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: '${prefix}PublicIP'
  location: location
  properties: { publicIPAllocationMethod: 'Static' }
}

// 🔹 4. Network Security Group (NSG) – Alleen HTTP (80) toestaan
resource nsg 'Microsoft.Network/networkSecurityGroups@2021-02-01' = {
  name: '${prefix}NSG'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allowHttp'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// 🔹 5. Log Analytics voor monitoring
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: '${prefix}LogAnalytics'
  location: location
  properties: { sku: { name: 'PerGB2018' } }
}

// 🔹 6. Azure Container Instance (ACI) met ACR als Image Source
resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: '${prefix}ContainerGroup'
  location: location
  properties: {
    containers: [
      {
        name: '${prefix}Container'
        properties: {
          image: '${acrLoginServer}/myimage:${imageTag}'  // 📌 Haalt altijd de nieuwste image uit ACR
          ports: [{ port: 80, protocol: 'TCP' }]
          resources: { requests: { cpu: cpuCores, memoryInGB: memoryInGb } }
        }
      }
    ]
    osType: 'Linux'
    restartPolicy: restartPolicy
    ipAddress: {
      type: 'Public'
      dnsNameLabel: '${prefix}app'
      ports: [{ port: 80, protocol: 'TCP' }]
    }
    subnetIds: [vnet.properties.subnets[0].id]
    diagnostics: { logAnalytics: { workspaceId: logAnalytics.id } }
    imageRegistryCredentials: [{
      server: acrLoginServer
      username: acr.name
      password: acr.listCredentials().passwords[0].value
    }]
  }
}

// 🔹 Outputs
output acrLoginServer string = acrLoginServer
output containerIPv4Address string = containerGroup.properties.ipAddress.ip
output publicIP string = publicIP.properties.ipAddress

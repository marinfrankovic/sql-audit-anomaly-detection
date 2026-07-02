// Windows Server 2022 VM running SQL Server 2022 Developer edition (marketplace image,
// SQL pre-installed = no license cost). Includes VNet, NSG, Public IP and NIC.
// The Azure Monitor Agent + Data Collection Rule are attached by monitoring.bicep.
@description('VM name (<=15 chars for Windows).')
@maxLength(15)
param vmName string
@description('Location.')
param location string
@description('Tags.')
param tags object
@description('Local admin username.')
param adminUsername string
@secure()
@description('Local admin password.')
param adminPassword string
@description('VM size. v2 B-series (v1 B-series is not available in Sweden Central).')
param vmSize string = 'Standard_B4s_v2'
@description('Optional client IP allowed to RDP / connect to SQL. Empty = allow from VirtualNetwork only.')
param clientIpAddress string = ''

var vnetName = 'vnet-sqlpoc'
var subnetName = 'snet-sql'
var nsgName = 'nsg-sqlpoc'
var pipName = 'pip-sqlpoc'
var nicName = 'nic-sqlpoc'
// If a client IP is supplied, lock RDP/SQL to it; otherwise use Internet (demo convenience).
var mgmtSource = empty(clientIpAddress) ? 'Internet' : clientIpAddress

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: mgmtSource
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'Allow-SQL'
        properties: {
          priority: 1010
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: mgmtSource
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '1433'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.42.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.42.1.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: pipName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: toLower('${vmName}-${uniqueString(resourceGroup().id)}')
    }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${vnet.id}/subnets/${subnetName}'
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        // SQL Server 2022 Developer edition on Windows Server 2022 — SQL pre-installed.
        publisher: 'MicrosoftSQLServer'
        offer: 'sql2022-ws2022'
        sku: 'sqldev-gen2'
        version: 'latest'
      }
      osDisk: {
        name: '${vmName}-osdisk'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

// Note: the optional Microsoft.SqlVirtualMachine (SQL IaaS Agent) resource is intentionally
// NOT deployed. SQL Server is already installed from the marketplace image, and the IaaS Agent
// registration rejects a 'DR' license for Developer edition (requires PAYG). It adds no value
// for this PoC, so it is omitted to keep the deployment simple and policy-friendly.

output vmName string = vm.name
output vmId string = vm.id
output publicIp string = publicIp.properties.ipAddress
output fqdn string = publicIp.properties.dnsSettings.fqdn
output principalId string = vm.identity.principalId

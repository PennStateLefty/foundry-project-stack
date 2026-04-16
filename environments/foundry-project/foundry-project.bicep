// ---------------------------------------------------------------------------
// Module: Create a Foundry Project under an existing Foundry Account
// ---------------------------------------------------------------------------
// This module is scoped to the resource group containing the Foundry account.
// Called from main.bicep which handles the cross-RG scoping.
// ---------------------------------------------------------------------------

@description('Name of the existing Foundry account.')
param foundryAccountName string

@description('Name for the Foundry Project.')
@minLength(2)
@maxLength(64)
param projectName string

@description('Azure region. Must match the Foundry account location.')
param location string

@description('Display name for the project.')
param displayName string

@description('Description for the project.')
param projectDescription string

// Reference the existing Foundry account in this resource group
resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

// Foundry Project — child of the existing account
resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundryAccount
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: displayName
    description: projectDescription
  }
}

// Outputs
output projectResourceId string = foundryProject.id
output projectNameOutput string = foundryProject.name
output projectPrincipalId string = foundryProject.identity.principalId

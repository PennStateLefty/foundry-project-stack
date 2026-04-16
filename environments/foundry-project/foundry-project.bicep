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

@description('Object ID (principal ID) of the developer to grant Azure AI User on the project.')
param developerPrincipalId string

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

// Grant the developer Azure AI User on the Foundry Project
var azureAiUserRoleId = '53ca6127-db72-4b80-b1b0-d745d6d5456d'

resource aiUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundryProject.id, developerPrincipalId, azureAiUserRoleId)
  scope: foundryProject
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureAiUserRoleId)
    principalId: developerPrincipalId
    principalType: 'User'
  }
}

// Outputs
output projectResourceId string = foundryProject.id
output projectNameOutput string = foundryProject.name
output projectPrincipalId string = foundryProject.identity.principalId

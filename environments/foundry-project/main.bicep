// ---------------------------------------------------------------------------
// ADE Catalog Item: Foundry Project under an existing Foundry Account
// ---------------------------------------------------------------------------
// This Bicep template creates a Microsoft Foundry Project as a child resource
// of an existing Foundry account (Microsoft.CognitiveServices/accounts with
// kind: AIServices). It also grants the requesting developer the Azure AI User
// role on the project for portal and data-plane access.
//
// Resource model: New Foundry (Ignite 2025 / CognitiveServices-based)
//   Parent:  Microsoft.CognitiveServices/accounts  (kind: AIServices)
//   Child:   Microsoft.CognitiveServices/accounts/projects
//
// Designed for use as an Azure Deployment Environments catalog item.
// ---------------------------------------------------------------------------

targetScope = 'resourceGroup'

// === Parameters =============================================================

@description('Name of the existing Foundry account (CognitiveServices/accounts resource).')
param foundryAccountName string

@description('Name for the Foundry Project (2-64 chars, alphanumeric + . - _).')
@minLength(2)
@maxLength(64)
param projectName string

@description('Azure region. Must match the Foundry account location.')
param location string = resourceGroup().location

@description('Object (principal) ID of the developer who will own this project.')
param developerPrincipalId string

@description('Optional display name for the project in the Foundry portal.')
param displayName string = projectName

@description('Optional description for the project.')
param projectDescription string = 'Self-service Foundry Project provisioned via Azure Deployment Environments.'

// === Variables ==============================================================

// Azure AI User — grants reader access to the project + data actions
var azureAiUserRoleId = '53ca6127-db72-4b80-b1b0-d745d6d5456d'

// === Resources ==============================================================

// Reference the existing Foundry account (parent)
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

// Role Assignment — Azure AI User on the project for the developer
resource aiUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundryProject.id, developerPrincipalId, azureAiUserRoleId)
  scope: foundryProject
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureAiUserRoleId)
    principalId: developerPrincipalId
    principalType: 'User'
  }
}

// === Outputs ================================================================

@description('Resource ID of the created Foundry Project.')
output projectResourceId string = foundryProject.id

@description('Name of the created Foundry Project.')
output projectNameOutput string = foundryProject.name

@description('System-assigned managed identity principal ID of the project.')
output projectPrincipalId string = foundryProject.identity.principalId

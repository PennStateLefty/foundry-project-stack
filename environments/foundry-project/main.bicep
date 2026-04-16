// ---------------------------------------------------------------------------
// ADE Catalog Item: Foundry Project under an existing Foundry Account
// ---------------------------------------------------------------------------
// ADE always creates a new resource group per environment, but the Foundry
// Project must be a child of the existing Foundry account (in its own RG).
// This entry point uses a module scoped to the Foundry account's RG.
//
// IMPORTANT: ADE TTL will delete the ADE-created (empty) RG, but NOT the
// Foundry Project in the Foundry account's RG. See README for cleanup options.
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

@description('Resource group containing the existing Foundry account.')
param foundryAccountResourceGroup string

@description('Name for the Foundry Project (2-64 chars, alphanumeric + . - _).')
@minLength(2)
@maxLength(64)
param projectName string

@description('Azure region. Must match the Foundry account location.')
param location string

@description('Optional display name for the project in the Foundry portal.')
param displayName string = projectName

@description('Optional description for the project.')
param projectDescription string = 'Self-service Foundry Project provisioned via Azure Deployment Environments.'

@description('Object ID of the developer. Auto-populated by ADE from the requesting user context.')
param developerPrincipalId string

// === Module: Deploy project into the Foundry account's resource group ========

module foundryProjectModule 'foundry-project.bicep' = {
  name: 'deploy-foundry-project-${projectName}'
  scope: resourceGroup(foundryAccountResourceGroup)
  params: {
    foundryAccountName: foundryAccountName
    projectName: projectName
    location: location
    displayName: displayName
    projectDescription: projectDescription
    developerPrincipalId: developerPrincipalId
  }
}

// === Outputs ================================================================

@description('Resource ID of the created Foundry Project.')
output projectResourceId string = foundryProjectModule.outputs.projectResourceId

@description('Name of the created Foundry Project.')
output projectNameOutput string = foundryProjectModule.outputs.projectNameOutput

@description('System-assigned managed identity principal ID of the project.')
output projectPrincipalId string = foundryProjectModule.outputs.projectPrincipalId

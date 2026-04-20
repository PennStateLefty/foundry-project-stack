---
layout: page
title: "ADE Setup Guide"
---

# Azure Deployment Environments — Setup Guide

> Step-by-step instructions for deploying the ADE-based Foundry Project
> self-service prototype. For architecture context and trade-offs, see
> [ADE Approach](ade-approach.md).

## Prerequisites

### Existing Infrastructure

1. **Azure Deployment Environments Dev Center** — already provisioned
2. **ADE Dev Center Project** — already created within the Dev Center
3. **Foundry Account** — an existing `Microsoft.CognitiveServices/accounts`
   resource with `kind: AIServices` and `allowProjectManagement: true`

### Understanding the Identity Model

ADE has **three distinct identities** that need permissions. Getting this wrong
was the #1 source of deployment failures during prototyping.

| Identity | Where to Find | What It Does |
|----------|---------------|--------------|
| **Dev Center MI** | Dev Center resource → Identity | Manages catalogs and environment orchestration |
| **ADE Project MI** | Not directly visible; inherited from Dev Center | Project-level operations |
| **Environment Type MI** | ADE Project → Environment Types → [type] → Identity | **Actually executes ARM deployments** |

> **The Environment Type's managed identity is the one that runs your Bicep
> template.** This is the identity that needs deployment permissions.

## Step 1: Grant RBAC Permissions

### Environment Type MI → Foundry Account Resource Group

| Role | Why |
|------|-----|
| **Contributor** | Create Foundry Projects and ARM deployments in the target RG |
| **User Access Administrator** | Create role assignments on the Foundry Project for Azure AI User |

```bash
# Get the Environment Type MI's object ID from the Azure Portal
# or via REST API:
az rest --method GET \
  --url "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.DevCenter/projects/<project>/environmentTypes/<type>?api-version=2025-04-01-preview" \
  --query "identity.principalId" -o tsv

# Assign Contributor on the Foundry account's RG:
az role assignment create \
  --assignee-object-id <environment-type-mi-object-id> \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "/subscriptions/<sub>/resourceGroups/<foundry-rg>"

# Assign User Access Administrator (for RBAC on the Foundry Project):
az role assignment create \
  --assignee-object-id <environment-type-mi-object-id> \
  --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" \
  --scope "/subscriptions/<sub>/resourceGroups/<foundry-rg>"
```

### Dev Center MI → Target Subscription

| Role | Why |
|------|-----|
| **Owner** | ADE pre-flight validation checks the Dev Center identity |
| **User Access Administrator** | Required if Bicep includes role assignments |

> **Note:** The Dev Center MI needs these even if the Bicep doesn't create role
> assignments — ADE performs a pre-flight permission check. During prototyping,
> we had to grant Owner + User Access Administrator at the **subscription level**
> to pass this check.

```bash
# Get the Dev Center MI's object ID:
az rest --method GET \
  --url "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.DevCenter/devcenters/<devcenter>?api-version=2025-04-01-preview" \
  --query "identity.principalId" -o tsv

# Assign Owner on the subscription:
az role assignment create \
  --assignee-object-id <devcenter-mi-object-id> \
  --assignee-principal-type ServicePrincipal \
  --role "Owner" \
  --scope "/subscriptions/<sub>"
```

## Step 2: Attach the GitHub Catalog

1. Navigate to your **Dev Center** in the Azure Portal
2. Go to **Catalogs** → **Add**
3. Select **GitHub** as the source
4. Install the **Microsoft Dev Center** GitHub App when prompted
   - Grant access to the repository containing this code
5. Set the **path** to `/environments`
6. Sync the catalog — the `foundry-project` item should appear

> **Naming constraint:** The `name` field in `environment.yaml` must use
> URL-safe characters (lowercase, hyphens, 3-63 chars). Spaces and
> uppercase will cause catalog sync errors.

## Step 3: Configure the Environment Type

1. In your **ADE Project**, go to **Environment Types**
2. Create or edit an environment type (e.g., "Sandbox")
3. Set the **deployment identity** — use a system-assigned managed identity
4. Set the **deployment subscription** to the subscription containing the
   Foundry account
5. Ensure the role assignments from Step 1 are in place

> **Note:** ADE always creates a **new resource group** per environment — there
> is no option to deploy into an existing RG. The Bicep template uses a cross-RG
> module to work around this. See [ADE Approach — Limitations](ade-approach.md).

## Step 4: Create an Environment (Developer Portal)

1. Go to the [ADE Developer Portal](https://devportal.microsoft.com)
2. Select your project → **New Environment**
3. Choose the **`foundry-project`** catalog item
4. Fill in the parameters:

| Parameter | Description | Example |
|-----------|-------------|---------|
| `foundryAccountName` | Name of the existing Foundry account | `foundry-deployment-env-test` |
| `foundryAccountResourceGroup` | RG where the Foundry account lives | `rg-dev-center-foundry` |
| `projectName` | Unique name for your project (2-64 chars) | `my-team-project` |
| `location` | Azure region matching the Foundry account | `eastus2` |
| `developerPrincipalId` | Your Entra Object ID | `abcd1234-...` |
| `displayName` | *(Optional)* Friendly name in Foundry portal | `My Team's Sandbox` |
| `projectDescription` | *(Optional)* Description of the project | `GPT-4o testing` |

> **Finding your Object ID:** Azure Portal → Entra ID → Users → your profile →
> Object ID. Copy the GUID.

5. *(Optional)* Toggle **"Enable scheduled deletion"** and set an expiration
   date/time for TTL
6. Click **Create**

## Step 5: Validate

- [ ] Deployment succeeds (check ADE portal or Activity Log)
- [ ] A new Foundry Project appears under the Foundry account in the Azure Portal
- [ ] The developer can access the project in the [Foundry portal](https://ai.azure.com)

## Template Details

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `foundryAccountName` | Yes | Name of the existing Foundry account |
| `foundryAccountResourceGroup` | Yes | Resource group containing the Foundry account |
| `projectName` | Yes | Name for the new Foundry Project (2-64 chars) |
| `location` | Yes | Azure region (must match the Foundry account) |
| `displayName` | No | Friendly name shown in the Foundry portal |
| `projectDescription` | No | Description of the project |
| `developerPrincipalId` | Yes | Developer's Entra Object ID (for Azure AI User role) |

### Resources Created

| Resource | Type | Location |
|----------|------|----------|
| Foundry Project | `Microsoft.CognitiveServices/accounts/projects` | Foundry account's RG (cross-RG) |
| Role Assignment | `Microsoft.Authorization/roleAssignments` | Scoped to the Foundry Project (Azure AI User) |

### Outputs

| Output | Description |
|--------|-------------|
| `projectResourceId` | Full ARM resource ID of the project |
| `projectNameOutput` | Name of the project |
| `projectPrincipalId` | System-assigned managed identity principal ID |

## Manual Cleanup

ADE TTL only deletes the ADE-created (empty) RG. To delete the Foundry Project:

```bash
# Delete the ADE environment (only deletes the empty RG)
az devcenter dev environment delete \
  --dev-center-name <dev-center> \
  --project-name <ade-project> \
  --name <environment-name> \
  --user-id "me"

# Delete the Foundry Project directly (required for cross-RG cleanup)
az resource delete \
  --ids "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<account>/projects/<project>"
```

## Troubleshooting

### Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Authorization failed for Microsoft.Resources/deployments/write` | Environment Type MI lacks Contributor on target RG | Grant Contributor on the Foundry account's RG |
| `Authorization failed for Microsoft.CognitiveServices/accounts/projects/write` | Same as above | Same fix |
| `Authorization failed for Microsoft.Authorization/roleAssignments/write` | Environment Type MI lacks User Access Administrator | Grant UAA on the Foundry account's RG |
| Pre-flight validation fails even with correct permissions | Dev Center MI doesn't have subscription-level Owner | Grant Owner + UAA to Dev Center MI at subscription scope |
| Catalog sync error on item name | `name` in environment.yaml contains spaces or uppercase | Use lowercase, hyphens, 3-63 chars |
| Location mismatch error | Project location doesn't match parent account | Use the same region as the Foundry account |
| `${{ AZURE_ENV_CREATOR_PRINCIPAL_ID }}` passed as literal string | Built-in Bicep runner doesn't support variable injection | Require developer to provide Object ID manually |

### Tips

- **Environment expiration (TTL)** is set per environment at creation time, not
  as a blanket policy. Developers toggle "Enable scheduled deletion" in the Dev
  Portal.
- **Name reuse** — verify that Foundry Projects don't have a soft-delete
  retention period blocking name reuse after deletion.
- **Production enhancement:** Use a
  [custom ADE runner](https://learn.microsoft.com/en-us/azure/deployment-environments/how-to-configure-extensibility-generic-container-image)
  to inject `AZURE_ENV_CREATOR_PRINCIPAL_ID` automatically.

---

[← ADE Approach](ade-approach.md) | [GitHub Actions Setup](github-actions-alternative.md) | [Comparison](comparison.md)

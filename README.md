# Foundry Project Self-Service via Azure Deployment Environments

> **Prototype / Proof of Concept**
>
> Can a developer use the Azure Deployment Environments (ADE) developer portal
> to self-service create a Foundry Project under an existing Foundry account —
> with automatic cleanup via ADE's TTL (time-to-live) policy?

## What This Proves

| Question | Answer |
|----------|--------|
| Can Bicep create a Foundry Project under an existing account? | Yes — `Microsoft.CognitiveServices/accounts/projects` is a standard ARM child resource. |
| Can ADE catalog items deploy Foundry Projects? | Yes — ADE supports any valid Bicep template in its catalog. |
| Does the developer portal surface the parameters? | Yes — `environment.yaml` parameter definitions render as form fields. |
| Does ADE TTL auto-delete the Foundry Project? | **To be validated** — this is the core hypothesis. |

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Azure Deployment Environments (ADE)            │
│                                                 │
│  Dev Center ─► ADE Project ─► Environment Type  │
│                    │             (TTL policy)    │
│                    ▼                             │
│              GitHub Catalog                      │
│              └── environments/                   │
│                  └── foundry-project/            │
│                      ├── environment.yaml        │
│                      └── main.bicep              │
└─────────────────────────────────────────────────┘
                     │
                     │  Developer clicks "Create Environment"
                     │  in the ADE Developer Portal
                     ▼
┌─────────────────────────────────────────────────┐
│  Existing Foundry Account                       │
│  (Microsoft.CognitiveServices/accounts)         │
│  kind: AIServices                               │
│                                                 │
│  └── New Foundry Project  ◄── created by Bicep  │
│      (accounts/projects)                        │
│      + Azure AI User role for the developer     │
└─────────────────────────────────────────────────┘
```

## Prerequisites

### Existing Infrastructure

1. **Azure Deployment Environments Dev Center** — already provisioned.
2. **ADE Dev Center Project** — already created within the Dev Center.
3. **Foundry Account** — an existing `Microsoft.CognitiveServices/accounts`
   resource with `kind: AIServices` and `allowProjectManagement: true`.

### Permissions

The ADE deployment identity (managed identity assigned to the environment type)
must have the following permissions on the **resource group** containing the
Foundry account:

| Permission | Why |
|------------|-----|
| `Microsoft.CognitiveServices/accounts/projects/write` | Create the project |
| `Microsoft.CognitiveServices/accounts/projects/delete` | TTL cleanup |
| `Microsoft.CognitiveServices/accounts/read` | Reference the existing account |
| `Microsoft.Authorization/roleAssignments/write` | Assign Azure AI User to the developer |

> **Tip:** The **Contributor** + **User Access Administrator** built-in roles
> on the resource group cover all of the above.

## Setup

### 1. Attach the GitHub Catalog to the Dev Center

1. Navigate to your **Dev Center** in the Azure Portal.
2. Go to **Catalogs** → **Add**.
3. Select **GitHub** as the source.
4. Point to this repository and set the **path** to `/environments`.
5. Sync the catalog. The "Foundry Project" item should appear.

### 2. Configure the Environment Type

1. In your **ADE Project**, go to **Environment Types**.
2. Create or edit an environment type (e.g., "Foundry-Dev").
3. Set the **deployment identity** (managed identity with the permissions above).
4. Set the **deployment subscription** and **resource group** where the Foundry
   account lives.

### 3. Configure TTL Policy

1. On the environment type, set the **Expiration policy**:
   - **Maximum environment lifetime** — e.g., 7 days, 30 days.
   - **Action on expiration** — Delete.
2. This ensures the Foundry Project (and its role assignments) are automatically
   removed when the TTL expires.

## Testing

### Create an Environment (Developer Portal)

1. Go to the [ADE Developer Portal](https://devportal.microsoft.com).
2. Select your project → **New Environment**.
3. Choose the **"Foundry Project"** catalog item.
4. Fill in the parameters:
   - `foundryAccountName` — name of the existing Foundry account.
   - `projectName` — a unique name for your project.
   - `developerPrincipalId` — your Azure AD Object ID.
5. Click **Create**.

### Validate

- [ ] The deployment succeeds (check ADE portal or Activity Log).
- [ ] A new Foundry Project appears under the Foundry account in the Azure Portal.
- [ ] The developer can access the project in the [Foundry portal](https://ai.azure.com).
- [ ] The Azure AI User role is assigned on the project.
- [ ] After TTL expiry (or manual deletion), the project and role assignment are removed.
- [ ] The project name can be reused after deletion.

### Manual Cleanup (if needed)

```bash
# Delete the ADE environment (triggers ARM cleanup)
az devcenter dev environment delete \
  --dev-center-name <dev-center> \
  --project-name <ade-project> \
  --name <environment-name> \
  --user-id "me"

# Or delete the Foundry project directly
az resource delete \
  --ids "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<account>/projects/<project>"
```

## Template Details

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `foundryAccountName` | Yes | Name of the existing Foundry account |
| `projectName` | Yes | Name for the new Foundry Project (2-64 chars) |
| `developerPrincipalId` | Yes | Azure AD Object ID of the developer |
| `location` | No | Azure region (defaults to resource group location) |
| `displayName` | No | Friendly name shown in the Foundry portal |
| `projectDescription` | No | Description of the project |

### Resources Created

| Resource | Type |
|----------|------|
| Foundry Project | `Microsoft.CognitiveServices/accounts/projects` |
| Azure AI User role assignment | `Microsoft.Authorization/roleAssignments` |

### Outputs

| Output | Description |
|--------|-------------|
| `projectResourceId` | Full ARM resource ID of the project |
| `projectNameOutput` | Name of the project |
| `projectPrincipalId` | System-assigned managed identity principal ID |

## Known Risks & Limitations

### TTL Deletion Behavior (Core Hypothesis)

ADE TTL deletes the environment, which typically means deleting the resource
group or the individual resources deployed by the template. The key question is
whether `Microsoft.CognitiveServices/accounts/projects` supports clean ARM
DELETE without affecting the parent Foundry account. **This is the primary thing
the prototype validates.**

### Developer Principal ID

ADE does not automatically inject the requesting user's principal ID into
template parameters. For this prototype, the developer must provide their own
Object ID. In a production implementation, this could be solved by:

- A custom ADE extensibility runner that injects the principal ID.
- A wrapper script or Azure Function that resolves the user identity.
- Using ADE's built-in environment variables (if/when supported).

### Location Mismatch

The project location must match the parent Foundry account's location. The
template defaults to the resource group location, which may not match. Ensure
the environment type's target resource group is in the same region as the
Foundry account.

### Name Reuse After Deletion

Verify that Foundry Projects (CognitiveServices/accounts/projects) do not have
a soft-delete retention period that blocks name reuse. This is less likely than
with ML workspaces but should be confirmed.

## File Structure

```
foundry-project-stack/
├── README.md                            # This file
├── .gitignore
└── environments/
    └── foundry-project/
        ├── environment.yaml             # ADE catalog manifest
        └── main.bicep                   # Bicep template
```

## References

- [Azure Deployment Environments documentation](https://learn.microsoft.com/en-us/azure/deployment-environments/)
- [ADE environment.yaml schema](https://learn.microsoft.com/en-us/azure/deployment-environments/concept-environment-yaml)
- [Microsoft.CognitiveServices/accounts/projects Bicep reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts/projects)
- [Azure AI Foundry documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/)
- [Azure AI User role](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#azure-ai-user)

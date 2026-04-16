# Foundry Project Self-Service via Azure Deployment Environments

> **Prototype / Proof of Concept — Validated ✅**
>
> Can a developer use the Azure Deployment Environments (ADE) developer portal
> to self-service create a Foundry Project under an existing Foundry account?

## What This Proves

| Question | Answer |
|----------|--------|
| Can Bicep create a Foundry Project under an existing account? | ✅ Yes — `Microsoft.CognitiveServices/accounts/projects` is a standard ARM child resource. |
| Can ADE catalog items deploy Foundry Projects? | ✅ Yes — ADE supports any valid Bicep template in its catalog. |
| Does the developer portal surface the parameters? | ✅ Yes — `environment.yaml` parameter definitions render as form fields. |
| Can ADE deploy cross-RG into the Foundry account's RG? | ✅ Yes — using a Bicep module scoped to the target RG. |
| Does ADE TTL auto-delete the Foundry Project? | ⚠️ No — ADE TTL only deletes the ADE-created RG, not cross-RG resources. See [TTL Limitation](#ttl-limitation). |

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Azure Deployment Environments (ADE)                │
│                                                     │
│  Dev Center ─► ADE Project ─► Environment Type      │
│                    │           (Sandbox)             │
│                    ▼                                 │
│              GitHub Catalog                          │
│              └── environments/foundry-project/       │
│                  ├── environment.yaml                │
│                  ├── main.bicep  (entry, cross-RG)   │
│                  └── foundry-project.bicep (module)  │
└─────────────────────────────────────────────────────┘
          │                              │
          │ ADE creates a new            │ Bicep module deploys
          │ (empty) RG per env           │ into existing RG
          ▼                              ▼
┌──────────────────┐    ┌─────────────────────────────────┐
│  ADE-created RG  │    │  Foundry Account RG              │
│  (empty, TTL     │    │  (rg-dev-center-foundry)         │
│   deletes this)  │    │                                  │
└──────────────────┘    │  Foundry Account                 │
                        │  (Microsoft.CognitiveServices/   │
                        │   accounts, kind: AIServices)    │
                        │                                  │
                        │  └── New Foundry Project  ◄───── │
                        │      (accounts/projects)         │
                        └─────────────────────────────────┘
```

## Prerequisites

### Existing Infrastructure

1. **Azure Deployment Environments Dev Center** — already provisioned.
2. **ADE Dev Center Project** — already created within the Dev Center.
3. **Foundry Account** — an existing `Microsoft.CognitiveServices/accounts`
   resource with `kind: AIServices` and `allowProjectManagement: true`.

### Permissions (Critical — Read Carefully)

ADE has **three distinct identities** that need permissions. Getting this wrong
was the #1 source of deployment failures during prototyping.

#### Identity Model

| Identity | Where to Find | What It Does |
|----------|---------------|--------------|
| **Dev Center MI** | Dev Center resource → Identity | Manages catalogs and environment orchestration |
| **ADE Project MI** | Not directly visible; inherited from Dev Center | Project-level operations |
| **Environment Type MI** | ADE Project → Environment Types → [type] → Identity | **Actually executes ARM deployments** |

> **The Environment Type's managed identity is the one that runs your Bicep
> template.** This is the identity that needs deployment permissions.

#### Required Role Assignments

**1. Environment Type MI → on the Foundry account's resource group:**

| Role | Why |
|------|-----|
| **Contributor** | Create Foundry Projects (`Microsoft.CognitiveServices/accounts/projects/write`) and ARM deployments (`Microsoft.Resources/deployments/write`) in the target RG |

```bash
# Get the Environment Type MI's object ID from:
# Azure Portal → ADE Project → Environment Types → [type] → Identity
# Or via REST API:
az rest --method GET \
  --url "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.DevCenter/projects/<project>/environmentTypes/<type>?api-version=2025-04-01-preview" \
  --query "identity.principalId" -o tsv

# Then assign Contributor on the Foundry account's RG:
az role assignment create \
  --assignee-object-id <environment-type-mi-object-id> \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "/subscriptions/<sub>/resourceGroups/<foundry-rg>"
```

**2. Dev Center MI → on the target subscription:**

| Role | Why |
|------|-----|
| **Owner** | ADE pre-flight validation checks the Dev Center identity for role assignment capabilities |
| **User Access Administrator** | Required if your Bicep includes `Microsoft.Authorization/roleAssignments` resources |

> **Note:** The Dev Center MI needs these even if the Bicep doesn't create role
> assignments — ADE performs a pre-flight permission check. During prototyping,
> we had to grant Owner + User Access Administrator at the subscription level
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

## Setup

### 1. Attach the GitHub Catalog to the Dev Center

1. Navigate to your **Dev Center** in the Azure Portal.
2. Go to **Catalogs** → **Add**.
3. Select **GitHub** as the source.
4. You'll be prompted to install the **Microsoft Dev Center** GitHub App.
   - Install it on your GitHub account/org.
   - Grant access to the repository containing this code.
5. Set the **path** to `/environments`.
6. Sync the catalog. The `foundry-project` item should appear.

> **Naming constraint:** The `name` field in `environment.yaml` must use
> URL-safe characters (lowercase, hyphens, 3-63 chars). Spaces and
> uppercase will cause catalog sync errors.

### 2. Configure the Environment Type

1. In your **ADE Project**, go to **Environment Types**.
2. Create or edit an environment type (e.g., "Sandbox").
3. Set the **deployment identity** — use a system-assigned managed identity.
4. Set the **deployment subscription** to the subscription containing the
   Foundry account.
5. Ensure the role assignments described above are in place.

> **Note:** ADE always creates a **new resource group** per environment — there
> is no option to deploy into an existing RG via the portal or CLI. The Bicep
> template uses a cross-RG module to deploy the Foundry Project into the
> Foundry account's existing RG. See [TTL Limitation](#ttl-limitation).

### 3. Environment Expiration (TTL)

TTL is configured **per environment at creation time**, not as a blanket policy
on the Environment Type.

- **At creation:** In the developer portal, toggle **"Enable scheduled deletion"**
  and set an expiration date/time.
- **After creation:** Developers can adjust the expiration on their environment
  in the developer portal settings.
- **Admin override:** Project Admins can manage deletion schedules for any
  environment in the Azure Portal under **ADE Project → Environments**.

## Testing

### Create an Environment (Developer Portal)

1. Go to the [ADE Developer Portal](https://devportal.microsoft.com).
2. Select your project → **New Environment**.
3. Choose the **`foundry-project`** catalog item.
4. Fill in the parameters:
   - `foundryAccountName` — name of the existing Foundry account.
   - `foundryAccountResourceGroup` — RG where the Foundry account lives.
   - `projectName` — a unique name for your project.
   - `location` — Azure region matching the Foundry account (e.g., `eastus2`).
5. Click **Create**.

### Validate

- [x] The deployment succeeds (check ADE portal or Activity Log).
- [ ] A new Foundry Project appears under the Foundry account in the Azure Portal.
- [ ] The developer can access the project in the [Foundry portal](https://ai.azure.com).
- [ ] After manual deletion of the ADE environment, the project is cleaned up.
- [ ] The project name can be reused after deletion.

### Manual Cleanup (if needed)

```bash
# Delete the ADE environment (only deletes the ADE-created empty RG)
az devcenter dev environment delete \
  --dev-center-name <dev-center> \
  --project-name <ade-project> \
  --name <environment-name> \
  --user-id "me"

# Delete the Foundry project directly (required for cross-RG cleanup)
az resource delete \
  --ids "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<account>/projects/<project>"
```

## Template Details

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `foundryAccountName` | Yes | Name of the existing Foundry account |
| `foundryAccountResourceGroup` | Yes | Resource group containing the Foundry account |
| `projectName` | Yes | Name for the new Foundry Project (2-64 chars) |
| `location` | Yes | Azure region (must match the Foundry account location) |
| `displayName` | No | Friendly name shown in the Foundry portal |
| `projectDescription` | No | Description of the project |

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

## Known Risks & Limitations

### TTL Limitation

ADE always creates a **new resource group** per environment — there is no option
to deploy into an existing RG (confirmed via REST API and CLI). Since the Foundry
Project must be a child of the existing Foundry account (in its own RG), the Bicep
uses a cross-RG module to deploy the project into the Foundry account's RG.

**Consequence:** ADE TTL expiration deletes the ADE-created (empty) RG but
**does NOT delete the Foundry Project** in the Foundry account's RG.

**Workarounds for automated cleanup:**

1. **Azure Policy** — Tag projects with an expiry date at creation time, then
   use a policy or Azure Automation runbook to delete expired projects.
2. **ADE custom runner** — Build a custom extensibility runner that handles
   both creation and deletion lifecycle hooks.
3. **Scheduled cleanup** — Use an Azure Function or Logic App that queries for
   projects tagged by ADE and deletes them after the TTL period.
4. **Manual deletion** — Developer or admin deletes the project via the portal
   or CLI when done.

### RBAC Role Assignments

The developer's **Azure AI User** role is automatically assigned on the Foundry
Project using ADE's built-in `AZURE_ENV_CREATOR_PRINCIPAL_ID` variable — the
developer doesn't need to enter any identity information. ADE injects the Object
ID of the user who creates the environment.

For this to work, ADE performs a **pre-flight permission check** on the **Dev
Center identity** (not the Environment Type identity) for
`Microsoft.Authorization/roleAssignments/write`. The Dev Center MI needs **User
Access Administrator** at the **subscription level**.

If this is too broad for your organization, remove the role assignment from the
Bicep and assign Azure AI User manually after creation.

### Location Mismatch

The project location **must** match the parent Foundry account's location. The
`location` parameter is required (no default) to make this explicit. Use the
same region as the Foundry account.

### Name Reuse After Deletion

Verify that Foundry Projects (`CognitiveServices/accounts/projects`) do not have
a soft-delete retention period that blocks name reuse. This is less likely than
with ML workspaces but should be confirmed.

## Lessons Learned

Key findings from the prototyping process:

1. **Three identities, not one.** ADE has Dev Center MI, ADE Project MI, and
   Environment Type MI. The Environment Type MI executes deployments, but the
   Dev Center MI is checked during pre-flight validation.

2. **Catalog item names must be URL-safe.** Spaces, uppercase, and special
   characters in the `name` field of `environment.yaml` cause catalog sync errors.

3. **No existing RG support.** ADE always creates a new RG per environment.
   Cross-RG Bicep modules are required for deploying into pre-existing RGs.

4. **TTL only covers ADE-created resources.** Cross-RG deployments are not
   cleaned up by TTL expiration. Custom cleanup automation is needed.

5. **`environment.yaml` defaults are literal strings.** A default like
   `"[resourceGroup().location]"` is passed as a literal string, not evaluated
   as an ARM expression. Either omit the default or use a real value.

6. **The new Foundry resource model matters.** Post-Ignite 2025, Foundry uses
   `Microsoft.CognitiveServices/accounts` (kind: AIServices) + `/projects`,
   not the classic `Microsoft.MachineLearningServices/workspaces` hub model.

## File Structure

```
foundry-project-stack/
├── README.md                            # This file
├── .gitignore
└── environments/
    └── foundry-project/
        ├── environment.yaml             # ADE catalog manifest
        ├── main.bicep                   # Entry point (cross-RG module call)
        └── foundry-project.bicep        # Module: creates the Foundry Project
```

## Adding RBAC Back

The Azure AI User role assignment is included by default, using ADE's built-in
`AZURE_ENV_CREATOR_PRINCIPAL_ID` to automatically grant the creating developer
access. If you need to **remove** it (e.g., the Dev Center MI cannot be granted
User Access Administrator), delete the `aiUserAssignment` resource from
`foundry-project.bicep` and the `developerPrincipalId` parameter from all files.

## References

- [Azure Deployment Environments documentation](https://learn.microsoft.com/en-us/azure/deployment-environments/)
- [ADE environment.yaml schema](https://learn.microsoft.com/en-us/azure/deployment-environments/concept-environment-yaml)
- [Microsoft.CognitiveServices/accounts/projects Bicep reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts/projects)
- [Azure AI Foundry documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/)
- [Azure AI User role](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#azure-ai-user)

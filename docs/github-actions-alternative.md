# GitHub Actions Alternative for Foundry Project Self-Service

> **Companion to the ADE approach** — use this when you need working TTL cleanup,
> cost tracking via tags, or automatic identity resolution.

## Why This Alternative?

The [ADE prototype](../README.md) proves that Azure Deployment Environments
*can* provision Foundry Projects, but several ADE features don't work well
for cross-resource-group deployments:

| Feature | ADE Approach | GitHub Actions Approach |
|---------|-------------|----------------------|
| **Developer UX** | Dev Portal form | GitHub Issue form |
| **Identity resolution** | Developer must provide Object ID manually | Automatic — resolves Entra UPN via `az ad user show` |
| **TTL / Auto-cleanup** | ❌ Only deletes empty ADE-created RG | ✅ Tag-based expiration with scheduled cleanup |
| **Cost tracking** | ❌ Tied to empty ADE-created RG | ✅ Tags on actual Foundry Project resource |
| **Approval workflow** | None (or manual ADE admin) | AI-powered triage + label-based approval |
| **RBAC assignment** | Limited (Bicep runner can't inject identity) | ✅ Full — CLI resolves identity before deploy |
| **Auth model** | ADE managed identities (3 separate!) | Single federated identity (OIDC, no secrets) |
| **Audit trail** | ADE Activity Log | GitHub Issue history + Actions logs |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  GitHub Repository                                                  │
│                                                                     │
│  1. Developer opens Issue    2. Agentic Workflow     3. Deploy WF   │
│     (form template)             (AI Maintainer)         (OIDC)      │
│     ┌──────────────┐        ┌─────────────────┐    ┌─────────────┐ │
│     │ Issue Form   │───────►│ Validate fields  │    │ az login    │ │
│     │ - Account    │        │ Check allowlist   │    │ (federated) │ │
│     │ - RG         │        │ Check TTL policy  │    │             │ │
│     │ - Name       │        │ Check UPN format  │    │ az ad user  │ │
│     │ - UPN        │        │                   │    │ show → OID  │ │
│     │ - TTL        │        │ ✅ → add approved │    │             │ │
│     └──────────────┘        │ ⚠️ → add review   │    │ az deploy   │ │
│                             └─────────────────┘    │ group create │ │
│                                     │              └──────┬──────┘ │
│                                     │ label               │        │
│                                     └─────────────────────┘        │
│                                                                     │
│  4. Scheduled Cleanup (daily cron)                                  │
│     ┌──────────────────────────────────────┐                        │
│     │ Query ARM for tagged projects        │                        │
│     │ Delete expired (expires-at < now)    │                        │
│     │ Only touch managed-by=github-actions │                        │
│     └──────────────────────────────────────┘                        │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────┐
│  Azure (Foundry Account RG)                             │
│                                                         │
│  Foundry Account (CognitiveServices/accounts)           │
│  └── Foundry Project (accounts/projects)                │
│      Tags:                                              │
│        managed-by: github-actions                       │
│        provisioning-source: foundry-project-request     │
│        expires-at: 2026-04-23T18:00:00Z                 │
│        issue-number: 42                                 │
│        requestor: jane@contoso.com                      │
│        source-repo: PennStateLefty/foundry-project-stack│
│      RBAC:                                              │
│        Azure AI User → jane@contoso.com                 │
└─────────────────────────────────────────────────────────┘
```

## Flow

1. **Developer** opens a GitHub Issue using the "🚀 Foundry Project Request"
   template. The `foundry-project-request` label is auto-applied.

2. **Agentic Workflow** (`triage-foundry-request.md`) fires on issue creation:
   - Parses the form fields
   - Validates against `config/allowed-targets.json`
   - **Auto-approves** (adds `approved` label) if all checks pass
   - **Escalates** (adds `needs-review` label, @-mentions admin team) if any
     check fails

3. **Deploy Workflow** (`deploy-foundry-project.yml`) fires when `approved`
   label is added:
   - Authenticates to Azure via OIDC (federated workload identity)
   - Resolves the developer's Entra UPN to an Object ID
   - Queries the Foundry account to get its location (no guessing)
   - Deploys the Bicep template with lifecycle tags and RBAC
   - Comments on the issue with the result and closes it

4. **Cleanup Workflow** (`cleanup-expired-projects.yml`) runs daily on a cron
   schedule:
   - Queries all Foundry Projects in allowed RGs
   - Filters to only `managed-by=github-actions` resources
   - Deletes any with `expires-at` in the past

## Prerequisites

### 1. Azure: Federated Workload Identity (OIDC)

This is the **only** authentication method — no client secrets are stored
anywhere.

#### Step 1: Create an Entra App Registration

```bash
az ad app create --display-name "GitHub-Foundry-Project-Deployer"
```

Note the `appId` (client ID) from the output.

#### Step 2: Create a Service Principal

```bash
az ad sp create --id <appId>
```

#### Step 3: Add a Federated Credential

```bash
az ad app federated-credential create \
  --id <appId> \
  --parameters '{
    "name": "github-foundry-project-stack-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:PennStateLefty/foundry-project-stack:environment:azure-deploy",
    "description": "GitHub Actions OIDC for Foundry Project deployment",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

> **Important:** The `subject` must match your repo and the GitHub Environment
> name (`azure-deploy`). If you use a different environment name, update this.

#### Step 4: Grant Azure RBAC

The service principal needs permissions on the Foundry account's resource group:

> **Note:** Unlike ADE (which requires subscription-level User Access Administrator
> due to its pre-flight validation layer), the GitHub Actions approach only needs
> RG-scoped permissions. ARM checks `roleAssignments/write` at the scope where
> the assignment is created — which is the Foundry Project inside this RG.

```bash
SP_OID=$(az ad sp show --id <appId> --query id -o tsv)

# Contributor — create Foundry Projects and ARM deployments
az role assignment create \
  --assignee-object-id "$SP_OID" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "/subscriptions/<sub>/resourceGroups/<foundry-rg>"

# User Access Administrator — create role assignments on projects
az role assignment create \
  --assignee-object-id "$SP_OID" \
  --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" \
  --scope "/subscriptions/<sub>/resourceGroups/<foundry-rg>"
```

The service principal also needs **Directory.Read.All** (or **User.Read.All**)
on Microsoft Graph to resolve UPNs to Object IDs:

```bash
# Grant User.Read.All application permission
GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"
USER_READ_ALL=$(az ad sp show --id $GRAPH_APP_ID --query "appRoles[?value=='User.Read.All'].id" -o tsv)

az ad app permission add \
  --id <appId> \
  --api $GRAPH_APP_ID \
  --api-permissions "$USER_READ_ALL=Role"

# Admin consent (requires Global Admin or Privileged Role Admin)
az ad app permission admin-consent --id <appId>
```

### 2. GitHub: Repository Configuration

#### Repository Variables (not secrets!)

Go to **Settings → Secrets and variables → Actions → Variables** and add:

| Variable | Value | Description |
|----------|-------|-------------|
| `AZURE_CLIENT_ID` | `<appId>` | Entra app registration client ID |
| `AZURE_TENANT_ID` | `<tenantId>` | Entra tenant ID |
| `AZURE_SUBSCRIPTION_ID` | `<subscriptionId>` | Azure subscription containing the Foundry account |

#### GitHub Environment

Create an environment called `azure-deploy`:

1. **Settings → Environments → New environment**
2. Name: `azure-deploy`
3. (Optional) Add **protection rules**:
   - Required reviewers — adds a human approval gate before Azure deployment
   - Deployment branches — restrict to `main` only

#### Agentic Workflow Setup

The AI triage workflow requires the `gh-aw` CLI extension:

```bash
gh extension install github/gh-aw
```

Create a `COPILOT_GITHUB_TOKEN` secret (fine-grained PAT with Copilot Requests
read permission):

1. [Create PAT](https://github.com/settings/personal-access-tokens/new?name=COPILOT_GITHUB_TOKEN&description=Agentic+Workflows&user_copilot_requests=read)
2. Add to repo: **Settings → Secrets and variables → Actions → Secrets** → `COPILOT_GITHUB_TOKEN`

Compile the agentic workflow:

```bash
cd .github/workflows
gh aw compile triage-foundry-request.md
# Commit both .md and .lock.yml
```

### 3. Policy Configuration

Edit `config/allowed-targets.json` to define:
- **Allowed Foundry accounts** — which accounts and RGs can be targeted
- **TTL policy** — max days, default, whether "no expiration" is allowed
- **Approval policy** — auto-approve settings, escalation team

## Security Model

| Layer | Protection |
|-------|-----------|
| **Issue creation** | Anyone can open an issue, but deployment requires `approved` label |
| **AI triage** | Validates against allowlist — only approved targets can be deployed to |
| **Label gate** | Only the agentic workflow or maintainers can add `approved` label |
| **GitHub Environment** | Optional required reviewers before Azure deploy job runs |
| **OIDC auth** | No stored secrets — federated identity with short-lived tokens |
| **Allowlist** | `config/allowed-targets.json` constrains valid targets |
| **Tag-scoped cleanup** | Cleanup workflow only deletes resources it created (multi-tag match) |
| **Input sanitization** | Issue fields are parsed by GitHub Script (JavaScript), not shell-expanded |

## File Structure

```
foundry-project-stack/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   └── foundry-project-request.yml      # Issue form template
│   └── workflows/
│       ├── triage-foundry-request.md         # Agentic workflow (source)
│       ├── triage-foundry-request.lock.yml   # Compiled (after gh aw compile)
│       ├── deploy-foundry-project.yml        # Deploy on approval
│       └── cleanup-expired-projects.yml      # Daily TTL cleanup
├── config/
│   └── allowed-targets.json                  # Policy / allowlist
├── docs/
│   └── github-actions-alternative.md         # This file
├── environments/
│   └── foundry-project/
│       ├── environment.yaml                  # ADE catalog manifest
│       ├── main.bicep                        # Shared entry point
│       └── foundry-project.bicep             # Shared module (tags + RBAC)
└── README.md                                 # ADE approach documentation
```

## Cost Tracking

Unlike the ADE approach (where costs are attributed to an empty RG), the GitHub
Actions approach tags the **actual Foundry Project resource** with:

- `managed-by: github-actions`
- `provisioning-source: foundry-project-request`
- `requestor: <upn>`
- `issue-number: <number>`
- `source-repo: <owner/repo>`

Use Azure Cost Management to filter by these tags for accurate cost attribution
per developer, per project, and per request.

## Comparison: When to Use Which

| Scenario | Recommended Approach |
|----------|---------------------|
| Quick prototype / demo | ADE (simpler setup) |
| Need working TTL cleanup | GitHub Actions |
| Need cost tracking per project | GitHub Actions |
| Organization already uses ADE | ADE (familiar UX) |
| Organization uses GitHub for workflow | GitHub Actions |
| Need automatic identity resolution | GitHub Actions |
| Need approval workflow | GitHub Actions (agentic + label gate) |
| Minimal Azure permissions | ADE (uses existing ADE identities) |

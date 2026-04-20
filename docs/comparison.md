---
layout: page
title: "Side-by-Side Comparison"
---

# Side-by-Side Comparison

Both approaches — Azure Deployment Environments (ADE) and GitHub Actions — successfully provision Foundry Projects via Bicep. The underlying infrastructure-as-code is identical. The differences come down to how each approach handles the lifecycle around that deployment: governance, cleanup, identity resolution, and developer experience.

This page provides a detailed comparison to help you choose the right approach for your organization.

---

## Feature Comparison

| Feature | ADE | GitHub Actions |
|---------|-----|----------------|
| Developer interface | Azure Dev Portal | GitHub Issue form |
| Template source | GitHub catalog (synced to Dev Center) | Same repo (direct) |
| Template format | Bicep (same template) | Bicep (same template) |
| Identity resolution | Manual (developer provides Object ID) | Automatic (UPN → Object ID via Graph API) |
| Approval workflow | None (or manual ADE admin) | AI-powered triage + label gate |
| TTL / Auto-cleanup | ❌ Only deletes empty ADE-created RG | ✅ Tag-based with daily cron cleanup |
| Cost tracking | ❌ Attributed to empty RG | ✅ Tags on actual project resource |
| Auth model | 3 managed identities | 1 OIDC federated identity |
| Permission scope | Subscription-level (Dev Center MI) | RG-scoped only |
| Secrets management | No secrets (managed identities) | No Azure secrets (OIDC); PAT for AI triage |
| Audit trail | ADE Activity Log | GitHub Issue history + Actions logs |
| Cross-RG deployment | ✅ Via Bicep module | ✅ Direct (no workaround needed) |
| Resource group created | Yes (empty, per environment) | No |
| Setup complexity | Medium (3 identities, catalog sync) | Medium (OIDC, Graph perms, agentic compile) |
| Azure dependency | Full (ADE is Azure-native) | Partial (OIDC + ARM; UI is GitHub) |
| GitHub dependency | Catalog only | Full (Issues, Actions, Agentic Workflows) |

---

## Decision Matrix

Use the flowchart below to determine which approach best fits your scenario.

<div class="mermaid">
flowchart TB
  Start["Need self-service<br/>Foundry Projects?"] --> Q1{"Organization<br/>uses GitHub?"}
  Q1 -->|"No"| ADE["Use ADE Approach"]
  Q1 -->|"Yes"| Q2{"Need working TTL<br/>or cost tracking?"}
  Q2 -->|"No"| Q3{"Prefer native<br/>Azure experience?"}
  Q2 -->|"Yes"| GHA["Use GitHub Actions"]
  Q3 -->|"Yes"| ADE
  Q3 -->|"No"| GHA

  ADE --> ADE_Note["✅ Native Azure UX<br/>⚠️ Manual cleanup needed<br/>⚠️ Broad permissions"]
  GHA --> GHA_Note["✅ Full lifecycle automation<br/>✅ AI-powered governance<br/>⚠️ Requires GitHub + PAT"]

  style ADE_Note fill:#f0f0f0,stroke:#999
  style GHA_Note fill:#f0f0f0,stroke:#999
</div>

---

## When to Use Which

### Choose ADE when:

- Your organization already uses Azure Deployment Environments and wants to consolidate provisioning workflows there.
- Developers are comfortable with the Azure Dev Portal and prefer a native Azure experience.
- You don't need automated TTL cleanup — manual cleanup of expired projects is acceptable.
- You want minimal external dependencies — everything stays within the Azure ecosystem.
- A quick prototype or demo is the goal, and you want to leverage existing Dev Center infrastructure.

### Choose GitHub Actions when:

- Your organization uses GitHub for development workflows and wants provisioning to live alongside code.
- Automated TTL cleanup and cost tracking are hard requirements.
- You want AI-powered request validation to catch misconfigurations before deployment.
- You need automatic identity resolution — no asking developers to look up their Object ID.
- You want an approval workflow with a full audit trail (issue history + workflow logs).
- You prefer RG-scoped permissions over subscription-level access for the deploying identity.

---

## Lessons Learned

We encountered several insights that apply regardless of which approach you choose.

### 1. Foundry Projects are child resources, not standalone

Both approaches must deploy into the parent account's resource group. A Foundry Project (`Microsoft.CognitiveServices/accounts/projects`) is a child resource of the AI Services account — it cannot exist in its own RG. This is the root cause of most ADE limitations.

### 2. ADE's RG-centric model is a poor fit for child resources

ADE assumes every deployment owns its resource group. When the actual resource lives under a parent in a different RG, ADE's TTL, cost tracking, and deletion logic all break down. Any ARM resource type that lives under a parent (not in its own RG) will face the same issues.

### 3. Pre-flight validation adds hidden permission requirements

ADE's Dev Center managed identity needs subscription-level Owner even when the Bicep template itself doesn't require it. This is because ADE performs a pre-flight validation pass that checks permissions broadly. GitHub Actions has no such pre-flight layer — it only needs the permissions the Bicep template actually uses.

### 4. GITHUB_TOKEN events don't trigger workflows

The agentic triage workflow's `approved` label — added via `GITHUB_TOKEN` — doesn't fire the deploy workflow. GitHub intentionally suppresses workflow triggers from `GITHUB_TOKEN`-initiated events to prevent infinite loops. We solved this with a `workflow_run` trigger that watches for the triage workflow to complete, then checks for the `approved` label.

### 5. Graph API permissions differ by identity type

App Registrations use `az ad app permission add` to configure Graph API access. User-Assigned Managed Identities, however, require `az rest` to POST an `appRoleAssignment` directly to the Microsoft Graph service principal. The permission model is fundamentally different, and the Azure CLI doesn't abstract over this difference.

### 6. The new Foundry resource model matters

Post-Ignite 2025, Azure AI Foundry uses `Microsoft.CognitiveServices/accounts` (kind: `AIServices`) with child `/projects` resources — not the classic `Microsoft.MachineLearningServices/workspaces` hub-and-spoke model. Bicep references must use the `@2025-06-01` API version or later. Templates targeting the old resource model will not work with the current Foundry architecture.

### 7. Tags are the lifecycle primitive for non-RG resources

When you can't rely on RG-level lifecycle management (because the resource lives in a shared RG), resource tags become the lifecycle primitive. We use `managed-by`, `expires-at`, and `requested-by` tags on every deployed resource, combined with a daily cleanup job that queries for expired tags. This pattern is portable to any Azure resource type.

---

## What's Next

We see several directions for extending this work:

- **Hybrid approach** — Use ADE for the developer request UI while routing actual deployments through a custom runner that calls GitHub Actions. This gives you the Azure Dev Portal experience with full lifecycle automation.
- **Azure Functions cleanup** — Replace the GitHub Actions cron-based cleanup with an Azure-native timer trigger function. This removes the GitHub dependency from the cleanup path.
- **Terraform alternative** — The same pattern works with Terraform (using the AzAPI provider) instead of Bicep. The lifecycle management, tagging, and identity resolution logic are provider-agnostic.
- **Multi-account support** — Extend the allowlist to support multiple Foundry accounts across subscriptions, enabling teams to provision projects into different AI Services accounts based on region, cost center, or compliance requirements.

---

## Navigation

[← GitHub Actions Approach](github-actions-approach.md) | [Overview](index.md) | [ADE Approach](ade-approach.md)

### Source Code

- [Repository](https://github.com/PennStateLefty/foundry-project-stack)
- [Bicep Templates](https://github.com/PennStateLefty/foundry-project-stack/tree/main/environments/foundry-project)
- [GitHub Actions Workflows](https://github.com/PennStateLefty/foundry-project-stack/tree/main/.github/workflows)

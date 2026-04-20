---
layout: page
title: "Platform Engineering Context"
---

## What is Platform Engineering?

Platform Engineering is the discipline of building and maintaining Internal Developer Platforms (IDPs). Rather than expecting every development team to become experts in cloud infrastructure, networking, and compliance, platform teams build abstractions that let developers provision what they need through self-service interfaces — with the right guardrails already in place.

IDPs abstract away infrastructure complexity and give developers self-service capabilities without sacrificing governance. A well-designed IDP handles identity, networking, cost controls, and security policies behind the scenes, so dev teams can focus on building their applications. The developer asks for a workspace; the platform delivers one that's already compliant.

The goal is to reduce cognitive load on development teams while maintaining governance, security, and cost control across the organization. Instead of writing tickets and waiting for an infrastructure team to provision resources manually, developers interact with a portal, a CLI, or an issue form — and the platform does the rest.

This is the "paved roads" concept: platform teams provide golden paths that are easy to follow. You _can_ go off-road if you need to, but the paved road is faster, safer, and already has guardrails. When the golden path is genuinely easier than the alternative, adoption happens naturally.

## How Foundry Project Provisioning Fits

Azure AI Foundry Projects are the workspace primitive for AI development on Azure. A Project is where a team connects to models, stores data connections, deploys agents, and runs evaluations. It's the unit of isolation for AI workloads.

Platform teams typically manage the Foundry account — the shared infrastructure layer that includes model deployments, networking configuration, and compliance settings. Dev teams, on the other hand, need isolated Projects for experimentation, each with their own data connections, agent deployments, and RBAC boundaries.

Self-service provisioning of Foundry Projects is a natural IDP capability. A developer should be able to request a new Project, get it provisioned with the right permissions and connections, and start building — without filing a ticket or waiting on a platform engineer.

The challenge is that Foundry Projects are ARM child resources (`Microsoft.CognitiveServices/accounts/projects`), not standalone resources. They must live under their parent Foundry account, in the account's resource group. They don't fit neatly into Azure's resource-group-centric provisioning model, and this architectural reality drives many of the design decisions we'll explore in the following pages.

## Two Approaches

We evaluate two approaches to self-service Foundry Project provisioning. Both share the same underlying infrastructure-as-code, but they differ in how they expose the self-service interface and handle identity, lifecycle, and governance.

<div class="mermaid">
flowchart TB
  subgraph IDP["Internal Developer Platform"]
    direction TB
    UI["Developer Interface"]
    Policy["Policy Engine"]
    IaC["Infrastructure as Code<br/>(Shared Bicep Template)"]
  end

  subgraph ADE["Approach 1: Azure Deployment Environments"]
    DevPortal["Azure Dev Portal"]
    ADECatalog["ADE Catalog"]
    ADEMI["ADE Managed Identities (3)"]
  end

  subgraph GHA["Approach 2: GitHub Issues + Actions"]
    IssueForm["GitHub Issue Form"]
    AITriage["AI Triage (Agentic Workflow)"]
    OIDC["OIDC Federated Identity"]
  end

  Developer --> UI
  UI --> ADE
  UI --> GHA
  ADE --> IaC
  GHA --> IaC
  IaC --> Azure["Azure AI Foundry Project"]
</div>

**Approach 1 — Azure Deployment Environments (ADE)** uses Microsoft's managed platform to give developers a portal-based provisioning experience. ADE handles catalog management, environment lifecycle, and identity — but its resource-group-centric model creates friction with Foundry's child-resource architecture.

**Approach 2 — GitHub Issues + Actions** uses GitHub as the developer interface. Developers open an issue using a structured form, an agentic AI workflow triages the request, and a GitHub Actions pipeline provisions the Project via OIDC federated identity. It's more flexible but requires us to build the governance layer ourselves.

## Shared Infrastructure

Regardless of which approach we use, both share the same core infrastructure:

- **The same Bicep template** — `environments/foundry-project/main.bicep` serves as the entry point, calling `foundry-project.bicep` as a module.
- **The same ARM resource types** — `Microsoft.CognitiveServices/accounts/projects@2025-06-01` for the Project itself, plus `Microsoft.Authorization/roleAssignments` for RBAC.
- **The same cross-RG deployment pattern** — The entry Bicep deploys in one scope, then uses a module scoped to the Foundry account's resource group to create the child resource.
- **The same RBAC model** — Both approaches assign the Azure AI User role on the newly created Project to the requesting developer's identity.

<div class="mermaid">
flowchart LR
  main["main.bicep<br/>(entry point)"] -->|"cross-RG module"| fp["foundry-project.bicep"]
  fp --> Project["Foundry Project"]
  fp --> RBAC["Azure AI User<br/>Role Assignment"]
</div>

This shared foundation means the actual provisioning logic is written once and reused. The two approaches differ in _how they invoke_ this template, not in _what it does_.

## The Key Tension

There is a fundamental architectural tension at the heart of this design:

**Azure's provisioning model is resource-group-centric.** Services like Azure Deployment Environments create a new resource group per environment. Cost tracking, lifecycle management (TTL), and identity injection all assume the provisioned resources live in that environment's RG.

**Foundry Projects are child resources that must live under their parent account**, in the account's resource group. You cannot create a `Microsoft.CognitiveServices/accounts/projects` resource in an arbitrary RG — it must be scoped to the existing Foundry account.

This mismatch drives the key differences between our two approaches:

- **ADE** works around the mismatch with cross-RG module deployments. The ADE-managed RG exists (satisfying ADE's model), but the actual Project is created in the Foundry account's RG via a cross-scope module. The trade-off: we lose ADE's built-in TTL enforcement, cost tracking breaks because the resources aren't in the managed RG, and ADE's identity injection doesn't carry through the cross-RG boundary.

- **GitHub Actions** sidesteps the problem entirely. Since we control the deployment pipeline, we deploy directly to the Foundry account's resource group. There's no intermediate RG, no cross-scope workaround, and no identity injection gap. The trade-off: we own the full governance stack — approval workflows, lifecycle management, and audit trails are our responsibility to build.

Neither approach is universally better. The right choice depends on your organization's existing platform investments, governance requirements, and team capabilities. We explore each in detail on the following pages.

---

[← Overview](index.md) | [ADE Approach →](ade-approach.md) | [GitHub Actions Approach →](github-actions-approach.md) | [Comparison](comparison.md)

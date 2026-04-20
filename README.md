# Foundry Project Self-Service Provisioning

> **Prototype / Proof of Concept — Validated ✅**
>
> Can platform teams enable developers to self-service create Azure AI Foundry
> Projects under an existing Foundry account — with governance, TTL, and RBAC?

## 📖 Documentation

**Full documentation is available on [GitHub Pages](https://pennstatelefty.github.io/foundry-project-stack/).**

| Page | Description |
|------|-------------|
| [Overview](https://pennstatelefty.github.io/foundry-project-stack/) | The problem, what self-service means, high-level flow |
| [Platform Engineering](https://pennstatelefty.github.io/foundry-project-stack/platform-engineering) | IDP concepts, how both approaches fit |
| [ADE Approach](https://pennstatelefty.github.io/foundry-project-stack/ade-approach) | Benefits, RG-centric limitations, identity model |
| [GitHub Actions Approach](https://pennstatelefty.github.io/foundry-project-stack/github-actions-approach) | AI triage, OIDC, tag-based TTL, security |
| [Comparison](https://pennstatelefty.github.io/foundry-project-stack/comparison) | Side-by-side table, decision matrix, lessons learned |

## Quick Summary

We prototyped two approaches for developer self-service Foundry Project creation:

### 1. Azure Deployment Environments (ADE)
Uses the native Azure Dev Portal. Proves the concept works, but ADE's
resource-group-centric model doesn't mesh well with Foundry's child-resource
architecture — TTL, cost tracking, and identity injection all break.

### 2. GitHub Issues + Actions
Uses GitHub Issue forms for requests, AI-powered triage (Agentic Workflows)
for validation, OIDC for Azure auth, and tag-based cleanup for TTL. Addresses
ADE's limitations but requires GitHub and a PAT for the AI agent.

## Repository Structure

```
foundry-project-stack/
├── environments/foundry-project/     # Shared Bicep templates (both approaches)
│   ├── main.bicep                    # Entry point (cross-RG module)
│   ├── foundry-project.bicep         # Module: Foundry Project + RBAC
│   └── environment.yaml              # ADE catalog manifest
├── .github/
│   ├── ISSUE_TEMPLATE/               # Issue form for project requests
│   └── workflows/                    # Deploy, triage, cleanup workflows
├── config/allowed-targets.json       # Policy allowlist
├── docs/                             # GitHub Pages documentation
└── README.md                         # This file
```

## References

- [Azure AI Foundry documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/)
- [Azure Deployment Environments](https://learn.microsoft.com/en-us/azure/deployment-environments/)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [CognitiveServices/accounts/projects Bicep](https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts/projects)

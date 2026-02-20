---
name: knowledge-base
description: Use when discussing topics where curated reference knowledge exists, such as Kubernetes networking, ingress controller migration, or other technical subjects the user has previously researched and distilled. This skill loads high-quality reference material that Claude can use to provide informed, accurate answers without re-researching from scratch.
version: 0.1.0
---

# Knowledge Base Skill

You have access to a curated library of technical reference material organized by topic. These references contain distilled knowledge from articles, documentation, and hands-on experience -- vetted and structured for quick retrieval.

## When to Use This Skill

Invoke this skill when the user asks about a topic that has curated reference material available. The skill supplements your training data with specific, verified, up-to-date knowledge.

## Reference Library Structure

References are organized by topic area under `reference/`:

```
knowledge-base/
├── SKILL.md
└── reference/
    ├── kubernetes-networking/
    │   └── traefik-migration.md
    ├── packer-talos-proxmox/
    │   └── packer-talos-image-factory.md
    ├── proxmox-ansible-host-config/
    │   └── ansible-host-configuration.md
    ├── talos-linux/
    │   └── ...
    ├── talos-proxmox-nocloud/
    │   └── nocloud-boot-provisioning.md
    └── talos-terraform-proxmox/
        └── terraform-talos-ha-pattern.md
```

### Available Topics

| Topic | Path | Contents |
|-------|------|----------|
| Kubernetes Networking | `reference/kubernetes-networking/` | Ingress controller migration, Traefik, Gateway API |
| Proxmox Ansible Host Config | `reference/proxmox-ansible-host-config/` | Ansible role-based hypervisor configuration, network templating, desired-state management |
| Talos Linux | `reference/talos-linux/` | Image cache, registry DDoS prevention, IMAGECACHE partition, registryd |
| Talos Proxmox NoCloud | `reference/talos-proxmox-nocloud/` | Talos Linux nocloud/cloud-init boot on Proxmox: SMBIOS serial method, cicustom snippets, nocloud vs metal images, JYSK 3000-cluster scale pattern, known boot issues |
| Talos Terraform Proxmox | `reference/talos-terraform-proxmox/` | Terraform-based Talos HA cluster on Proxmox, Cilium CNI, bpg/proxmox + siderolabs/talos providers |
| Packer Talos Proxmox | `reference/packer-talos-proxmox/` | Packer-based Talos template creation using Image Factory API, CI/CD-friendly automation |

## How to Use References

1. **At invocation**, read all `.md` files in the relevant `reference/` subdirectory
2. **Synthesize** reference material with your existing knowledge
3. **Cite the reference** when answering -- mention that the information comes from curated notes
4. **Cross-reference** with the user's Obsidian vault at `~/notes/` for related notes (use the `knowledge-reader` agent for vault searches if needed)

## Adding New References

When the user wants to add knowledge to the base:

1. Identify the topic area (create a new subdirectory under `reference/` if needed)
2. Distill the source material into a structured reference document
3. Use this format for reference docs:

```markdown
---
topic: <topic-area>
source: <original-url-or-description>
created: YYYY-MM-DD
updated: YYYY-MM-DD
tags:
  - <relevant-tag>
---

# Title

## Summary
2-3 sentence overview of what this reference covers.

## Key Concepts
Core technical details, organized by subtopic.

## Practical Application
Commands, configurations, step-by-step procedures.

## Decision Points
Trade-offs, alternatives, when to use what.

## References
Links to official docs and further reading.
```

4. Update the "Available Topics" table in this SKILL.md
5. Create a corresponding note in `~/notes/` if one doesn't exist (using the obsidian-notes agent conventions)

## Relationship to Obsidian Vault

The knowledge base and Obsidian vault serve complementary purposes:

- **Knowledge base** (this skill): Curated, distilled reference material optimized for Claude to load and reason with. Structured for machine consumption.
- **Obsidian vault** (`~/notes/`): The user's full knowledge graph with rich cross-linking, status tracking, and personal context. Structured for human consumption and AI-assisted search.

When a reference is added here, a corresponding note should also exist in the vault. The vault note may contain additional personal context, related links, and status tracking that the reference doc omits.

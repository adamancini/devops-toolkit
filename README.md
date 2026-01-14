# DevOps Toolkit

A comprehensive collection of agents and skills for Claude Code focused on DevOps, infrastructure management, and developer productivity.

## Quick Start

```bash
# Install via Claude Code
/plugins install https://github.com/adamancini/devops-toolkit

# Or clone manually
git clone https://github.com/adamancini/devops-toolkit ~/.claude/plugins/repos/devops-toolkit
```

Restart Claude Code and invoke skills:
```
"Create a wildcard certificate for example.com"
"Configure aerospace for my workspace"
```

## Agents

Specialized agents for project-specific workflows and task automation.

### CLAUDEMD Compliance Checker
Verifies compliance with project-specific instructions in CLAUDE.md/AGENTS.md files.

### Helm Chart Developer
Production-quality Helm chart development with Helm 3 standards and best practices.

### Home Manager
Expert management of home directory structure, dotfiles with yadm, and system configuration.

### Linear Assistant
Processes verbose Linear MCP responses and returns concise summaries for context optimization.

### Markdown Writer
Creates, edits, and improves Markdown documents with proper formatting and style compliance.

### MCP Security Validator
Validates MCP servers for security issues before addition to Claude Code.

### Obsidian Notes
Expert Obsidian knowledge management for vault operations and Notion synchronization.

### Quality Control Enforcer
Reviews work to ensure it meets quality standards and avoids common pitfalls.

### Shell Code Optimizer
Ensures shell scripts follow portability, simplicity, and best practices for cross-platform compatibility.

### YAML Kubernetes Validator
Validates YAML documents for proper formatting and Kubernetes API specification compliance.

## Skills Overview

### SSL Certificate Manager

Comprehensive SSL/TLS certificate management with Let's Encrypt.

**Key Features:**
- Automated DNS challenges (Google Cloud DNS, Cloudflare, Route53)
- Manual DNS challenges for any provider
- Wildcard certificate support
- Certificate inspection and validation
- Kubernetes TLS secret generation
- Renewal workflows with expiration monitoring

**Example:**
```
"Create a wildcard certificate for *.example.com using Cloudflare DNS"
```

[Full Documentation →](./skills/ssl-cert-manager/)

### AeroSpace Configuration Manager

Safe management of AeroSpace window manager configurations on macOS.

**Key Features:**
- Automatic backup before changes
- Keybinding conflict detection (AeroSpace + macOS + apps)
- Application workspace assignments
- Floating vs tiling window rules
- Multi-monitor configuration
- TOML validation and rollback

**Example:**
```
"Assign Chrome to workspace 2"
"Add keybinding for fullscreen toggle"
```

[Full Documentation →](./skills/aerospace-config-manager/)

## Installation

### Prerequisites

- **General**: Claude Code, macOS 14+
- **SSL Cert Manager**: Docker, DNS provider access
- **AeroSpace Manager**: [AeroSpace](https://github.com/nikitabobko/AeroSpace), Python 3.11+

### Via Claude Code

```
/plugins install https://github.com/adamancini/devops-toolkit
```

### Manual Installation

```bash
mkdir -p ~/.claude/plugins/repos
cd ~/.claude/plugins/repos
git clone https://github.com/adamancini/devops-toolkit
```

Restart Claude Code to load the plugin.

## Configuration

### SSL Certificate Manager

Configure DNS provider credentials:

**Google Cloud DNS:**
```bash
# Place service account JSON
~/letsencrypt/credentials.json
```

**Cloudflare:**
```bash
# Create credentials file
cat > ~/letsencrypt/cloudflare.ini <<EOF
dns_cloudflare_api_token = your-token
EOF
```

**Route53:**
```bash
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
```

### AeroSpace Configuration Manager

No additional configuration required. Works with existing `~/.aerospace.toml`.

## Usage Examples

### SSL Certificates

**Generate certificate:**
```
User: "Create a wildcard certificate for *.lab.example.com using Google Cloud DNS"

→ Verifies credentials
→ Runs certbot with dns-google plugin
→ Generates cert + key
→ Shows expiration date
→ Optionally creates Kubernetes secret
```

**Renew certificate:**
```
User: "Renew my example.com certificate"

→ Checks expiration
→ Runs renewal
→ Updates Kubernetes secrets
```

### AeroSpace Configuration

**Workspace setup:**
```
User: "Set up my development workspace layout"

→ Detects running apps
→ Suggests assignments (Browser→1, Editor→2, etc.)
→ Creates backup
→ Applies configuration
→ Generates cheatsheet
```

**Add keybinding:**
```
User: "Add alt+m for fullscreen"

→ Checks conflicts
→ Shows preview
→ Backs up config
→ Applies change
→ Reloads AeroSpace
```

## Architecture

```
devops-toolkit/
├── README.md                                # This file
├── plugin.json                              # Plugin manifest
├── CHANGELOG.md                             # Version history
├── LICENSE                                  # MIT License
├── agents/                                  # Agent definitions
│   ├── claudemd-compliance-checker.md
│   ├── helm-chart-developer.md
│   ├── home-manager.md
│   ├── linear-assistant.md
│   ├── markdown-writer.md
│   ├── mcp-security-validator.md
│   ├── obsidian-notes.md
│   ├── quality-control-enforcer.md
│   ├── shell-code-optimizer.md
│   └── yaml-kubernetes-validator.md
└── skills/
    ├── ssl-cert-manager/
    │   ├── ssl-cert-manager.md             # Skill implementation
    │   └── README.md                        # Skill documentation
    ├── aerospace-config-manager/
    │   ├── aerospace-config-manager.md     # Skill implementation
    │   └── README.md                        # Skill documentation
    └── linear-mcp-operations/
        ├── SKILL.md                         # Skill implementation
        └── README.md                        # Skill documentation
```

## Development

### Adding Agents

1. Create agent markdown file in `agents/`
2. Include YAML frontmatter with description and capabilities
3. Add detailed agent instructions
4. Update this README with agent description
5. Update CHANGELOG.md

### Adding Skills

1. Create skill directory in `skills/`
2. Add skill markdown file (implementation)
3. Add README.md (user documentation)
4. Update `plugin.json` manifest
5. Update this README and CHANGELOG

### Testing

Test skills by invoking in Claude Code:
```
"Test ssl certificate with staging environment"
"Validate my aerospace configuration"
```

### Contributing

1. Fork the repository
2. Create feature branch
3. Make changes
4. Test thoroughly
5. Submit pull request

## Troubleshooting

### Plugin Not Loading

```bash
# Verify installation
ls -la ~/.claude/plugins/repos/devops-toolkit/plugin.json

# Check JSON validity
cat ~/.claude/plugins/repos/devops-toolkit/plugin.json | python3 -m json.tool

# Restart Claude Code
```

### SSL Certificate Issues

- **Rate limits**: Use Let's Encrypt staging for testing
- **DNS propagation**: Wait 5-10 minutes after DNS changes
- **Docker**: Verify Docker daemon is running

### AeroSpace Issues

- **Config backup**: Check `~/.aerospace.toml.backups/`
- **TOML errors**: Run `python3 -c "import tomllib; tomllib.load(open('~/.aerospace.toml', 'rb'))"`
- **Keybinding conflicts**: Check System Settings > Keyboard

## Security

- SSL private keys stored locally in `~/letsencrypt/`
- DNS credentials should follow least-privilege principle
- AeroSpace backups stored locally (no remote transmission)
- All configuration changes backed up before modification

## Roadmap

### Planned Skills

- Kubernetes helpers (pod debugging, log aggregation)
- Helm chart validator
- Docker Compose manager
- Terraform manager
- CI/CD pipeline helpers

See [CHANGELOG.md](./CHANGELOG.md) for version history.

## Support

- **Issues**: [GitHub Issues](https://github.com/adamancini/devops-toolkit/issues)
- **Discussions**: [GitHub Discussions](https://github.com/adamancini/devops-toolkit/discussions)

## Author

**Ada Mancini** ([@adamancini](https://github.com/adamancini))

DevOps engineer specializing in Kubernetes, Helm, and infrastructure automation.

## License

MIT License - see [LICENSE](./LICENSE) file.

## Acknowledgments

- [AeroSpace](https://github.com/nikitabobko/AeroSpace) - macOS tiling window manager
- [Let's Encrypt](https://letsencrypt.org/) - Free SSL/TLS certificates
- [Claude Code](https://claude.ai/code) - AI development assistant

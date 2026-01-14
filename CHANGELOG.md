# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Kubernetes helpers (pod debugging, log aggregation)
- Docker Compose manager
- Terraform configuration manager
- CI/CD pipeline helpers

## [1.2.0] - 2026-01-14

### Added
- Agents component to plugin structure:
  - CLAUDEMD Compliance Checker - Verifies project-specific instruction compliance
  - Helm Chart Developer - Production Helm chart development workflows
  - Home Manager - Home directory, dotfiles, and system configuration management
  - Linear Assistant - Context-optimized Linear MCP operations
  - Markdown Writer - Professional Markdown document creation and editing
  - MCP Security Validator - Security validation for MCP server installations
  - Obsidian Notes - Knowledge management and vault operations
  - Quality Control Enforcer - Quality standards validation
  - Shell Code Optimizer - Cross-platform shell script best practices
  - YAML Kubernetes Validator - YAML and K8s manifest validation
- Linear MCP Operations skill for reliable Linear interactions
- Updated plugin architecture to include agents directory
- Enhanced documentation for agent usage and development

### Changed
- Updated README.md with comprehensive agent documentation
- Expanded development section with agent creation workflow
- Updated architecture diagram to reflect agents component

## [1.1.0] - 2026-01-07

### Added
- Linear MCP Operations skill for reliable Linear interactions with health checking

## [1.0.0] - 2025-11-19

### Added
- Initial release of DevOps Toolkit plugin
- SSL Certificate Manager skill:
  - Automated DNS challenges (Google Cloud DNS, Cloudflare, Route53)
  - Manual DNS challenge workflows
  - Wildcard certificate support
  - Certificate inspection and validation with openssl
  - Expiration monitoring
  - Kubernetes TLS secret generation
  - Renewal workflows
  - Integration with cert-manager
- AeroSpace Configuration Manager skill:
  - Safe configuration management with automatic backup
  - TOML syntax and semantic validation
  - Keybinding management with conflict detection
  - Application workspace assignment
  - Floating vs tiling window rules
  - Multi-monitor configuration support
  - Documentation generation (markdown cheatsheets)
  - Rollback to previous configurations
  - Integration with YADM and git workflows
  - Task runner integration
- Comprehensive documentation:
  - Plugin README with installation and usage instructions
  - Skill-specific documentation with examples
  - Troubleshooting guides
  - Best practices
- MIT License
- This changelog

### Documentation
- README.md for plugin overview
- Individual skill READMEs with detailed usage examples
- Inline documentation in skill implementation files

## Release Notes

### v1.0.0 - Initial Release

This is the first public release of the DevOps Toolkit plugin for Claude Code. The plugin provides two comprehensive skills for DevOps and infrastructure management:

**SSL Certificate Manager** makes Let's Encrypt certificate management simple and safe, with support for multiple DNS providers, automated renewals, and seamless Kubernetes integration.

**AeroSpace Configuration Manager** provides safe, validated management of AeroSpace window manager configurations with automatic backups, conflict detection, and easy rollback.

Both skills emphasize safety, with automatic backups before changes, comprehensive validation, and easy rollback capabilities.

## Future Roadmap

### v1.1.0 (Planned)
- Kubernetes pod debugging helpers
- Container log aggregation workflows
- kubectl shortcut commands

### v1.2.0 (Planned)
- Helm chart linting and validation
- Chart dependency management
- Release workflows

### v2.0.0 (Planned)
- Terraform plan and apply workflows
- State management helpers
- Provider configuration

---

For detailed changes and migration guides, see individual skill documentation.

[Unreleased]: https://github.com/adamancini/devops-toolkit/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/adamancini/devops-toolkit/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/adamancini/devops-toolkit/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/adamancini/devops-toolkit/releases/tag/v1.0.0

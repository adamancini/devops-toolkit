# Replicated Release Workflows

This reference provides detailed patterns for creating, promoting, and managing Replicated releases.

## Release Lifecycle

A Replicated release progresses through several stages:

1. **Development** - Manifests are created/updated in source control
2. **Validation** - Linting checks manifest syntax and references
3. **Creation** - Release is created with version label and sequence number
4. **Promotion** - Release is promoted to one or more channels
5. **Deployment** - Customers receive updates via their subscribed channels

## Creating Releases

### Basic Release Creation

Create a release from a directory of manifests:

```bash
replicated release create \
  --app <app-slug> \
  --yaml-dir <path-to-manifests> \
  --version <semantic-version>
```

**Parameters:**
- `--app` - Application slug from vendor portal
- `--yaml-dir` - Directory containing KOTS manifests (YAML files)
- `--version` - Semantic version label (e.g., `1.2.3`, `1.2.3-beta.1`)

**Output:**
- Sequence number (auto-incremented integer, e.g., `123`)
- Release ID
- Created timestamp

### Lint Before Creating

Always validate manifests before creating releases:

```bash
replicated release lint \
  --app <app-slug> \
  --yaml-dir <path-to-manifests>
```

**Common lint issues:**
- Missing required fields in KOTS manifests
- Invalid Kubernetes resource specs
- Broken template syntax in Helm charts
- Nonexistent status informer objects
- Schema validation failures

**Filtering lint output:**

Some warnings can be ignored (e.g., nonexistent status informers during development):

```bash
replicated release lint --app chef-360 --yaml-dir manifests | \
  grep -v 'nonexistent-status-informer-object'
```

### Combined Workflow

Create, lint, and promote in a single command:

```bash
replicated release create \
  --app <app-slug> \
  --yaml-dir <path-to-manifests> \
  --lint \
  --promote <channel-name-or-id> \
  --version <version>
```

This approach:
- Validates manifests first
- Creates release if validation passes
- Immediately promotes to specified channel
- Applies version label

## Promoting Releases

### Promote by Sequence Number

After creating a release, promote it to channels:

```bash
replicated release promote <sequence> <channel-name-or-id> \
  --app <app-slug> \
  --version <version>
```

**Example:**
```bash
# Create release (get sequence from output)
replicated release create --app myapp --yaml-dir ./manifests --version 1.2.3
# Output: SEQUENCE: 42

# Promote to beta channel
replicated release promote 42 beta --app myapp --version 1.2.3
```

### Promote to Multiple Channels

Promote the same sequence to multiple channels for staged rollouts:

```bash
# Promote to beta first
replicated release promote 42 beta --app myapp --version 1.2.3

# After testing, promote to stable
replicated release promote 42 stable --app myapp --version 1.2.3
```

### Channel Selection Best Practices

**Development workflow:**
- Use branch-named channels during development (e.g., `feature-auth`, `bugfix-123`)
- Automatically create channels matching git branches
- Clean up channels when branches are merged/deleted

**Release workflow:**
- `unstable` - Latest builds, internal testing only
- `beta` - Pre-release testing with select customers
- `stable` - Production-ready releases

## Version Labeling Strategies

### Semantic Versioning

Standard format: `MAJOR.MINOR.PATCH`

```bash
replicated release create --app myapp --yaml-dir ./manifests --version 1.2.3
```

**When to increment:**
- `MAJOR` - Breaking changes or major feature releases
- `MINOR` - New features, backward-compatible
- `PATCH` - Bug fixes, security patches

### Pre-release Versions

Use pre-release labels for non-production releases:

```bash
# Beta release
replicated release create --app myapp --yaml-dir ./manifests --version 1.2.3-beta.1

# Release candidate
replicated release create --app myapp --yaml-dir ./manifests --version 1.2.3-rc.2

# Development snapshot
replicated release create --app myapp --yaml-dir ./manifests --version 1.2.3-dev.20250119
```

### Build Metadata

Include build metadata for traceability:

```bash
# Git commit SHA
replicated release create --app myapp --yaml-dir ./manifests --version 1.2.3+abc123

# Build number
replicated release create --app myapp --yaml-dir ./manifests --version 1.2.3+build.456

# Combined
replicated release create --app myapp --yaml-dir ./manifests --version 1.2.3-beta.1+abc123
```

### Branch-Based Versioning

For CI/CD pipelines, include branch and commit information:

```bash
# Format: <branch>-<short-sha>
VERSION="$(git branch --show-current)-$(git rev-parse --short HEAD)"
replicated release create --app myapp --yaml-dir ./manifests --version $VERSION

# Format: <version>+<branch>.<sha>
BASE_VERSION=$(cat VERSION)  # e.g., 1.2.3
VERSION="${BASE_VERSION}+$(git branch --show-current).$(git rev-parse --short HEAD)"
replicated release create --app myapp --yaml-dir ./manifests --version $VERSION
```

## Helm Chart Packaging

When using Helm charts with KOTS, package charts into the manifest directory:

```bash
# Package chart with dependencies
helm package ./chart-dir \
  --destination ./manifests \
  --dependency-update

# Create release (includes packaged chart)
replicated release create \
  --app myapp \
  --yaml-dir ./manifests \
  --version 1.2.3
```

**Makefile pattern:**
```makefile
.PHONY: replicated-helm-package
replicated-helm-package:
	rm -f manifests/*.tgz
	helm package ./helm --destination manifests --dependency-update

.PHONY: replicated-release
replicated-release: replicated-helm-package
	@[ "${CHANNEL}" ] || ( echo ">> CHANNEL is not set"; exit 1 )
	@[ "${VERSION}" ] || ( echo ">> VERSION is not set"; exit 1 )
	replicated release create \
	  --app myapp \
	  --yaml-dir manifests \
	  --lint \
	  --promote $(CHANNEL) \
	  --version $(VERSION)
```

## Listing and Inspecting Releases

### List Recent Releases

```bash
# List last 10 releases
replicated release ls --app <app-slug>

# List with specific count
replicated release ls --app <app-slug> | head -n 20
```

**Output columns:**
- Sequence number
- Version label
- Created timestamp
- Channels (where promoted)

### Inspect Specific Release

```bash
# Get release details
replicated release inspect <sequence> --app <app-slug>
```

**Details include:**
- All manifests in the release
- Promoted channels
- Creation and modification timestamps
- Release notes (if provided)

### Download Release Manifests

```bash
# Download YAML for specific release
replicated release download <sequence> \
  --app <app-slug> \
  --dest ./downloaded-release
```

Use cases:
- Audit what was released
- Compare releases
- Debug customer installations
- Rollback reference

## Automated Release Pipelines

### CI/CD Integration

**GitHub Actions example:**
```yaml
name: Create Replicated Release
on:
  push:
    branches: [main]

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install Replicated CLI
        run: |
          curl -sSL https://raw.githubusercontent.com/replicatedhq/replicated/main/install.sh | bash

      - name: Create Release
        env:
          REPLICATED_API_TOKEN: ${{ secrets.REPLICATED_API_TOKEN }}
        run: |
          VERSION="${{ github.ref_name }}-${{ github.sha }}"
          replicated release create \
            --app ${{ secrets.REPLICATED_APP_SLUG }} \
            --yaml-dir ./manifests \
            --lint \
            --promote ${{ github.ref_name }} \
            --version $VERSION
```

### Makefile Integration

**Complete release workflow:**
```makefile
# Variables
APP_SLUG := myapp
CHANNEL ?= unstable
VERSION ?= $(shell cat VERSION)

.PHONY: release
release: lint package promote

.PHONY: lint
lint:
	@echo "Linting manifests..."
	replicated release lint --app $(APP_SLUG) --yaml-dir manifests

.PHONY: package
package:
	@echo "Packaging Helm charts..."
	rm -f manifests/*.tgz
	helm dependency update ./helm
	helm package ./helm --destination manifests

.PHONY: create
create: package
	@echo "Creating release $(VERSION)..."
	replicated release create \
	  --app $(APP_SLUG) \
	  --yaml-dir manifests \
	  --version $(VERSION)

.PHONY: promote
promote:
	@echo "Promoting to $(CHANNEL)..."
	@[ "$(CHANNEL)" ] || (echo "CHANNEL not set"; exit 1)
	@[ "$(VERSION)" ] || (echo "VERSION not set"; exit 1)
	$(eval SEQUENCE := $(shell replicated release ls --app $(APP_SLUG) | \
	  grep $(VERSION) | awk '{print $$1}' | head -1))
	replicated release promote $(SEQUENCE) $(CHANNEL) \
	  --app $(APP_SLUG) \
	  --version $(VERSION)

.PHONY: release-one-shot
release-one-shot: package
	@[ "$(CHANNEL)" ] || (echo "CHANNEL not set"; exit 1)
	@[ "$(VERSION)" ] || (echo "VERSION not set"; exit 1)
	replicated release create \
	  --app $(APP_SLUG) \
	  --yaml-dir manifests \
	  --lint \
	  --promote $(CHANNEL) \
	  --version $(VERSION)
```

## Release Notes

Add release notes via vendor portal or API:

```bash
# Create release with notes
replicated release create \
  --app myapp \
  --yaml-dir ./manifests \
  --version 1.2.3 \
  --release-notes "$(cat RELEASE_NOTES.md)"
```

**Best practices:**
- Use markdown formatting
- Highlight breaking changes
- List new features
- Document bug fixes
- Include upgrade instructions if needed

## Error Handling

### Common Errors

**"No such file or directory":**
- Verify `--yaml-dir` path exists
- Check current working directory
- Ensure manifest files have `.yaml` or `.yml` extension

**"Invalid YAML":**
- Run `replicated release lint` first
- Check for syntax errors in manifests
- Validate Kubernetes resource specs
- Review template rendering (for Helm charts)

**"Channel not found":**
- List channels: `replicated channel ls --app <app>`
- Create channel if needed: `replicated channel create --name <name> --app <app>`
- Check channel name spelling

**"App not found":**
- Verify app slug matches vendor portal
- Check authentication: `replicated whoami`
- Confirm API token has access to app

### Retry Strategies

For transient failures in automation:

```bash
# Retry with exponential backoff
for i in 1 2 3; do
  if replicated release create \
    --app myapp \
    --yaml-dir ./manifests \
    --version $VERSION; then
    break
  else
    echo "Attempt $i failed, retrying..."
    sleep $((i * 5))
  fi
done
```

## Advanced Patterns

### Multi-App Releases

For applications with multiple components:

```bash
# Release component A
replicated release create --app component-a --yaml-dir ./component-a/manifests --version 1.2.3

# Release component B (same version)
replicated release create --app component-b --yaml-dir ./component-b/manifests --version 1.2.3

# Release orchestrator (references components)
replicated release create --app orchestrator --yaml-dir ./orchestrator/manifests --version 1.2.3
```

### Coordinated Channel Promotion

Promote multiple apps to channels simultaneously:

```bash
apps=("component-a" "component-b" "orchestrator")
version="1.2.3"
channel="beta"

for app in "${apps[@]}"; do
  sequence=$(replicated release ls --app $app | grep $version | awk '{print $1}')
  replicated release promote $sequence $channel --app $app --version $version
done
```

### Release Rollback

To rollback, promote a previous sequence:

```bash
# List releases to find previous version
replicated release ls --app myapp

# Promote older sequence to channel
replicated release promote 40 stable --app myapp --version 1.2.2
```

Note: This creates a new promotion, doesn't delete the problematic release.

## Monitoring and Verification

### Verify Release Promotion

```bash
# Check which channels have a specific release
replicated release inspect <sequence> --app <app-slug> | grep -i channel

# List releases on a channel
replicated channel releases <channel-id> --app <app-slug>
```

### Customer Update Status

```bash
# List customer installations
replicated customer ls --app <app-slug>

# Check specific customer's version
replicated instance ls --customer <customer-id> --app <app-slug>
```

### Adoption Metrics

Track release adoption via vendor portal:
- Channel adoption rates
- Update latency (time from release to installation)
- Version distribution across customer base
- Update success/failure rates

## Best Practices Summary

**Before Creating Releases:**
- Always lint manifests first
- Test locally with `helm template` or `kustomize build`
- Review changes in source control
- Update VERSION file if using automated versioning

**Version Labeling:**
- Use semantic versioning consistently
- Include build metadata for traceability
- Match versions to git tags or commits
- Use pre-release labels for non-production releases

**Channel Strategy:**
- Use branch-named channels during development
- Maintain separate channels for testing stages (unstable, beta, stable)
- Clean up obsolete channels
- Document channel promotion criteria

**Automation:**
- Integrate with CI/CD pipelines
- Implement retry logic for transient failures
- Validate manifests before creating releases
- Store API tokens securely
- Use service accounts for automated releases

**Documentation:**
- Include release notes with every release
- Document breaking changes clearly
- Provide upgrade instructions when needed
- Maintain CHANGELOG in source control

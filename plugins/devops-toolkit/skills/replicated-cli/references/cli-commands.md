# Replicated CLI Command Reference

Complete reference for all Replicated CLI commands and options.

## Installation

```bash
# Install latest version
curl -sSL https://raw.githubusercontent.com/replicatedhq/replicated/main/install.sh | bash

# Install specific version
curl -sSL https://raw.githubusercontent.com/replicatedhq/replicated/main/install.sh | VERSION=<version> bash

# Check version
replicated version
```

## Authentication

### Login

```bash
# Interactive login (opens browser)
replicated login

# With API token
replicated login --token <api-token>

# Check authentication status
replicated whoami
```

### API Tokens

Tokens are managed at https://vendor.replicated.com/team/tokens

**Scopes:**
- `read:app` - Read application data
- `write:app` - Create/update releases, channels
- `read:customer` - Read customer data
- `write:customer` - Create/update customers
- `read:instance` - Read instance data

## Release Commands

### create

Create a new release from manifests.

```bash
replicated release create [flags]
```

**Required flags:**
- `--app <slug>` - Application slug
- `--yaml-dir <path>` - Directory containing manifest files

**Optional flags:**
- `--version <version>` - Version label (semantic version)
- `--release-notes <text>` - Release notes (supports markdown)
- `--lint` - Lint manifests before creating
- `--promote <channel>` - Promote immediately to channel
- `--required` - Mark as required update
- `--entitlements <json>` - Entitlement values

**Examples:**
```bash
# Basic release
replicated release create --app myapp --yaml-dir ./manifests --version 1.2.3

# With linting and promotion
replicated release create \
  --app myapp \
  --yaml-dir ./manifests \
  --lint \
  --promote stable \
  --version 1.2.3

# With release notes
replicated release create \
  --app myapp \
  --yaml-dir ./manifests \
  --version 1.2.3 \
  --release-notes "$(cat RELEASE_NOTES.md)"
```

### lint

Validate manifest files without creating release.

```bash
replicated release lint [flags]
```

**Flags:**
- `--app <slug>` - Application slug
- `--yaml-dir <path>` - Directory containing manifest files

**Example:**
```bash
replicated release lint --app myapp --yaml-dir ./manifests
```

### promote

Promote existing release to channel.

```bash
replicated release promote <sequence> <channel> [flags]
```

**Arguments:**
- `<sequence>` - Release sequence number
- `<channel>` - Channel name or ID

**Flags:**
- `--app <slug>` - Application slug
- `--version <version>` - Version label
- `--release-notes <text>` - Release notes
- `--required` - Mark as required update

**Example:**
```bash
replicated release promote 42 stable --app myapp --version 1.2.3
```

### ls

List releases.

```bash
replicated release ls [flags]
```

**Flags:**
- `--app <slug>` - Application slug
- `--output <format>` - Output format (`table`, `json`, `wide`)

**Example:**
```bash
# Table format (default)
replicated release ls --app myapp

# JSON format
replicated release ls --app myapp --output json

# Show first 10
replicated release ls --app myapp | head -n 10
```

### inspect

Show detailed information about a release.

```bash
replicated release inspect <sequence> [flags]
```

**Arguments:**
- `<sequence>` - Release sequence number

**Flags:**
- `--app <slug>` - Application slug

**Example:**
```bash
replicated release inspect 42 --app myapp
```

### download

Download release manifests.

```bash
replicated release download <sequence> [flags]
```

**Arguments:**
- `<sequence>` - Release sequence number

**Flags:**
- `--app <slug>` - Application slug
- `--dest <path>` - Destination directory (default: current directory)

**Example:**
```bash
replicated release download 42 --app myapp --dest ./release-42
```

## Channel Commands

### ls

List channels.

```bash
replicated channel ls [flags]
```

**Flags:**
- `--app <slug>` - Application slug
- `--output <format>` - Output format (`table`, `json`)

**Example:**
```bash
replicated channel ls --app myapp
```

### create

Create a new channel.

```bash
replicated channel create [flags]
```

**Flags:**
- `--app <slug>` - Application slug
- `--name <name>` - Channel name
- `--description <text>` - Channel description

**Example:**
```bash
replicated channel create --app myapp --name beta --description "Beta testing channel"
```

### inspect

Show channel details.

```bash
replicated channel inspect <channel-id> [flags]
```

**Arguments:**
- `<channel-id>` - Channel ID

**Flags:**
- `--app <slug>` - Application slug

**Example:**
```bash
replicated channel inspect abc123 --app myapp
```

### releases

List releases on a channel.

```bash
replicated channel releases <channel-id> [flags]
```

**Arguments:**
- `<channel-id>` - Channel ID

**Flags:**
- `--app <slug>` - Application slug

**Example:**
```bash
replicated channel releases abc123 --app myapp
```

## Customer Commands

### ls

List customers.

```bash
replicated customer ls [flags]
```

**Flags:**
- `--app <slug>` - Application slug
- `--output <format>` - Output format (`table`, `json`)

**Example:**
```bash
replicated customer ls --app myapp
```

### create

Create a new customer.

```bash
replicated customer create [flags]
```

**Flags:**
- `--app <slug>` - Application slug
- `--name <name>` - Customer name
- `--channel <channel>` - Channel name or ID
- `--email <email>` - Customer email
- `--license-type <type>` - License type (`dev`, `trial`, `paid`)
- `--expires-in <duration>` - Expiration (e.g., `30d`, `1y`)
- `--entitlements <json>` - Entitlement values

**Example:**
```bash
replicated customer create \
  --app myapp \
  --name "Acme Corp" \
  --channel stable \
  --email "admin@acme.com" \
  --license-type trial \
  --expires-in 30d
```

### inspect

Show customer details.

```bash
replicated customer inspect <customer-id> [flags]
```

**Arguments:**
- `<customer-id>` - Customer ID

**Flags:**
- `--app <slug>` - Application slug

**Example:**
```bash
replicated customer inspect xyz789 --app myapp
```

### download-license

Download customer license file.

```bash
replicated customer download-license <customer-id> [flags]
```

**Arguments:**
- `<customer-id>` - Customer ID

**Flags:**
- `--app <slug>` - Application slug
- `--output <path>` - Output file path

**Example:**
```bash
replicated customer download-license xyz789 --app myapp --output license.yaml
```

## Instance Commands

### ls

List customer instances.

```bash
replicated instance ls [flags]
```

**Flags:**
- `--app <slug>` - Application slug
- `--customer <id>` - Filter by customer ID
- `--output <format>` - Output format (`table`, `json`)

**Example:**
```bash
# All instances
replicated instance ls --app myapp

# Specific customer
replicated instance ls --app myapp --customer xyz789
```

### inspect

Show instance details.

```bash
replicated instance inspect <instance-id> [flags]
```

**Arguments:**
- `<instance-id>` - Instance ID

**Flags:**
- `--app <slug>` - Application slug

**Example:**
```bash
replicated instance inspect inst-abc123 --app myapp
```

## VM Commands (CMX)

### create

Create test VMs.

```bash
replicated vm create [flags]
```

**Required flags:**
- `--name <name>` - VM name (must be unique)

**Optional flags:**
- `--distribution <dist>` - OS distribution (default: `ubuntu`)
  - Options: `ubuntu`, `almalinux`
- `--version <version>` - OS version (default: `24.04`)
  - Ubuntu: `22.04`, `24.04`
  - AlmaLinux: `8`
- `--instance-type <type>` - VM size (default: `r1.medium`)
  - Options: `r1.medium` (4 vCPU, 8GB RAM), `r1.large` (8 vCPU, 16GB RAM), `r1.xlarge` (16 vCPU, 32GB RAM)
- `--disk <size>` - Disk size in GB (default: 50)
- `--ttl <duration>` - Time to live (default: `8h`)
  - Examples: `1h`, `8h`, `24h`, `7d`
- `--count <n>` - Number of VMs to create (default: 1)
- `--network <id>` - Network ID (for multi-node clusters)
- `--tag <key>=<value>` - Tags (can be specified multiple times)
- `--ssh-public-key <path>` - SSH public key file
- `--ssh-public-key-github <username>` - GitHub username for SSH keys
- `--wait <duration>` - Wait for VM to be ready
  - Examples: `5m`, `10m`

**Examples:**
```bash
# Single VM
replicated vm create \
  --name test-vm \
  --distribution ubuntu \
  --version 24.04 \
  --instance-type r1.medium \
  --disk 100 \
  --ttl 8h \
  --wait 5m

# With tags
replicated vm create \
  --name myapp-control-1 \
  --distribution ubuntu \
  --version 24.04 \
  --instance-type r1.xlarge \
  --disk 100 \
  --ttl 8h \
  --tag role=control \
  --tag cluster=myapp \
  --wait 5m

# On existing network
replicated vm create \
  --name myapp-control-2 \
  --distribution ubuntu \
  --version 24.04 \
  --instance-type r1.xlarge \
  --disk 100 \
  --ttl 8h \
  --network net-abc123 \
  --tag role=control \
  --tag cluster=myapp \
  --wait 5m

# With GitHub SSH keys
replicated vm create \
  --name test-vm \
  --distribution ubuntu \
  --version 24.04 \
  --ssh-public-key-github adamancini
```

### ls

List VMs.

```bash
replicated vm ls [flags]
```

**Flags:**
- `--output <format>` - Output format (`table`, `json`, `wide`)

**Examples:**
```bash
# Table format
replicated vm ls

# JSON format
replicated vm ls --output json

# Filter by tag
replicated vm ls --output json | jq '.[] | select(.tags.cluster == "myapp")'
```

### ssh

SSH to a VM.

```bash
replicated vm ssh <vm-id-or-name> [-- <command>]
```

**Arguments:**
- `<vm-id-or-name>` - VM ID or name
- `<command>` - Optional command to execute (use `--` separator)

**Examples:**
```bash
# Interactive SSH
replicated vm ssh myapp-control-1

# Execute command
replicated vm ssh myapp-control-1 -- 'kubectl get nodes'

# With sudo
replicated vm ssh myapp-control-1 -- 'sudo systemctl status k0scontroller'

# Multi-line command
replicated vm ssh myapp-control-1 -- 'kubectl get nodes && kubectl get pods -A'
```

### inspect

Show VM details.

```bash
replicated vm inspect <vm-id> [flags]
```

**Arguments:**
- `<vm-id>` - VM ID

**Example:**
```bash
replicated vm inspect vm-abc123
```

### rm

Delete VMs.

```bash
replicated vm rm <vm-id> [<vm-id> ...]
```

**Arguments:**
- `<vm-id>` - VM ID(s) to delete

**Examples:**
```bash
# Delete single VM
replicated vm rm vm-abc123

# Delete multiple VMs
replicated vm rm vm-abc123 vm-def456 vm-ghi789

# Delete all VMs with tag
replicated vm ls --output json | \
  jq -r '.[] | select(.tags.cluster == "myapp") | .id' | \
  xargs replicated vm rm
```

### stop

Stop running VM.

```bash
replicated vm stop <vm-id>
```

**Arguments:**
- `<vm-id>` - VM ID

**Example:**
```bash
replicated vm stop vm-abc123
```

### start

Start stopped VM.

```bash
replicated vm start <vm-id>
```

**Arguments:**
- `<vm-id>` - VM ID

**Example:**
```bash
replicated vm start vm-abc123
```

### restart

Restart VM.

```bash
replicated vm restart <vm-id>
```

**Arguments:**
- `<vm-id>` - VM ID

**Example:**
```bash
replicated vm restart vm-abc123
```

### port expose

Expose VM port for external access.

```bash
replicated vm port expose <vm-id> [flags]
```

**Arguments:**
- `<vm-id>` - VM ID

**Flags:**
- `--host-port <port>` - Port to expose
- `--vm-port <port>` - VM port (defaults to host-port)
- `--protocols <list>` - Comma-separated protocols
  - Options: `http`, `https`, `tcp`, `udp`

**Examples:**
```bash
# Expose single port
replicated vm port expose vm-abc123 --host-port 30000 --protocols http,https

# Different host and VM ports
replicated vm port expose vm-abc123 --host-port 8080 --vm-port 80 --protocols http
```

### port ls

List exposed ports.

```bash
replicated vm port ls <vm-id> [flags]
```

**Arguments:**
- `<vm-id>` - VM ID

**Flags:**
- `--output <format>` - Output format (`table`, `json`)

**Example:**
```bash
replicated vm port ls vm-abc123
```

### port rm

Remove exposed port.

```bash
replicated vm port rm <vm-id> --host-port <port>
```

**Arguments:**
- `<vm-id>` - VM ID

**Flags:**
- `--host-port <port>` - Port to remove

**Example:**
```bash
replicated vm port rm vm-abc123 --host-port 30000
```

## App Commands

### ls

List applications.

```bash
replicated app ls [flags]
```

**Flags:**
- `--output <format>` - Output format (`table`, `json`)

**Example:**
```bash
replicated app ls
```

### inspect

Show application details.

```bash
replicated app inspect <app-slug> [flags]
```

**Arguments:**
- `<app-slug>` - Application slug

**Example:**
```bash
replicated app inspect myapp
```

## Global Flags

These flags apply to all commands:

- `--token <token>` - API token (overrides login)
- `--endpoint <url>` - API endpoint (default: https://api.replicated.com/vendor)
- `--output <format>` - Output format (`table`, `json`, `wide`)
- `--help` - Show help for command
- `--version` - Show CLI version

## Environment Variables

Configure CLI behavior via environment variables:

- `REPLICATED_API_TOKEN` - API token (alternative to `--token`)
- `REPLICATED_APP` - Default app slug (alternative to `--app`)
- `REPLICATED_API_ENDPOINT` - API endpoint (alternative to `--endpoint`)

**Example:**
```bash
export REPLICATED_API_TOKEN="..."
export REPLICATED_APP="myapp"

# Now --token and --app are optional
replicated release ls
```

## Output Formats

### Table (Default)

Human-readable table format with columns:

```
SEQUENCE  VERSION  CREATED              CHANNELS
42        1.2.3    2025-01-19 10:30:00  stable, beta
41        1.2.2    2025-01-18 15:20:00  beta
```

### JSON

Machine-parseable JSON format for scripting:

```json
[
  {
    "sequence": 42,
    "version": "1.2.3",
    "created": "2025-01-19T10:30:00Z",
    "channels": ["stable", "beta"]
  }
]
```

Use with `jq` for filtering:

```bash
replicated release ls --app myapp --output json | \
  jq '.[] | select(.version == "1.2.3")'
```

### Wide

Extended table format with additional columns.

## Error Handling

### Common Error Codes

- `401 Unauthorized` - Authentication failure (check token)
- `403 Forbidden` - Insufficient permissions (check token scopes)
- `404 Not Found` - Resource doesn't exist (check app slug, sequence, etc.)
- `409 Conflict` - Resource already exists (unique name violation)
- `422 Unprocessable Entity` - Validation error (check manifest syntax)
- `429 Too Many Requests` - Rate limit exceeded (retry with backoff)
- `500 Internal Server Error` - Server error (retry or contact support)

### Exit Codes

- `0` - Success
- `1` - General error
- `2` - Usage error (invalid flags/arguments)

## Examples and Patterns

### CI/CD Integration

```bash
#!/bin/bash
set -e

# Authenticate
export REPLICATED_API_TOKEN="${REPLICATED_TOKEN}"
export REPLICATED_APP="myapp"

# Generate version
VERSION="${CI_BRANCH}-${CI_COMMIT_SHORT}"

# Create and promote
replicated release create \
  --yaml-dir ./manifests \
  --lint \
  --promote "${CI_BRANCH}" \
  --version "${VERSION}"
```

### Multi-Node Testing

```bash
#!/bin/bash
set -e

CLUSTER="test-$(date +%s)"

# Create control node
replicated vm create \
  --name "${CLUSTER}-control-1" \
  --distribution ubuntu --version 24.04 \
  --instance-type r1.xlarge \
  --disk 100 --ttl 8h \
  --tag cluster="${CLUSTER}" \
  --wait 5m

# Get network ID
NETWORK=$(replicated vm ls --output json | \
  jq -r ".[] | select(.name == \"${CLUSTER}-control-1\") | .network_id")

# Create worker nodes
for i in 1 2; do
  replicated vm create \
    --name "${CLUSTER}-worker-${i}" \
    --distribution ubuntu --version 24.04 \
    --instance-type r1.xlarge \
    --disk 100 --ttl 8h \
    --network "${NETWORK}" \
    --tag cluster="${CLUSTER}" \
    --wait 5m &
done
wait

echo "Cluster ${CLUSTER} ready"
```

### Release Rollback

```bash
#!/bin/bash
set -e

APP="myapp"
CHANNEL="stable"
PREVIOUS_VERSION="1.2.2"

# Find previous version sequence
SEQUENCE=$(replicated release ls --app "${APP}" --output json | \
  jq -r ".[] | select(.version == \"${PREVIOUS_VERSION}\") | .sequence" | head -1)

# Promote to channel
replicated release promote "${SEQUENCE}" "${CHANNEL}" \
  --app "${APP}" \
  --version "${PREVIOUS_VERSION}" \
  --release-notes "Rollback to ${PREVIOUS_VERSION}"
```

## Further Reading

- **Vendor Documentation**: https://docs.replicated.com/vendor
- **CLI Reference**: https://docs.replicated.com/reference/vendor-cli
- **API Documentation**: https://docs.replicated.com/reference/vendor-api
- **GitHub Repository**: https://github.com/replicatedhq/replicated

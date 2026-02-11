# Ansible Inventory Patterns Reference

Comprehensive reference for Ansible inventory formats, organization patterns, and dynamic inventory configurations.

## INI Format

The traditional inventory format, suitable for simple environments.

### Basic Structure

```ini
# Single hosts
mail.example.com

# Grouped hosts
[webservers]
web1.example.com ansible_host=10.0.1.10
web2.example.com ansible_host=10.0.1.11
web3.example.com ansible_host=10.0.1.12

[databases]
db1.example.com ansible_host=10.0.2.10 ansible_port=5432
db2.example.com ansible_host=10.0.2.11 ansible_port=5432

[loadbalancers]
lb1.example.com ansible_host=10.0.0.10
```

### Group Variables

```ini
[webservers:vars]
http_port=80
ansible_user=deploy
ansible_python_interpreter=/usr/bin/python3
```

### Group Inheritance (Children)

```ini
[production:children]
webservers
databases
loadbalancers

[production:vars]
env=production
monitoring_enabled=true
```

### Range Patterns

```ini
[webservers]
web[01:10].example.com     # web01 through web10
web-[a:f].example.com      # web-a through web-f

[databases]
db-[1:3].dc[1:2].example.com  # db-1.dc1, db-1.dc2, db-2.dc1, etc.
```

---

## YAML Format

More expressive format, preferred for complex inventories.

### Basic Structure

```yaml
all:
  hosts:
    mail.example.com:
  children:
    webservers:
      hosts:
        web1.example.com:
          ansible_host: 10.0.1.10
        web2.example.com:
          ansible_host: 10.0.1.11
      vars:
        http_port: 80
        ansible_user: deploy

    databases:
      hosts:
        db1.example.com:
          ansible_host: 10.0.2.10
          postgresql_port: 5432
        db2.example.com:
          ansible_host: 10.0.2.11
          postgresql_port: 5432
      vars:
        ansible_user: dbadmin

    production:
      children:
        webservers:
        databases:
      vars:
        env: production
        monitoring_enabled: true
```

### Multi-Environment Inventory

```yaml
all:
  children:
    staging:
      children:
        staging_web:
          hosts:
            stg-web1.example.com:
        staging_db:
          hosts:
            stg-db1.example.com:
      vars:
        env: staging
        debug_mode: true

    production:
      children:
        production_web:
          hosts:
            prod-web[1:3].example.com:
        production_db:
          hosts:
            prod-db1.example.com:
            prod-db2.example.com:
      vars:
        env: production
        debug_mode: false
```

---

## Variable File Organization

### Directory Structure

```
inventory/
├── production/
│   ├── hosts.yml                # Host definitions
│   ├── group_vars/
│   │   ├── all/
│   │   │   ├── vars.yml         # Non-sensitive defaults
│   │   │   └── vault.yml        # Vault-encrypted secrets
│   │   ├── webservers/
│   │   │   ├── nginx.yml        # nginx-specific vars
│   │   │   └── ssl.yml          # SSL configuration
│   │   └── databases/
│   │       ├── postgresql.yml   # PostgreSQL config
│   │       └── vault.yml        # DB secrets (encrypted)
│   └── host_vars/
│       ├── web1.example.com.yml # Host-specific overrides
│       └── db1.example.com.yml
└── staging/
    ├── hosts.yml
    ├── group_vars/
    │   └── all/
    │       └── vars.yml
    └── host_vars/
```

### group_vars Examples

**`group_vars/all/vars.yml`** (shared defaults):
```yaml
---
ntp_servers:
  - 0.pool.ntp.org
  - 1.pool.ntp.org
dns_servers:
  - 8.8.8.8
  - 8.8.4.4
ansible_python_interpreter: /usr/bin/python3
```

**`group_vars/webservers/nginx.yml`** (group-specific):
```yaml
---
nginx_worker_processes: auto
nginx_worker_connections: 1024
nginx_keepalive_timeout: 65
nginx_client_max_body_size: 64m
nginx_ssl_protocols: "TLSv1.2 TLSv1.3"
```

**`group_vars/all/vault.yml`** (encrypted):
```yaml
---
vault_deploy_key: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  ...encrypted content...
vault_api_token: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  ...encrypted content...
```

### host_vars Examples

**`host_vars/web1.example.com.yml`**:
```yaml
---
# Override for this specific host
nginx_worker_processes: 4  # This host has 4 cores
custom_vhosts:
  - domain: api.example.com
    port: 8080
  - domain: admin.example.com
    port: 8081
```

---

## Dynamic Inventory

### Script-Based Dynamic Inventory

Dynamic inventory scripts must return JSON in this structure when called with `--list`:

```json
{
  "webservers": {
    "hosts": ["web1.example.com", "web2.example.com"],
    "vars": {
      "http_port": 80
    }
  },
  "databases": {
    "hosts": ["db1.example.com"]
  },
  "_meta": {
    "hostvars": {
      "web1.example.com": {
        "ansible_host": "10.0.1.10"
      },
      "web2.example.com": {
        "ansible_host": "10.0.1.11"
      },
      "db1.example.com": {
        "ansible_host": "10.0.2.10"
      }
    }
  }
}
```

When called with `--host <hostname>`, return host-specific variables:

```json
{
  "ansible_host": "10.0.1.10",
  "http_port": 80
}
```

### AWS EC2 Inventory Plugin

**`inventory/aws_ec2.yml`**:
```yaml
---
plugin: amazon.aws.aws_ec2
regions:
  - us-east-1
  - us-west-2

filters:
  tag:Environment:
    - production
  instance-state-name:
    - running

keyed_groups:
  - key: tags.Role
    prefix: role
    separator: "_"
  - key: placement.availability_zone
    prefix: az
  - key: instance_type
    prefix: type

hostnames:
  - tag:Name
  - private-ip-address

compose:
  ansible_host: private_ip_address
  ansible_user: "'ubuntu'"
```

Usage: `ansible-playbook -i inventory/aws_ec2.yml playbook.yml`

Requires: `amazon.aws` collection and `boto3` Python library.

### GCP Inventory Plugin

**`inventory/gcp_compute.yml`**:
```yaml
---
plugin: google.cloud.gcp_compute
projects:
  - my-gcp-project
zones:
  - us-central1-a
  - us-central1-b

filters:
  - status = RUNNING
  - labels.env = production

keyed_groups:
  - key: labels.role
    prefix: role
  - key: zone
    prefix: zone

hostnames:
  - name
  - private_ip

compose:
  ansible_host: networkInterfaces[0].networkIP
```

Requires: `google.cloud` collection and `google-auth` Python library.

### Constructed Inventory Plugin

Build dynamic groups from host variables and facts:

```yaml
---
plugin: ansible.builtin.constructed
strict: false

groups:
  # Create group from variable value
  webservers: "'web' in group_names"
  big_memory: ansible_memtotal_mb >= 16384
  debian_hosts: ansible_os_family == "Debian"

keyed_groups:
  - key: ansible_distribution | lower
    prefix: os
  - key: ansible_distribution_major_version
    prefix: os_version

compose:
  # Create new variables
  datacenter: "'dc1' if ansible_default_ipv4.address.startswith('10.0') else 'dc2'"
```

---

## Host Connection Variables

Common variables set per-host or per-group:

| Variable | Description | Default |
|---|---|---|
| `ansible_host` | IP or hostname to connect to | inventory hostname |
| `ansible_port` | SSH port | 22 |
| `ansible_user` | SSH user | current user |
| `ansible_ssh_private_key_file` | SSH private key path | |
| `ansible_python_interpreter` | Python path on managed node | /usr/bin/python |
| `ansible_connection` | Connection type | ssh |
| `ansible_become` | Enable privilege escalation | false |
| `ansible_become_method` | Escalation method | sudo |
| `ansible_become_user` | Target user for escalation | root |
| `ansible_become_password` | Escalation password | |
| `ansible_ssh_common_args` | Extra SSH arguments | |

### Connection Types

```yaml
# SSH (default for Linux)
ansible_connection: ssh

# Local execution (for localhost)
ansible_connection: local

# Docker container
ansible_connection: community.docker.docker

# WinRM (for Windows)
ansible_connection: winrm
ansible_winrm_transport: ntlm

# Network devices
ansible_connection: ansible.netcommon.network_cli
ansible_network_os: cisco.ios.ios
```

---

## Inventory Targeting Patterns

Use `--limit` or `hosts:` patterns to target specific hosts:

| Pattern | Meaning |
|---|---|
| `all` | All hosts |
| `webservers` | All hosts in group |
| `web1.example.com` | Single host |
| `webservers:databases` | Union (OR) |
| `webservers:&production` | Intersection (AND) |
| `webservers:!staging` | Exclusion (NOT) |
| `~web\d+\.example\.com` | Regex match |
| `webservers[0]` | First host in group |
| `webservers[0:2]` | First three hosts |
| `webservers[-1]` | Last host in group |

### Examples

```bash
# Target specific group
ansible-playbook playbook.yml --limit webservers

# Target intersection
ansible-playbook playbook.yml --limit 'webservers:&production'

# Exclude staging
ansible-playbook playbook.yml --limit 'all:!staging'

# Single host
ansible-playbook playbook.yml --limit web1.example.com

# Multiple patterns
ansible-playbook playbook.yml --limit 'webservers:databases:!db2.example.com'
```

---

## Best Practices

1. **Use directories, not single files** for `group_vars/` and `host_vars/` - split by concern (e.g., `nginx.yml`, `ssl.yml`, `vault.yml`)
2. **Prefix variable names** with the group or role name to avoid collisions
3. **Separate environments** into distinct inventory directories (`production/`, `staging/`)
4. **Use meaningful group names** reflecting function (`webservers`) not hostnames (`web1_web2`)
5. **Keep vault-encrypted variables** in dedicated `vault.yml` files alongside plaintext `vars.yml`
6. **Use `_meta` in dynamic inventory** to avoid per-host API calls
7. **Document group purposes** with comments in inventory files
8. **Test inventory** with `ansible-inventory --list` to verify group membership and variable resolution

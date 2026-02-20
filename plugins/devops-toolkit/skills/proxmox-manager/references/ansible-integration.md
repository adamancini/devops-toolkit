# Ansible Integration Reference

For multi-node orchestration, delegate to existing Ansible playbooks in the fleet-infra repository. The repository path and inventory are defined in the `ansible` section of `cluster-config.yaml`. The skill does **not** modify Ansible playbooks or inventory files -- it is a consumer of existing automation, not an editor.

## Prerequisites

The Proxmox Ansible playbooks require the `community.proxmox` collection:

```bash
ansible-galaxy collection install community.proxmox
```

**Module name:** `community.proxmox.proxmox_kvm` (not the deprecated `proxmox_kvm`)

**API token format for Ansible** (differs from the curl `PVEAPIToken` header format):
- `api_token_id`: `user@pve!tokenname` (same as line 1 of the `pass` entry)
- `api_token_secret`: the UUID secret (same as line 2 of the `pass` entry)

## General Delegation Pattern

```bash
ansible-playbook \
  -i <FLEET_INFRA_PATH>/<INVENTORY> \
  <FLEET_INFRA_PATH>/playbooks/<playbook>.yaml
```

Where `<FLEET_INFRA_PATH>` is `ansible.fleet_infra_path` and `<INVENTORY>` is `ansible.inventory` from `cluster-config.yaml`.

## Available Playbooks

| Playbook | Purpose | Tags |
|----------|---------|------|
| `talos-provision-vms.yaml` | Provision Talos VMs via Proxmox API (clone, configure, start) | `controlplane`, `workers` |
| `reboot-vms.yaml` | Rolling reboot of VMs by group | -- |
| `pve-servers.yaml` | Proxmox host configuration and maintenance | -- |
| `ping.yaml` | Connectivity check for all hosts in inventory | -- |

## Talos Cluster Provisioning via Ansible

**Extract Proxmox API token for Ansible:**

```bash
PROXMOX_API_TOKEN="$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)"
```

**Full cluster provisioning:**

```bash
PROXMOX_API_TOKEN="$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  ansible-playbook \
  -i <FLEET_INFRA_PATH>/<INVENTORY> \
  <FLEET_INFRA_PATH>/playbooks/talos-provision-vms.yaml
```

**Control plane only:** Add `--tags controlplane`

**Workers only:** Add `--tags workers`

## When to Use Ansible vs Direct API

| Use Ansible when... | Use direct API when... |
|----------------------|------------------------|
| The topology matches the existing playbook | Custom placement or sizing |
| Single command for the full lifecycle | Step-by-step control with verification |
| Inventory already defines target hosts | New profile not in inventory |
| Rolling operations across many nodes | Single-VM operations |

## Fleet-Wide Operations

Target specific hosts or groups using `--limit`:

```bash
ansible-playbook \
  -i <FLEET_INFRA_PATH>/<INVENTORY> \
  <FLEET_INFRA_PATH>/playbooks/<playbook>.yaml \
  --limit <PATTERN>
```

| Pattern | Matches |
|---------|---------|
| `controlplane` | All control plane nodes |
| `workers` | All worker nodes |
| `pve01` | Single Proxmox host |
| `pve*` | All Proxmox hosts |
| `k0s01,k0s02` | Specific nodes by name |
| `all:!workers` | Everything except workers |

## Host Configuration Automation

While the sections above cover **VM provisioning** playbooks, this section addresses **hypervisor host configuration** -- ensuring every Proxmox node has consistent network, repository, certificate, NTP, monitoring, and user management settings.

### Architecture: Role-Based Desired State

Host configuration uses a modular Ansible role architecture where each configuration domain is an independent role. A top-level role list controls which domains are active:

```yaml
# defaults/main.yml -- toggle roles on/off
roles:
  - network
  - repositories
  - certificates
  - ntp
  - monitoring
  - notifications
  - certbot
  - usermgmt
```

The main playbook dynamically includes enabled roles:

```yaml
---
- hosts: all
  gather_facts: true
  tasks:
    - name: Include roles
      include_vars: defaults/main.yml

    - name: Include {{ roles | length }} role(s)
      include_role:
        name: "{{ role.split('#')[0] }}"
        tasks_from: "{{ role.split('#')[1] | default('main') }}"
      with_items: "{{ roles }}"
      loop_control:
        loop_var: role
```

The `role.split('#')` pattern allows targeting specific task files (e.g., `network#vlans` runs `roles/network/tasks/vlans.yml`).

### Configuration Domains

| Role | Purpose |
|------|---------|
| `network` | Bridge/interface configuration, VLAN-aware bridges |
| `repositories` | APT repository management (enterprise/no-subscription, Ceph) |
| `certificates` | SSL/TLS certificate deployment for Proxmox web UI |
| `ntp` | Time synchronization (chrony/systemd-timesyncd) |
| `monitoring` | Monitoring agent installation and configuration |
| `notifications` | Alert/notification channel setup |
| `certbot` | Let's Encrypt certificate automation |
| `usermgmt` | Host-level user/group/permission management |

### Network Configuration Pattern

The network role uses a data-driven approach with Jinja2 templating. Full reference material with all code examples is available in the knowledge base at `skills/knowledge-base/reference/proxmox-ansible-host-config/ansible-host-configuration.md`.

### When to Use Host Config Automation

| Use host config automation when... | Use the Proxmox API when... |
|-------------------------------------|------------------------------|
| Onboarding new Proxmox nodes | Creating/managing VMs |
| Enforcing consistent network bridges | Configuring individual VM settings |
| Managing host-level certificates | Cloning templates, migrating VMs |
| Recovering from host reinstallation | Cluster lifecycle (create/teardown) |
| Preventing configuration drift at scale | Single-node status checks |

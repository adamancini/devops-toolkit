---
topic: proxmox-ansible-host-config
source: https://jysk.tech/automate-the-process-of-proxmox-configuration-27466f415240
created: 2026-02-20
updated: 2026-02-20
tags:
  - proxmox
  - ansible
  - infrastructure-as-code
  - configuration-management
  - hypervisor
---

# Ansible-Based Proxmox Host Configuration

## Summary

Automates Proxmox VE hypervisor configuration (not installation) using Ansible roles for desired-state management. Prevents configuration drift across large Proxmox clusters by codifying host settings (network, repositories, certificates, NTP, monitoring, notifications, certbot, user management) as declarative Ansible roles that can be individually enabled/disabled. Originally developed at JYSK for managing a large-scale Proxmox deployment.

## Key Concepts

### Scope: Host Configuration, Not VM Management

This pattern handles **hypervisor-level** configuration -- the Proxmox host itself. It is complementary to (not a replacement for) VM lifecycle management via the Proxmox API. Proxmox must already be installed and reachable over SSH.

### Role-Based Architecture

Each configuration domain is an independent Ansible role created via `ansible-galaxy init <role_name>`. Roles are toggled on/off through a top-level `defaults/main.yml` role list:

```yaml
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

Comment out a role to disable it. This makes configuration modular and auditable.

### Dynamic Role Inclusion

The main playbook dynamically includes roles from the list, supporting task-specific execution via a `#` separator:

```yaml
---
- hosts: all
  gather_facts: true
  tasks:
    - name: Include roles
      include_vars: defaults/main.yml

    - debug:
        msg: "{{ roles | length }} role(s)"

    - name: Include {{ roles | length }} role(s)
      include_role:
        name: "{{ role.split('#')[0] }}"
        tasks_from: "{{ role.split('#')[1] | default('main') }}"
      with_items: "{{ roles }}"
      loop_control:
        loop_var: role
```

The `role.split('#')` pattern allows targeting specific task files within a role (e.g., `network#vlans` would run `roles/network/tasks/vlans.yml`).

### Configuration Domains

| Role | Purpose |
|------|---------|
| `network` | Bridge/interface configuration, VLAN-aware bridges, management + trunk interfaces |
| `repositories` | APT repository management (Proxmox enterprise/no-subscription, Ceph, etc.) |
| `certificates` | SSL/TLS certificate deployment for the Proxmox web UI |
| `ntp` | Time synchronization (chrony/systemd-timesyncd) |
| `monitoring` | Monitoring agent installation and configuration |
| `notifications` | Alert/notification channel setup |
| `certbot` | Let's Encrypt certificate automation |
| `usermgmt` | User/group/permission management on the host |

## Practical Application

### Directory Structure

```
├── inventory
├── main.yml
├── defaults/
│   └── main.yml          # Role toggle list
├── roles/
│   ├── network/
│   │   ├── defaults/
│   │   │   └── main.yml  # networkfacts variable
│   │   ├── tasks/
│   │   │   └── main.yml
│   │   └── templates/
│   │       └── networkconfig.j2
│   ├── repositories/
│   ├── certificates/
│   ├── ntp/
│   ├── monitoring/
│   ├── notifications/
│   ├── certbot/
│   └── usermgmt/
```

### Inventory

```ini
[server]
pve01.example.com

[server:vars]
ansible_user="root"
ansible_password="<proxmox root password>"
```

For production, use SSH keys or Ansible Vault instead of plaintext passwords.

### Network Configuration Pattern

**Data definition** (`roles/network/defaults/main.yml`):

```yaml
---
networkfacts:
  - mgmt:
    type: mgmt
    bridge: vmbr0
    int: [ens192]
    intmode: manual
    bridgemode: static
    ipaddress: "192.168.100.10/24"
    gateway: "192.168.100.1"
  - trunk:
    bridge: vmbr1
    int: [ens224]
    type: trunk
    intmode: manual
    bridgemode: static
```

**Jinja2 template** (`roles/network/templates/networkconfig.j2`):

```jinja2
auto lo
iface lo inet loopback

{% for item in networkfacts %}
iface {{ item.int }} inet {{ item.intmode }}
{% endfor %}

{% for item in networkfacts %}
iface {{ item.bridge }} inet {{ item.bridgemode }}
        {% if item.ipaddress is defined -%}
        address {{ item.ipaddress }}
        gateway {{ item.gateway }}
        {%- endif %}
        bridge-ports {{ item.int }}
        bridge-stp off
        bridge-fd 0
        {% if item.type == 'trunk' -%}
        bridge-vlan-aware yes
        bridge-vids 2-4094
        {%- endif %}
{% endfor %}

source /etc/network/interfaces.d/*
```

**Task** (`roles/network/tasks/main.yml`):

```yaml
---
- include_vars: "../defaults/main.yml"

- name: Create network resources
  template:
    src: "../templates/networkconfig.j2"
    dest: "/etc/network/interfaces"
```

### Execution

```bash
ansible-playbook -i inventory main.yml
```

## Decision Points

### When to Use This Pattern

- Managing 3+ Proxmox hosts where manual config becomes error-prone
- Need to enforce consistent network, repo, certificate, and NTP settings across nodes
- Onboarding new Proxmox hosts to match existing cluster configuration
- Recovering from host reinstallation -- reapply full config in one command

### When NOT to Use This Pattern

- Single-host Proxmox installations where manual config is manageable
- VM lifecycle management (use Proxmox API or Terraform instead)
- Proxmox cluster formation (corosync/cluster join) -- handle separately
- Storage backend configuration that requires PVE-specific CLI tools

### Complementary Approaches

| Layer | Tool | Scope |
|-------|------|-------|
| Host OS configuration | **Ansible roles** (this pattern) | Network, repos, certs, NTP, monitoring |
| Proxmox cluster formation | Manual or dedicated playbook | `pvecm create`, `pvecm add` |
| VM lifecycle | Proxmox REST API / Terraform | Create, clone, migrate, delete VMs |
| Guest OS configuration | Ansible (separate inventory) | Configure workloads inside VMs |

### Improvements Over the Article's Approach

- Use Ansible Vault or SSH keys instead of plaintext passwords in inventory
- Add `handlers` for network restart after config changes (the article applies config but doesn't mention restarting networking)
- Consider `check` mode (`--check --diff`) for dry-run validation before applying network changes
- Use host_vars for per-node IP assignments instead of a single defaults file
- Add a pre-flight validation role that checks Proxmox version compatibility

## References

- [JYSK Tech: Automate the Process of Proxmox Configuration](https://jysk.tech/automate-the-process-of-proxmox-configuration-27466f415240) (Daniel Hansen, May 2025)
- [Proxmox VE Network Configuration](https://pve.proxmox.com/wiki/Network_Configuration)
- [Ansible Galaxy - Role Init](https://docs.ansible.com/ansible/latest/galaxy/user_guide.html)
- [community.general.proxmox* modules](https://docs.ansible.com/ansible/latest/collections/community/general/)

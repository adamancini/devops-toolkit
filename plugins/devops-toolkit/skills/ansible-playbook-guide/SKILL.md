---
name: ansible-playbook-guide
description: Comprehensive Ansible automation reference covering playbook development, module usage, role structure, inventory management, variable precedence, Jinja2 templating, Vault secrets, and operational patterns. Use when writing, reviewing, or debugging Ansible playbooks, roles, and inventories.
---

# Ansible Playbook Guide

Provides structured reference knowledge for writing production-quality Ansible automation. This skill covers architecture, playbook structure, module categories, role conventions, variable management, templating, and operational patterns for databases, containers, and Kubernetes.

## Architecture Overview

Ansible uses a **push-based, agentless** architecture:

- **Control Node**: Runs Ansible commands and playbooks. Requires Python 3.8+.
- **Managed Nodes**: Target hosts accessed via SSH (Linux/macOS) or WinRM (Windows). Require Python 2.7+ or 3.5+.
- **Inventory**: Organized lists of managed nodes, grouped by function or environment.
- **Modules**: Reusable units of work (package installation, file management, service control).
- **Tasks**: Individual module invocations with parameters.
- **Plays**: Ordered groups of tasks targeting specific host groups.
- **Playbooks**: YAML files containing one or more plays.
- **Roles**: Reusable, self-contained automation units with standardized directory structure.

**Configuration precedence** (highest first):
1. `ANSIBLE_CONFIG` environment variable
2. `./ansible.cfg` (current directory)
3. `~/.ansible.cfg` (home directory)
4. `/etc/ansible/ansible.cfg`

## Playbook Structure

### Basic Play

```yaml
---
- name: Configure web servers
  hosts: webservers
  become: yes
  gather_facts: yes
  vars:
    http_port: 80

  pre_tasks:
    - name: Update apt cache
      ansible.builtin.apt:
        update_cache: yes
        cache_valid_time: 3600

  roles:
    - common
    - nginx

  tasks:
    - name: Deploy application config
      ansible.builtin.template:
        src: app.conf.j2
        dest: /etc/myapp/app.conf
      notify: restart myapp

  post_tasks:
    - name: Verify service health
      ansible.builtin.uri:
        url: "http://localhost:{{ http_port }}/health"
        status_code: 200

  handlers:
    - name: restart myapp
      ansible.builtin.service:
        name: myapp
        state: restarted
```

### Execution Order Within a Play

1. `pre_tasks` (and their handlers)
2. `roles`
3. `tasks` (and their handlers)
4. `post_tasks` (and their handlers)

### Blocks with Error Handling

```yaml
tasks:
  - name: Deploy with rollback
    block:
      - name: Deploy new version
        ansible.builtin.copy:
          src: app-v2.tar.gz
          dest: /opt/app/

      - name: Run migrations
        ansible.builtin.command:
          cmd: /opt/app/migrate.sh
        changed_when: "'applied' in migration_result.stdout"
        register: migration_result

    rescue:
      - name: Rollback deployment
        ansible.builtin.copy:
          src: app-v1.tar.gz
          dest: /opt/app/

      - name: Alert on failure
        ansible.builtin.debug:
          msg: "Deployment failed, rolled back to v1"

    always:
      - name: Clean temp files
        ansible.builtin.file:
          path: /tmp/deploy-staging
          state: absent
```

### Conditionals

```yaml
# OS-family conditional
- name: Install Apache (RedHat)
  ansible.builtin.dnf:
    name: httpd
    state: present
  when: ansible_os_family == "RedHat"

# Multiple conditions (AND)
- name: Shutdown old CentOS
  ansible.builtin.command: /sbin/shutdown -t now
  when:
    - ansible_facts['distribution'] == "CentOS"
    - ansible_facts['distribution_major_version'] == "6"

# Registered variable
- name: Check if config exists
  ansible.builtin.stat:
    path: /etc/myapp/config.yml
  register: config_file

- name: Generate default config
  ansible.builtin.template:
    src: config.yml.j2
    dest: /etc/myapp/config.yml
  when: not config_file.stat.exists
```

### Loops

```yaml
# Simple list
- name: Install packages
  ansible.builtin.apt:
    name: "{{ item }}"
    state: present
  loop:
    - nginx
    - redis-server
    - postgresql-client

# List of dicts
- name: Create users
  ansible.builtin.user:
    name: "{{ item.name }}"
    groups: "{{ item.groups }}"
    shell: /bin/bash
  loop:
    - { name: 'alice', groups: 'wheel' }
    - { name: 'bob', groups: 'docker' }

# Loop control for readability
- name: Process servers
  ansible.builtin.debug:
    msg: "Configuring {{ item.name }}"
  loop: "{{ server_list }}"
  loop_control:
    label: "{{ item.name }}"
```

### Error Handling

```yaml
# Custom failure condition
- name: Check application status
  ansible.builtin.shell: systemctl is-active myapp
  register: result
  failed_when: result.rc not in [0, 3]

# Custom changed condition
- name: Run database migration
  ansible.builtin.command: /opt/app/migrate.sh
  register: migration
  changed_when: "'migrations applied' in migration.stdout"

# Serial execution with failure threshold
- name: Rolling update
  hosts: webservers
  serial: 2
  max_fail_percentage: 25
  tasks:
    - name: Update application
      ansible.builtin.apt:
        name: myapp
        state: latest
```

## Best Practices

### Task Naming
- Every task MUST have a `name:` field
- Names should describe intent ("Ensure nginx is running") not mechanism ("Run systemctl start nginx")
- Use consistent verb style: "Install", "Configure", "Ensure", "Deploy", "Verify"

### Idempotency
- Prefer declarative modules over `command`/`shell`
- When `command`/`shell` is necessary, use `creates:`, `removes:`, or `changed_when:`
- Test by running playbooks twice; the second run should report zero changes

### Tags
- Use tags for selective execution: `--tags deploy`, `--skip-tags debug`
- Apply `tags: always` to tasks that must run regardless of tag filtering
- Tag inheritance works with `import_tasks` but not `include_tasks`

### Handlers
- Use handlers for service restarts triggered by config changes
- Handlers run once at end of play, regardless of how many tasks notify them
- Use `listen:` to group multiple handlers under a topic name
- Use `meta: flush_handlers` when you need handlers to run mid-play

## Role Conventions

Standard directory layout:
```
roles/<role_name>/
  tasks/main.yml        # Primary task list
  handlers/main.yml     # Handler definitions
  templates/            # Jinja2 templates (.j2)
  files/                # Static files for copy module
  vars/main.yml         # Internal role constants (high precedence)
  defaults/main.yml     # Default values for users to override (low precedence)
  meta/main.yml         # Role metadata and dependencies
```

See [examples/role-structure.md](examples/role-structure.md) for a complete working example.

## Security Patterns

### Ansible Vault
```bash
# Create encrypted file
ansible-vault create secrets.yml

# Encrypt existing file
ansible-vault encrypt vars/secrets.yml

# Encrypt single string for inline use
ansible-vault encrypt_string 'P@$$w0rd' --name 'db_password'

# Run playbook with vault
ansible-playbook site.yml --ask-vault-pass
ansible-playbook site.yml --vault-password-file=~/.vault_pass
```

### Vault Best Practices
- Use vault IDs for multi-environment separation: `--vault-id dev@prompt --vault-id prod@~/.vault_prod`
- Never commit vault password files to version control
- Apply `no_log: true` to tasks handling decrypted secrets
- Prefix vault variable names: `vault_db_password`, then reference as `db_password: "{{ vault_db_password }}"`

## Running Playbooks

| Option | Description |
|---|---|
| `--check` (`-C`) | Dry run, predict changes without applying |
| `--diff` (`-D`) | Show file differences |
| `--tags` / `--skip-tags` | Selective task execution |
| `--limit SUBSET` (`-l`) | Target specific hosts/groups |
| `--start-at-task "name"` | Resume from named task |
| `--step` | Interactive confirmation per task |
| `--forks N` (`-f`) | Parallel execution (default: 5) |
| `-e "var=value"` | Extra vars (highest precedence) |
| `-v` / `-vvv` / `-vvvv` | Verbosity levels |
| `--syntax-check` | Syntax validation only |
| `--list-tasks` | List tasks without executing |
| `--list-hosts` | List targeted hosts |

## Validation Workflow

```bash
# 1. YAML formatting
yamllint playbook.yml

# 2. Ansible linting
ansible-lint playbook.yml

# 3. Syntax check
ansible-playbook --syntax-check playbook.yml

# 4. Dry run with diff
ansible-playbook --check --diff playbook.yml

# 5. Role testing (CI/CD)
molecule test
```

## Reference Documentation

- [Module Categories](reference/module-categories.md) - 30+ module categories with usage patterns
- [Inventory Patterns](reference/inventory-patterns.md) - INI, YAML, and dynamic inventory formats
- [Variable Precedence](reference/variable-precedence.md) - Full precedence hierarchy and Jinja2 templating

## Examples

- [Role Structure](examples/role-structure.md) - Standard role layout with a working nginx example
- [Multi-Play Orchestration](examples/multi-play-orchestration.md) - Multi-play patterns, delegation, and serial execution

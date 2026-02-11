# Ansible Variable Precedence & Jinja2 Templating Reference

## Variable Precedence Hierarchy

Ansible resolves variables using a 22-level precedence hierarchy. Variables at higher levels override those at lower levels. Understanding this hierarchy is critical for debugging unexpected variable values.

### Full Precedence (Lowest to Highest)

| Level | Source | Scope |
|---|---|---|
| 1 | Command-line values (e.g., `-u my_user`) | Global |
| 2 | Role defaults (`roles/<role>/defaults/main.yml`) | Play |
| 3 | Inventory file or script group vars | Host |
| 4 | Inventory `group_vars/all` | Host |
| 5 | Playbook `group_vars/all` | Play |
| 6 | Inventory `group_vars/*` | Host |
| 7 | Playbook `group_vars/*` | Play |
| 8 | Inventory file or script host vars | Host |
| 9 | Inventory `host_vars/*` | Host |
| 10 | Playbook `host_vars/*` | Play |
| 11 | Host facts / cached `set_facts` | Host |
| 12 | Play `vars:` | Play |
| 13 | Play `vars_prompt:` | Play |
| 14 | Play `vars_files:` | Play |
| 15 | Role `vars/main.yml` | Play |
| 16 | Block `vars:` | Play |
| 17 | Task `vars:` | Play |
| 18 | `include_vars` | Play |
| 19 | `set_facts` / registered vars | Host |
| 20 | Role parameters (and `include_role` params) | Play |
| 21 | `include` parameters | Play |
| 22 | Extra vars (`-e "var=value"`) | Global |

### Key Takeaways

- **Extra vars always win** (`-e`). Use for emergency overrides, not routine configuration.
- **Role defaults are intentionally lowest** role-level precedence. Put values users should override here.
- **Role vars (`vars/main.yml`) are high precedence.** Put internal constants here that should not be casually overridden.
- **`set_fact` overrides most things** except extra vars and include/role parameters. Be cautious with it.
- **Inventory group/host vars** are below playbook group/host vars at equivalent specificity.

### Three Variable Scopes

| Scope | Set By | Examples |
|---|---|---|
| **Global** | Config, environment, CLI | `ansible.cfg`, `ANSIBLE_*` env vars, `-e` |
| **Play** | Play directives, roles, tasks | `vars:`, `vars_files:`, `include_vars`, role defaults/vars |
| **Host** | Inventory, facts, registered vars | `host_vars/`, `group_vars/`, `setup` facts, `set_fact` |

---

## Variable Usage Patterns

### Defining Variables

```yaml
# In a play
- hosts: webservers
  vars:
    http_port: 80
    app_name: myapp

  vars_files:
    - vars/common.yml
    - "vars/{{ ansible_os_family }}.yml"

  vars_prompt:
    - name: deploy_version
      prompt: "Which version to deploy?"
      private: no

# In a role defaults/main.yml (low precedence, user-overridable)
---
nginx_worker_processes: auto
nginx_worker_connections: 1024
nginx_keepalive_timeout: 65

# In a role vars/main.yml (high precedence, internal constants)
---
nginx_config_path: /etc/nginx
nginx_log_path: /var/log/nginx
```

### Registering Variables

```yaml
- name: Get service status
  ansible.builtin.command: systemctl is-active myapp
  register: service_status
  changed_when: false
  failed_when: false

- name: Restart if inactive
  ansible.builtin.service:
    name: myapp
    state: restarted
  when: service_status.rc != 0
```

Registered variable attributes: `.stdout`, `.stderr`, `.rc`, `.stdout_lines`, `.changed`, `.failed`, `.skipped`.

### set_fact

```yaml
- name: Calculate derived values
  ansible.builtin.set_fact:
    app_url: "https://{{ app_domain }}:{{ app_port }}"
    worker_count: "{{ ansible_processor_cores * 2 }}"
    cacheable: yes  # Persist across plays via fact cache
```

### include_vars

```yaml
- name: Load OS-specific variables
  ansible.builtin.include_vars:
    file: "{{ ansible_os_family }}.yml"

- name: Load all variable files from directory
  ansible.builtin.include_vars:
    dir: vars/
    extensions:
      - yml
      - yaml
```

---

## Jinja2 Templating

### Variable Substitution

```jinja2
{{ variable_name }}
{{ nested.dict.value }}
{{ list_var[0] }}
{{ dict_var['key-with-dashes'] }}
```

### Default Values

```jinja2
{# Simple default #}
{{ nginx_worker_processes | default('auto') }}

{# Default with boolean false distinction #}
{{ optional_flag | default(true) }}

{# Nested default (when parent may not exist) #}
{{ config.database.host | default('localhost') }}

{# Mandatory (fail if undefined) #}
{{ required_var | mandatory }}
```

### String Filters

```jinja2
{{ text | upper }}
{{ text | lower }}
{{ text | title }}
{{ text | capitalize }}
{{ text | trim }}
{{ text | replace('old', 'new') }}
{{ text | regex_replace('^prefix-', '') }}
{{ text | regex_search('pattern') }}
{{ items | join(', ') }}
{{ text | truncate(50) }}
{{ text | quote }}                    {# Shell-safe quoting #}
{{ text | urlencode }}
{{ text | b64encode }}
{{ text | b64decode }}
```

### Numeric Filters

```jinja2
{{ value | int }}
{{ value | float }}
{{ value | abs }}
{{ value | round(2) }}
{{ ansible_memtotal_mb * 0.7 | int }}
{{ 59 | random }}
{{ [3, 1, 4, 1, 5] | min }}
{{ [3, 1, 4, 1, 5] | max }}
{{ [3, 1, 4, 1, 5] | sum }}
```

### Type Casting and Testing

```jinja2
{{ value | int }}
{{ value | float }}
{{ value | bool }}
{{ value | string }}
{{ value | list }}

{# Type tests #}
{% if value is string %}
{% if value is number %}
{% if value is mapping %}    {# dict #}
{% if value is iterable %}
{% if value is defined %}
{% if value is undefined %}
```

### List Filters

```jinja2
{{ list | unique }}
{{ list | sort }}
{{ list | reverse }}
{{ list | shuffle }}
{{ list | flatten }}
{{ list | length }}
{{ list | first }}
{{ list | last }}

{# Set operations #}
{{ list1 | union(list2) }}
{{ list1 | intersect(list2) }}
{{ list1 | difference(list2) }}
{{ list1 | symmetric_difference(list2) }}

{# Transformation #}
{{ servers | map(attribute='name') | list }}
{{ ports | map('int') | list }}
{{ users | selectattr('active', 'equalto', true) | list }}
{{ items | rejectattr('disabled') | list }}
{{ users | map(attribute='name') | join(', ') }}
```

### Dictionary Filters

```jinja2
{# Merge dicts (right-side wins) #}
{{ defaults | combine(overrides) }}
{{ base | combine(overlay, recursive=True) }}

{# Convert between dict and list #}
{{ my_dict | dict2items }}
{# Result: [{"key": "k1", "value": "v1"}, ...] #}

{{ my_list | items2dict }}
{# Expects: [{"key": "k1", "value": "v1"}, ...] #}

{# Access dict keys safely #}
{{ my_dict | dict2items | selectattr('key', 'match', '^prefix_') | list }}
```

### Data Format Filters

```jinja2
{{ data | to_json }}
{{ data | to_nice_json(indent=2) }}
{{ data | to_yaml }}
{{ data | to_nice_yaml }}
{{ json_string | from_json }}
{{ yaml_string | from_yaml }}
```

### Password and Hash Filters

```jinja2
{{ 'mypassword' | password_hash('sha512') }}
{{ 'mypassword' | password_hash('sha512', 'salt_string') }}
{{ value | hash('sha256') }}
{{ value | hash('md5') }}
{{ value | checksum }}     {# SHA-1 #}
```

### Conditional Expression (Ternary)

```jinja2
{{ (env == 'production') | ternary('https', 'http') }}
{{ is_primary | ternary('master', 'replica') }}
```

### Path Filters

```jinja2
{{ path | basename }}          {# filename.ext #}
{{ path | dirname }}           {# /parent/dir #}
{{ path | expanduser }}        {# Expand ~ #}
{{ path | realpath }}          {# Resolve symlinks #}
{{ path | relpath('/base') }} {# Relative path #}
{{ 'file' | path_join('/etc', 'myapp') }}  {# /etc/myapp/file #}
```

### IP Address Filters

Requires `ansible.utils` collection.

```jinja2
{{ '192.0.2.1/24' | ansible.utils.ipaddr('address') }}
{{ '192.0.2.0/24' | ansible.utils.ipaddr('network') }}
{{ '192.0.2.0/24' | ansible.utils.ipaddr('netmask') }}
{{ address_list | ansible.utils.ipv4 }}
{{ address_list | ansible.utils.ipv6 }}
```

---

## Template Constructs

### Conditionals

```jinja2
{% if nginx_ssl_enabled | default(false) %}
    ssl_certificate {{ ssl_cert_path }};
    ssl_certificate_key {{ ssl_key_path }};
    ssl_protocols {{ nginx_ssl_protocols | default('TLSv1.2 TLSv1.3') }};
{% elif nginx_redirect_to_https | default(false) %}
    return 301 https://$host$request_uri;
{% else %}
    # HTTP only configuration
{% endif %}

{# Inline conditional #}
{{ 'enabled' if feature_flag else 'disabled' }}
```

### Loops

```jinja2
{% for vhost in virtual_hosts %}
server {
    listen {{ vhost.port | default(80) }};
    server_name {{ vhost.domain }};
    root {{ vhost.root | default('/var/www/html') }};
}
{% endfor %}

{# Loop with index and special variables #}
{% for server in upstream_servers %}
    server {{ server.host }}:{{ server.port }}{% if loop.first %} weight=5{% endif %};
{% endfor %}

{# Dictionary iteration #}
{% for key, value in config_map.items() %}
{{ key }} = {{ value }}
{% endfor %}

{# Filtered loop #}
{% for user in users if user.active %}
{{ user.name }}
{% endfor %}
```

Loop variables: `loop.index` (1-based), `loop.index0` (0-based), `loop.first`, `loop.last`, `loop.length`, `loop.revindex`, `loop.revindex0`.

### Comments

```jinja2
{# This is a Jinja2 comment - not rendered in output #}
```

### Whitespace Control

```jinja2
{# Strip whitespace with minus sign #}
{% for item in list -%}
    {{ item }}
{%- endfor %}

{# Or use trim_blocks and lstrip_blocks in template module #}
```

### Raw Blocks (Escape Jinja2)

```jinja2
{% raw %}
  This {{ will_not_be_processed }} by Jinja2
{% endraw %}
```

### Macros (Reusable Template Functions)

```jinja2
{% macro render_upstream(name, servers, port=8080) %}
upstream {{ name }} {
    {% for server in servers %}
    server {{ server }}:{{ port }};
    {% endfor %}
}
{% endmacro %}

{{ render_upstream('app', ['10.0.1.1', '10.0.1.2'], 3000) }}
{{ render_upstream('api', ['10.0.2.1', '10.0.2.2']) }}
```

---

## Lookups

Lookups access data from external sources on the **control node**.

```jinja2
{# File content #}
{{ lookup('file', '/etc/ssh/ssh_host_rsa_key.pub') }}

{# Environment variable #}
{{ lookup('env', 'HOME') }}

{# Template rendering #}
{{ lookup('template', 'myapp-config.j2') }}

{# Password generation #}
{{ lookup('password', '/tmp/passwordfile length=20 chars=ascii_letters,digits') }}

{# Pipe (command output) #}
{{ lookup('pipe', 'date +%Y%m%d') }}

{# URL content #}
{{ lookup('url', 'https://api.example.com/config') }}

{# INI file #}
{{ lookup('ini', 'key section=section file=config.ini') }}

{# CSV file #}
{{ lookup('csvfile', 'hostname file=servers.csv delimiter=, col=1') }}

{# First found file #}
{{ lookup('first_found', params) }}
```

### Lookup vs Query

```yaml
# lookup returns a string (comma-separated for lists)
result: "{{ lookup('file', 'file1.txt', 'file2.txt') }}"

# query returns a list (preferred for iteration)
result: "{{ query('file', 'file1.txt', 'file2.txt') }}"

# Equivalent to:
result: "{{ lookup('file', 'file1.txt', 'file2.txt', wantlist=True) }}"
```

---

## Debugging Variable Resolution

```bash
# Show all variables for a host
ansible -m debug -a "var=hostvars[inventory_hostname]" hostname

# Show specific variable
ansible -m debug -a "var=http_port" -i inventory/production webservers

# Show inventory structure
ansible-inventory --list -i inventory/production
ansible-inventory --graph -i inventory/production

# Show variable origin
ansible-inventory --host web1.example.com -i inventory/production
```

### In Playbooks

```yaml
- name: Debug variable resolution
  ansible.builtin.debug:
    var: http_port

- name: Show all variables for this host
  ansible.builtin.debug:
    var: hostvars[inventory_hostname]

- name: Show group membership
  ansible.builtin.debug:
    var: group_names

- name: Show all groups
  ansible.builtin.debug:
    var: groups
```

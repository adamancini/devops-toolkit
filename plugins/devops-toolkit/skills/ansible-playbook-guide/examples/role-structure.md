# Example: Standard Role Structure

A complete working example of an Ansible role following the standard directory layout and Galaxy conventions.

## Standard Directory Layout

```
roles/nginx/
├── defaults/
│   └── main.yml          # Low-precedence defaults (user-overridable)
├── vars/
│   └── main.yml          # High-precedence internal constants
├── tasks/
│   └── main.yml          # Primary task list
├── handlers/
│   └── main.yml          # Handler definitions
├── templates/
│   └── nginx.conf.j2     # Jinja2 templates
├── files/
│   └── default-index.html  # Static files for copy module
├── meta/
│   └── main.yml          # Role metadata and dependencies
└── README.md             # Role documentation
```

### What Goes Where

| Directory | Purpose | Precedence |
|---|---|---|
| `defaults/` | Values users should override (ports, domains, feature flags) | Low (level 2) |
| `vars/` | Internal constants that should not change (paths, package names) | High (level 15) |
| `tasks/` | Task definitions, including imported sub-task files | N/A |
| `handlers/` | Service restart/reload handlers triggered by `notify:` | N/A |
| `templates/` | Jinja2 templates rendered by `template:` module | N/A |
| `files/` | Static files deployed by `copy:` module | N/A |
| `meta/` | Role dependencies, supported platforms, Galaxy metadata | N/A |

---

## Complete nginx Role Example

### defaults/main.yml

```yaml
---
# User-overridable configuration
nginx_worker_processes: auto
nginx_worker_connections: 1024
nginx_keepalive_timeout: 65
nginx_client_max_body_size: 64m

nginx_http_port: 80
nginx_https_port: 443

nginx_ssl_enabled: false
nginx_ssl_certificate: ""
nginx_ssl_certificate_key: ""
nginx_ssl_protocols: "TLSv1.2 TLSv1.3"

nginx_server_names: []

nginx_proxy_enabled: false
nginx_proxy_upstream_host: "127.0.0.1"
nginx_proxy_upstream_port: 8080

nginx_gzip_enabled: true
nginx_gzip_types:
  - text/plain
  - text/css
  - application/json
  - application/javascript
  - text/xml
  - application/xml
```

### vars/main.yml

```yaml
---
# Internal constants - do not override
nginx_config_path: /etc/nginx
nginx_config_file: "{{ nginx_config_path }}/nginx.conf"
nginx_sites_available: "{{ nginx_config_path }}/sites-available"
nginx_sites_enabled: "{{ nginx_config_path }}/sites-enabled"
nginx_log_path: /var/log/nginx
nginx_pid_file: /run/nginx.pid

# OS-specific package names (can be split into vars/Debian.yml, vars/RedHat.yml)
nginx_packages:
  Debian:
    - nginx
    - nginx-extras
  RedHat:
    - nginx
```

### tasks/main.yml

```yaml
---
- name: Install nginx packages
  ansible.builtin.package:
    name: "{{ nginx_packages[ansible_os_family] }}"
    state: present

- name: Create nginx directories
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: root
    group: root
    mode: '0755'
  loop:
    - "{{ nginx_sites_available }}"
    - "{{ nginx_sites_enabled }}"

- name: Deploy nginx configuration
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: "{{ nginx_config_file }}"
    owner: root
    group: root
    mode: '0644'
    validate: 'nginx -t -c %s'
    backup: yes
  notify: reload nginx

- name: Remove default site
  ansible.builtin.file:
    path: "{{ nginx_sites_enabled }}/default"
    state: absent
  notify: reload nginx

- name: Ensure nginx is started and enabled
  ansible.builtin.service:
    name: nginx
    state: started
    enabled: yes
```

### handlers/main.yml

```yaml
---
- name: restart nginx
  ansible.builtin.service:
    name: nginx
    state: restarted

- name: reload nginx
  ansible.builtin.service:
    name: nginx
    state: reloaded

# Grouped handler example: notify "restart web services" to trigger both
- name: restart nginx via topic
  listen: "restart web services"
  ansible.builtin.service:
    name: nginx
    state: restarted
```

### templates/nginx.conf.j2

```jinja2
# Managed by Ansible - DO NOT EDIT
user www-data;
worker_processes {{ nginx_worker_processes }};
pid {{ nginx_pid_file }};

events {
    worker_connections {{ nginx_worker_connections }};
}

http {
    include {{ nginx_config_path }}/mime.types;
    default_type application/octet-stream;

    sendfile on;
    tcp_nopush on;
    keepalive_timeout {{ nginx_keepalive_timeout }};
    client_max_body_size {{ nginx_client_max_body_size }};

    # Logging
    access_log {{ nginx_log_path }}/access.log;
    error_log {{ nginx_log_path }}/error.log;

{% if nginx_gzip_enabled | default(true) %}
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types {{ nginx_gzip_types | join(' ') }};
{% endif %}

{% if nginx_ssl_enabled %}
    # SSL settings
    ssl_protocols {{ nginx_ssl_protocols }};
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
{% endif %}

    # Virtual hosts
    include {{ nginx_sites_enabled }}/*;

{% if nginx_proxy_enabled %}
    # Upstream for proxy
    upstream app_backend {
        server {{ nginx_proxy_upstream_host }}:{{ nginx_proxy_upstream_port }};
    }
{% endif %}

{% for server_name in nginx_server_names | default([]) %}
    server {
        listen {{ nginx_http_port }};
        server_name {{ server_name }};

{% if nginx_ssl_enabled %}
        listen {{ nginx_https_port }} ssl;
        ssl_certificate {{ nginx_ssl_certificate }};
        ssl_certificate_key {{ nginx_ssl_certificate_key }};
{% endif %}

{% if nginx_proxy_enabled %}
        location / {
            proxy_pass http://app_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
{% else %}
        root /var/www/html;
        index index.html;
{% endif %}
    }
{% endfor %}
}
```

### meta/main.yml

```yaml
---
galaxy_info:
  author: Your Name
  description: Install and configure nginx web server
  license: MIT
  min_ansible_version: "2.14"
  platforms:
    - name: Ubuntu
      versions:
        - jammy
        - noble
    - name: Debian
      versions:
        - bookworm
    - name: EL
      versions:
        - "8"
        - "9"
  galaxy_tags:
    - nginx
    - web
    - proxy
    - ssl

dependencies: []
# Example with dependencies:
# dependencies:
#   - role: common
#   - role: ssl-certs
#     when: nginx_ssl_enabled
```

---

## Using the Role

### In a Playbook

```yaml
---
- name: Configure web servers
  hosts: webservers
  become: yes

  roles:
    - role: nginx
      vars:
        nginx_server_names:
          - app.example.com
        nginx_ssl_enabled: true
        nginx_ssl_certificate: /etc/ssl/certs/app.crt
        nginx_ssl_certificate_key: /etc/ssl/private/app.key
        nginx_proxy_enabled: true
        nginx_proxy_upstream_port: 3000
```

### With group_vars

**`group_vars/webservers/nginx.yml`**:
```yaml
---
nginx_worker_processes: 4
nginx_worker_connections: 2048
nginx_server_names:
  - app.example.com
  - www.example.com
nginx_ssl_enabled: true
nginx_ssl_certificate: /etc/ssl/certs/app.crt
nginx_ssl_certificate_key: /etc/ssl/private/app.key
nginx_proxy_enabled: true
nginx_proxy_upstream_port: 3000
```

---

## Scaffolding a New Role

```bash
# Create role skeleton with ansible-galaxy
ansible-galaxy role init my_new_role

# Install roles from requirements
ansible-galaxy role install -r requirements.yml

# requirements.yml
---
roles:
  - name: geerlingguy.nginx
    version: "3.2.0"
  - name: geerlingguy.certbot
```

### Galaxy-Compatible Conventions

- Include a `README.md` with description, requirements, role variables, dependencies, and example playbook
- Use `meta/main.yml` for platform support and Galaxy metadata
- Prefix all variables with the role name (e.g., `nginx_*`)
- Keep `defaults/main.yml` well-commented as the primary user interface
- Support `--check` mode for all tasks where possible

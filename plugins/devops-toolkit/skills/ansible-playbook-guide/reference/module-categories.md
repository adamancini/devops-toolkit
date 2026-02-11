# Ansible Module Categories Reference

Comprehensive reference for commonly used Ansible modules organized by category. Each entry includes the module name, key parameters, and a concise usage example.

## Package Management

### apt (Debian/Ubuntu)

```yaml
- name: Install nginx
  ansible.builtin.apt:
    name: nginx
    state: present
    update_cache: yes
    cache_valid_time: 3600
```

Key parameters: `name`, `state` (present/absent/latest), `update_cache`, `cache_valid_time`, `upgrade` (dist/yes/no), `purge`, `deb` (local .deb path).

### yum (RHEL/CentOS 7)

```yaml
- name: Install httpd
  ansible.builtin.yum:
    name: httpd
    state: present
    enablerepo: epel
```

Key parameters: `name`, `state`, `enablerepo`, `disablerepo`, `exclude`, `installroot`.

### dnf (Fedora/RHEL 8+)

```yaml
- name: Install packages
  ansible.builtin.dnf:
    name:
      - httpd
      - mod_ssl
    state: present
```

Key parameters: `name` (string or list), `state`, `enablerepo`, `disablerepo`, `allowerasing`.

### package (Cross-Platform)

```yaml
- name: Install git
  ansible.builtin.package:
    name: git
    state: present
```

Automatically selects the appropriate package manager for the target OS. Use when writing platform-agnostic roles.

### pip

```yaml
- name: Install Python packages
  ansible.builtin.pip:
    name:
      - flask
      - gunicorn>=20.0
    virtualenv: /opt/myapp/venv
    virtualenv_python: python3
```

Key parameters: `name`, `requirements`, `virtualenv`, `virtualenv_python`, `state`, `extra_args`.

---

## File Management

### file

```yaml
- name: Create application directory
  ansible.builtin.file:
    path: /opt/myapp
    state: directory
    owner: appuser
    group: appgroup
    mode: '0755'
```

States: `directory`, `file`, `link`, `hard`, `absent`, `touch`.

Key parameters: `path`, `state`, `owner`, `group`, `mode`, `recurse`, `src` (for links), `force`.

### copy

```yaml
- name: Copy configuration file
  ansible.builtin.copy:
    src: files/nginx.conf
    dest: /etc/nginx/nginx.conf
    owner: root
    group: root
    mode: '0644'
    backup: yes
```

Key parameters: `src`, `dest`, `content` (inline string), `owner`, `group`, `mode`, `backup`, `remote_src`, `validate`.

### template

```yaml
- name: Generate nginx config from template
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
    owner: root
    group: root
    mode: '0644'
    backup: yes
    validate: 'nginx -t -c %s'
  notify: restart nginx
```

Key parameters: `src`, `dest`, `owner`, `group`, `mode`, `backup`, `validate`, `newline_sequence`, `trim_blocks`, `lstrip_blocks`.

### fetch

```yaml
- name: Retrieve remote logs
  ansible.builtin.fetch:
    src: /var/log/myapp/app.log
    dest: ./collected-logs/{{ inventory_hostname }}/
    flat: no
```

Copies files **from** managed nodes to the control node. Key parameters: `src`, `dest`, `flat`, `validate_checksum`.

### lineinfile

```yaml
- name: Set SSH port
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^#?Port '
    line: 'Port 2222'
    backup: yes
    validate: 'sshd -t -f %s'
  notify: restart sshd
```

Key parameters: `path`, `line`, `regexp`, `state` (present/absent), `insertbefore`, `insertafter`, `backrefs`, `backup`, `validate`.

### blockinfile

```yaml
- name: Add custom nginx settings
  ansible.builtin.blockinfile:
    path: /etc/nginx/nginx.conf
    block: |
      client_max_body_size 64m;
      client_body_timeout 120s;
    marker: "# {mark} ANSIBLE MANAGED BLOCK - Custom settings"
    insertafter: "http {"
    backup: yes
```

Key parameters: `path`, `block`, `marker`, `insertbefore`, `insertafter`, `state`, `backup`.

### replace

```yaml
- name: Update database connection string
  ansible.builtin.replace:
    path: /opt/myapp/config.py
    regexp: 'DATABASE_URL = ".*"'
    replace: 'DATABASE_URL = "{{ database_url }}"'
    backup: yes
```

Key parameters: `path`, `regexp`, `replace`, `backup`, `before`, `after`.

### stat

```yaml
- name: Check if config exists
  ansible.builtin.stat:
    path: /etc/myapp/config.yml
  register: config_stat

- name: Generate config if missing
  ansible.builtin.template:
    src: config.yml.j2
    dest: /etc/myapp/config.yml
  when: not config_stat.stat.exists
```

Returns file metadata: `exists`, `isdir`, `isreg`, `islnk`, `size`, `uid`, `gid`, `mode`, `checksum`.

### unarchive

```yaml
- name: Extract application archive
  ansible.builtin.unarchive:
    src: app-v2.tar.gz
    dest: /opt/myapp/
    remote_src: no
    owner: appuser
    creates: /opt/myapp/v2
```

Key parameters: `src`, `dest`, `remote_src`, `creates`, `owner`, `group`, `mode`, `exclude`.

---

## User and Access Management

### user

```yaml
- name: Create application user
  ansible.builtin.user:
    name: appuser
    comment: "Application Service Account"
    shell: /bin/bash
    create_home: yes
    uid: 1500
    group: appgroup
    groups: docker,wheel
    append: yes
    password: "{{ user_password | password_hash('sha512') }}"
    state: present
```

Key parameters: `name`, `uid`, `group`, `groups`, `append`, `home`, `shell`, `password`, `password_lock`, `generate_ssh_key`, `ssh_key_bits`, `system`, `state`, `remove`.

### group

```yaml
- name: Create application group
  ansible.builtin.group:
    name: appgroup
    gid: 1500
    state: present
    system: no
```

Key parameters: `name`, `gid`, `state`, `system`.

### authorized_key

```yaml
- name: Add SSH authorized key
  ansible.posix.authorized_key:
    user: "{{ ansible_user }}"
    state: present
    key: "{{ lookup('file', '~/.ssh/id_ed25519.pub') }}"
    exclusive: no
    comment: "Deployed by Ansible"
```

Key parameters: `user`, `key`, `state`, `exclusive`, `key_options`, `comment`, `path`.

---

## Service Management

### service

```yaml
- name: Ensure nginx is running and enabled
  ansible.builtin.service:
    name: nginx
    state: started
    enabled: yes
```

States: `started`, `stopped`, `restarted`, `reloaded`.

### systemd

```yaml
- name: Manage application service
  ansible.builtin.systemd:
    name: myapp
    state: started
    enabled: yes
    daemon_reload: yes
    masked: no
```

Key parameters: `name`, `state`, `enabled`, `daemon_reload`, `daemon_reexec`, `masked`, `scope` (system/user/global).

Use `daemon_reload: yes` after deploying new unit files.

---

## Command Execution

### command

```yaml
- name: Run database migration
  ansible.builtin.command:
    cmd: /opt/myapp/bin/migrate
    chdir: /opt/myapp
    creates: /opt/myapp/.migrated
  register: migration_result
  changed_when: "'applied' in migration_result.stdout"
```

Does **not** use shell processing (no pipes, redirects, environment variables). Key parameters: `cmd`, `chdir`, `creates`, `removes`, `stdin`.

### shell

```yaml
- name: Check service memory usage
  ansible.builtin.shell: |
    ps aux | grep myapp | grep -v grep | awk '{print $6}'
  register: memory_usage
  changed_when: false
```

Uses `/bin/sh` shell processing. Only use when pipes, redirects, or shell features are needed. Always consider whether a declarative module exists instead.

### raw

```yaml
- name: Bootstrap Python on managed node
  ansible.builtin.raw: apt-get install -y python3
  become: yes
```

Executes a command without requiring Python on the managed node. Use for bootstrapping Python or on network devices.

### script

```yaml
- name: Run local script on remote host
  ansible.builtin.script:
    cmd: scripts/setup.sh arg1 arg2
    creates: /opt/app/.setup-complete
```

Transfers and executes a script from the control node on managed nodes.

---

## Scheduling

### cron

```yaml
- name: Schedule nightly backup
  ansible.builtin.cron:
    name: "Database backup"
    minute: "0"
    hour: "2"
    job: "/opt/scripts/backup.sh >> /var/log/backup.log 2>&1"
    user: backupuser
    state: present
```

Key parameters: `name` (required, used as identifier), `minute`, `hour`, `day`, `month`, `weekday`, `job`, `user`, `state`, `special_time` (reboot/yearly/monthly/weekly/daily/hourly), `cron_file`.

---

## Networking

### ufw

```yaml
- name: Allow SSH access
  community.general.ufw:
    rule: allow
    port: '22'
    proto: tcp
    comment: 'Allow SSH'

- name: Enable firewall with default deny
  community.general.ufw:
    state: enabled
    policy: deny
    direction: incoming
```

Key parameters: `rule` (allow/deny/reject/limit), `port`, `proto`, `src`, `dest`, `direction`, `comment`, `state`, `policy`.

### iptables

```yaml
- name: Allow established connections
  ansible.builtin.iptables:
    chain: INPUT
    ctstate: ESTABLISHED,RELATED
    jump: ACCEPT
    comment: "Allow established connections"

- name: Allow SSH
  ansible.builtin.iptables:
    chain: INPUT
    protocol: tcp
    destination_port: 22
    ctstate: NEW
    jump: ACCEPT
    comment: "Allow SSH"
```

Key parameters: `chain`, `protocol`, `source`, `destination`, `destination_port`, `ctstate`, `jump`, `comment`, `table`, `action` (insert/append).

---

## Database Modules

### mysql_db / mysql_user

```yaml
- name: Create MySQL database
  community.mysql.mysql_db:
    name: webapp
    encoding: utf8mb4
    collation: utf8mb4_unicode_ci
    state: present
    login_user: root
    login_password: "{{ vault_mysql_root_password }}"

- name: Create MySQL user with privileges
  community.mysql.mysql_user:
    name: webapp_user
    password: "{{ vault_webapp_db_password }}"
    priv: "webapp.*:ALL"
    host: "192.168.1.%"
    state: present
    login_user: root
    login_password: "{{ vault_mysql_root_password }}"
```

Requires `community.mysql` collection and `PyMySQL` or `mysqlclient` Python library on the target.

### postgresql_db / postgresql_user / postgresql_privs

```yaml
- name: Create PostgreSQL database
  community.postgresql.postgresql_db:
    name: webapp
    owner: webapp_user
    encoding: UTF8
    lc_collate: en_US.UTF-8
    lc_ctype: en_US.UTF-8
    state: present

- name: Create PostgreSQL user
  community.postgresql.postgresql_user:
    name: webapp_user
    password: "{{ vault_webapp_pg_password }}"
    role_attr_flags: CREATEDB,NOSUPERUSER
    state: present

- name: Grant schema privileges
  community.postgresql.postgresql_privs:
    database: webapp
    roles: webapp_user
    privs: ALL
    type: schema
    objs: public
    state: present
```

Requires `community.postgresql` collection and `psycopg2` Python library on the target.

---

## Container Modules

### docker_image

```yaml
- name: Pull application images
  community.docker.docker_image:
    name: "{{ item }}"
    source: pull
    state: present
  loop:
    - nginx:1.25-alpine
    - redis:7-alpine
    - postgres:16-alpine
```

Key parameters: `name`, `tag`, `source` (pull/build/load), `state`, `build` (path, dockerfile, args), `force_source`.

### docker_container

```yaml
- name: Run Redis container
  community.docker.docker_container:
    name: redis
    image: redis:7-alpine
    state: started
    restart_policy: unless-stopped
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    env:
      REDIS_ARGS: "--maxmemory 512mb"
    networks:
      - name: app-network
    memory: 1g
    cpus: 1.0
```

Key parameters: `name`, `image`, `state` (started/stopped/absent/present), `ports`, `volumes`, `env`, `restart_policy`, `networks`, `command`, `entrypoint`, `memory`, `cpus`, `labels`.

### docker_network

```yaml
- name: Create application network
  community.docker.docker_network:
    name: app-network
    driver: bridge
    state: present
    ipam_config:
      - subnet: 172.20.0.0/16
```

### docker_compose_v2

```yaml
- name: Deploy application stack
  community.docker.docker_compose_v2:
    project_src: /opt/myapp
    state: present
    pull: always
```

Requires `community.docker` collection and Docker SDK for Python.

---

## Kubernetes Modules

Requires `kubernetes.core` collection: `ansible-galaxy collection install kubernetes.core`

### k8s (Create/Manage Resources)

```yaml
- name: Create namespace
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: v1
      kind: Namespace
      metadata:
        name: myapp

- name: Apply manifest from file
  kubernetes.core.k8s:
    state: present
    src: /path/to/deployment.yml

- name: Create deployment inline
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: myapp
        namespace: myapp
      spec:
        replicas: 3
        selector:
          matchLabels:
            app: myapp
        template:
          metadata:
            labels:
              app: myapp
          spec:
            containers:
              - name: myapp
                image: myapp:latest
                ports:
                  - containerPort: 8080
```

Key parameters: `state` (present/absent/patched), `definition`, `src`, `namespace`, `name`, `kind`, `api_version`, `wait`, `wait_timeout`.

### k8s_info (Query Resources)

```yaml
- name: Get running pods
  kubernetes.core.k8s_info:
    kind: Pod
    namespace: myapp
    label_selectors:
      - app=myapp
    field_selectors:
      - status.phase=Running
  register: pod_list

- name: Wait for deployment readiness
  kubernetes.core.k8s_info:
    kind: Deployment
    namespace: myapp
    name: myapp
  register: deployment
  until: deployment.resources[0].status.readyReplicas | default(0) >= 3
  retries: 10
  delay: 15
```

### helm (Deploy Charts)

```yaml
- name: Deploy ingress controller
  kubernetes.core.helm:
    name: ingress-nginx
    chart_ref: ingress-nginx/ingress-nginx
    release_namespace: ingress-nginx
    create_namespace: true
    values:
      controller:
        replicaCount: 2
    wait: true
    wait_timeout: 300s

- name: Remove release
  kubernetes.core.helm:
    name: ingress-nginx
    release_namespace: ingress-nginx
    state: absent
```

Key parameters: `name`, `chart_ref`, `release_namespace`, `create_namespace`, `values`, `values_files`, `state`, `wait`, `wait_timeout`, `atomic`, `force`.

---

## Cloud Modules

### amazon.aws.ec2_instance

```yaml
- name: Launch EC2 instance
  amazon.aws.ec2_instance:
    name: web-server
    instance_type: t3.medium
    image_id: ami-0abcdef1234567890
    key_name: mykey
    vpc_subnet_id: subnet-12345
    security_groups:
      - web-sg
    tags:
      Environment: production
    state: running
```

### amazon.aws.s3_bucket

```yaml
- name: Create S3 bucket
  amazon.aws.s3_bucket:
    name: my-app-assets
    state: present
    versioning: yes
    encryption: AES256
    tags:
      Project: myapp
```

### google.cloud.gcp_compute_instance

```yaml
- name: Create GCE instance
  google.cloud.gcp_compute_instance:
    name: web-server
    machine_type: n1-standard-2
    zone: us-central1-a
    disks:
      - auto_delete: true
        boot: true
        initialize_params:
          source_image: projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts
    network_interfaces:
      - network:
          selfLink: global/networks/default
    state: present
```

---

## System Information

### setup (Fact Gathering)

```yaml
- name: Gather only network facts
  ansible.builtin.setup:
    gather_subset:
      - network

- name: Display OS information
  ansible.builtin.debug:
    msg: "{{ ansible_distribution }} {{ ansible_distribution_version }} ({{ ansible_os_family }})"
```

Common facts: `ansible_hostname`, `ansible_fqdn`, `ansible_os_family`, `ansible_distribution`, `ansible_distribution_major_version`, `ansible_default_ipv4.address`, `ansible_processor_cores`, `ansible_memtotal_mb`.

### debug

```yaml
- name: Print variable value
  ansible.builtin.debug:
    var: my_variable

- name: Print formatted message
  ansible.builtin.debug:
    msg: "Server {{ inventory_hostname }} has {{ ansible_processor_cores }} cores"
```

### assert

```yaml
- name: Validate required variables
  ansible.builtin.assert:
    that:
      - app_domain is defined
      - app_domain | length > 0
      - http_port | int > 0
    fail_msg: "Required variables are missing or invalid"
    success_msg: "All required variables are set"
```

---

## HTTP / API

### uri

```yaml
- name: Call REST API
  ansible.builtin.uri:
    url: "https://api.example.com/v1/deploy"
    method: POST
    headers:
      Authorization: "Bearer {{ api_token }}"
      Content-Type: application/json
    body_format: json
    body:
      version: "{{ app_version }}"
    status_code: [200, 201]
    return_content: yes
  register: api_response
```

Key parameters: `url`, `method`, `headers`, `body`, `body_format`, `status_code`, `return_content`, `validate_certs`, `timeout`.

### get_url

```yaml
- name: Download application binary
  ansible.builtin.get_url:
    url: "https://releases.example.com/myapp-{{ version }}.tar.gz"
    dest: /tmp/myapp.tar.gz
    checksum: "sha256:{{ expected_checksum }}"
    mode: '0644'
```

Key parameters: `url`, `dest`, `checksum`, `mode`, `owner`, `group`, `force`, `timeout`, `headers`.

---

## Wait and Synchronization

### wait_for

```yaml
- name: Wait for port to be available
  ansible.builtin.wait_for:
    port: 8080
    host: "{{ inventory_hostname }}"
    delay: 5
    timeout: 300

- name: Wait for file to appear
  ansible.builtin.wait_for:
    path: /var/run/myapp.pid
    state: present
    timeout: 60
```

Key parameters: `port`, `host`, `path`, `state` (present/absent/started/stopped/drained), `delay`, `timeout`, `search_regex`.

### wait_for_connection

```yaml
- name: Wait for host to come back after reboot
  ansible.builtin.wait_for_connection:
    delay: 30
    timeout: 300
```

### pause

```yaml
- name: Wait before continuing
  ansible.builtin.pause:
    seconds: 30
    prompt: "Press Enter to continue deployment"
```

---

## Async Tasks

```yaml
- name: Start long-running backup
  ansible.builtin.command: /opt/scripts/full-backup.sh
  async: 3600
  poll: 0
  register: backup_job

- name: Continue with other tasks
  ansible.builtin.debug:
    msg: "Backup running in background"

- name: Check backup completion
  ansible.builtin.async_status:
    jid: "{{ backup_job.ansible_job_id }}"
  register: backup_result
  until: backup_result.finished
  retries: 60
  delay: 60
```

`async:` sets max runtime in seconds. `poll: 0` means fire-and-forget; check later with `async_status`.

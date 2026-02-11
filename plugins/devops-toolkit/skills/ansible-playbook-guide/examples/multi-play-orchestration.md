# Example: Multi-Play Orchestration Patterns

Patterns for coordinating complex deployments across multiple host groups using multi-play playbooks, delegation, serial execution, and error handling.

## Multi-Play Playbook

A playbook containing multiple plays, each targeting different host groups with different tasks.

```yaml
---
# Play 1: Prepare all servers
- name: Common baseline configuration
  hosts: all
  become: yes
  roles:
    - common
    - security-baseline

# Play 2: Configure databases first
- name: Configure database servers
  hosts: databases
  become: yes
  roles:
    - postgresql
  tasks:
    - name: Verify database is accepting connections
      community.postgresql.postgresql_ping:
      register: db_status

    - name: Fail if database is not ready
      ansible.builtin.assert:
        that: db_status.is_available
        fail_msg: "Database is not accepting connections"

# Play 3: Deploy application after database is ready
- name: Deploy application servers
  hosts: webservers
  become: yes
  serial: 2
  roles:
    - myapp
  tasks:
    - name: Verify application health
      ansible.builtin.uri:
        url: "http://localhost:{{ app_port }}/health"
        status_code: 200
      retries: 5
      delay: 10

# Play 4: Configure load balancer last
- name: Update load balancer configuration
  hosts: loadbalancers
  become: yes
  roles:
    - haproxy
```

### Execution Order

Plays execute **sequentially** top to bottom. Within each play, tasks execute on all targeted hosts before moving to the next task (linear strategy by default).

---

## Serial Execution (Rolling Updates)

Control how many hosts are updated at a time to maintain service availability.

### Fixed Batch Size

```yaml
- name: Rolling update - 2 hosts at a time
  hosts: webservers
  become: yes
  serial: 2
  tasks:
    - name: Update application
      ansible.builtin.apt:
        name: myapp
        state: latest
      notify: restart myapp

  handlers:
    - name: restart myapp
      ansible.builtin.service:
        name: myapp
        state: restarted
```

### Percentage-Based Batches

```yaml
- name: Update 25% of hosts at a time
  hosts: webservers
  serial: "25%"
  tasks:
    - name: Update application
      ansible.builtin.apt:
        name: myapp
        state: latest
```

### Graduated Batches (Canary Pattern)

```yaml
- name: Canary deployment
  hosts: webservers
  serial:
    - 1          # First: test on 1 host
    - 5          # Then: expand to 5
    - "25%"      # Then: 25% of remaining
  max_fail_percentage: 10
  tasks:
    - name: Deploy new version
      ansible.builtin.copy:
        src: myapp-v2.tar.gz
        dest: /opt/myapp/

    - name: Restart application
      ansible.builtin.service:
        name: myapp
        state: restarted

    - name: Wait for health check
      ansible.builtin.uri:
        url: "http://localhost:{{ app_port }}/health"
        status_code: 200
      retries: 10
      delay: 5
```

### Failure Threshold

```yaml
- name: Rolling update with failure tolerance
  hosts: webservers
  serial: 5
  max_fail_percentage: 20   # Stop if >20% of batch fails
  # OR
  # any_errors_fatal: true  # Stop immediately on any failure
  tasks:
    - name: Update and restart
      ansible.builtin.apt:
        name: myapp
        state: latest
```

---

## Delegation

Run a task on a different host than the one being iterated over.

### delegate_to

```yaml
- name: Rolling update with load balancer coordination
  hosts: webservers
  serial: 1
  become: yes
  tasks:
    - name: Remove from load balancer
      ansible.builtin.uri:
        url: "http://{{ lb_host }}/api/pools/web/members/{{ inventory_hostname }}"
        method: DELETE
        headers:
          Authorization: "Bearer {{ lb_api_token }}"
      delegate_to: localhost

    - name: Update application
      ansible.builtin.apt:
        name: myapp
        state: latest
      notify: restart myapp

    - name: Wait for application to start
      ansible.builtin.wait_for:
        port: "{{ app_port }}"
        delay: 5
        timeout: 60

    - name: Add back to load balancer
      ansible.builtin.uri:
        url: "http://{{ lb_host }}/api/pools/web/members"
        method: POST
        body_format: json
        body:
          hostname: "{{ inventory_hostname }}"
          port: "{{ app_port }}"
        headers:
          Authorization: "Bearer {{ lb_api_token }}"
      delegate_to: localhost

  handlers:
    - name: restart myapp
      ansible.builtin.service:
        name: myapp
        state: restarted
```

### run_once

Execute a task only once across all hosts in the play, regardless of how many hosts match.

```yaml
- name: Database migration (run once)
  hosts: webservers
  tasks:
    - name: Run database migrations
      ansible.builtin.command:
        cmd: /opt/myapp/bin/migrate
      delegate_to: "{{ groups['databases'][0] }}"
      run_once: true
      register: migration_result
      changed_when: "'applied' in migration_result.stdout"

    - name: Generate deployment ID
      ansible.builtin.command: uuidgen
      delegate_to: localhost
      run_once: true
      register: deploy_id

    - name: Deploy with shared ID
      ansible.builtin.template:
        src: version.txt.j2
        dest: /opt/myapp/version.txt
      vars:
        deployment_id: "{{ deploy_id.stdout }}"
```

### delegate_facts

When gathering facts from a delegated host, store them on that host instead of the current host.

```yaml
- name: Gather facts from database host
  ansible.builtin.setup:
  delegate_to: "{{ db_host }}"
  delegate_facts: true
```

---

## Block Error Handling

### Deploy with Rollback

```yaml
- name: Application deployment with rollback
  hosts: webservers
  become: yes
  serial: 2
  vars:
    app_path: /opt/myapp
    backup_path: /opt/myapp-backup

  tasks:
    - name: Deploy new version
      block:
        - name: Backup current version
          ansible.builtin.copy:
            src: "{{ app_path }}/"
            dest: "{{ backup_path }}/"
            remote_src: yes

        - name: Deploy new artifacts
          ansible.builtin.unarchive:
            src: "myapp-{{ deploy_version }}.tar.gz"
            dest: "{{ app_path }}/"

        - name: Run database migrations
          ansible.builtin.command:
            cmd: "{{ app_path }}/bin/migrate"
          run_once: true
          delegate_to: "{{ groups['databases'][0] }}"
          changed_when: "'applied' in migrate_result.stdout"
          register: migrate_result

        - name: Restart application
          ansible.builtin.service:
            name: myapp
            state: restarted

        - name: Verify health check
          ansible.builtin.uri:
            url: "http://localhost:{{ app_port }}/health"
            status_code: 200
          retries: 10
          delay: 5
          register: health

      rescue:
        - name: Restore from backup
          ansible.builtin.copy:
            src: "{{ backup_path }}/"
            dest: "{{ app_path }}/"
            remote_src: yes

        - name: Restart with previous version
          ansible.builtin.service:
            name: myapp
            state: restarted

        - name: Send failure notification
          ansible.builtin.uri:
            url: "{{ slack_webhook }}"
            method: POST
            body_format: json
            body:
              text: "Deployment of {{ deploy_version }} FAILED on {{ inventory_hostname }} - rolled back"
          delegate_to: localhost

        - name: Fail the play after rollback
          ansible.builtin.fail:
            msg: "Deployment failed and was rolled back. Check logs on {{ inventory_hostname }}"

      always:
        - name: Clean up backup
          ansible.builtin.file:
            path: "{{ backup_path }}"
            state: absent

        - name: Record deployment attempt
          ansible.builtin.lineinfile:
            path: /var/log/deployments.log
            line: "{{ ansible_date_time.iso8601 }} - {{ deploy_version }} - {{ 'SUCCESS' if health is defined and health is succeeded else 'FAILED' }}"
            create: yes
```

---

## Execution Strategies

### Linear (Default)

Each task runs on all hosts before proceeding to the next task.

```yaml
- hosts: all
  strategy: linear
```

### Free

Each host runs through all tasks as fast as possible, independently.

```yaml
- hosts: all
  strategy: free
```

Useful when tasks are independent per host and you want maximum parallelism.

### Throttle (Per-Task Concurrency Limit)

```yaml
- name: API call with rate limiting
  ansible.builtin.uri:
    url: "https://api.example.com/register/{{ inventory_hostname }}"
    method: POST
  throttle: 2   # Max 2 concurrent executions
```

---

## Async Tasks in Orchestration

### Fire-and-Forget with Later Check

```yaml
- name: Long-running operations
  hosts: all
  tasks:
    - name: Start system update
      ansible.builtin.apt:
        upgrade: dist
      async: 3600    # Max runtime: 1 hour
      poll: 0        # Don't wait
      register: update_job

    - name: Continue with other tasks
      ansible.builtin.debug:
        msg: "System update running in background on {{ inventory_hostname }}"

    - name: Wait for updates to complete
      ansible.builtin.async_status:
        jid: "{{ update_job.ansible_job_id }}"
      register: job_result
      until: job_result.finished
      retries: 60
      delay: 60
```

---

## Import vs Include

### Static Import (Parsed at Load Time)

```yaml
# Imports are resolved before play execution
- name: Configure servers
  hosts: webservers
  tasks:
    - ansible.builtin.import_tasks: tasks/install.yml
    - ansible.builtin.import_tasks: tasks/configure.yml
      tags: configure   # Tag applies to all imported tasks
```

- Tags and `when` conditions propagate to all imported tasks
- Visible in `--list-tasks` output
- Cannot be used with loops

### Dynamic Include (Parsed at Runtime)

```yaml
# Includes are resolved during execution
- name: Configure servers
  hosts: webservers
  tasks:
    - ansible.builtin.include_tasks: "tasks/{{ ansible_os_family | lower }}.yml"

    - ansible.builtin.include_tasks: tasks/optional.yml
      when: feature_enabled

    - ansible.builtin.include_role:
        name: "{{ role_name }}"
      loop: "{{ required_roles }}"
```

- Tags and `when` apply to the include statement only, not child tasks
- Not visible in `--list-tasks`
- Can be used with loops and runtime variables

### When to Use Each

| Use Case | Recommendation |
|---|---|
| Unconditional, always-included tasks | `import_tasks` |
| OS-specific task files | `include_tasks` (runtime file selection) |
| Conditional role inclusion | `include_role` with `when:` |
| Role in a loop | `include_role` with `loop:` |
| Tag-based selective execution | `import_tasks` (tags propagate) |

---

## Complete Multi-Tier Deployment Example

```yaml
---
# site.yml - Full infrastructure deployment

- name: Apply common configuration
  hosts: all
  become: yes
  roles:
    - common
    - security
  tags: common

- name: Deploy and configure databases
  hosts: databases
  become: yes
  roles:
    - postgresql
  tags: database

- name: Deploy application (rolling)
  hosts: webservers
  become: yes
  serial:
    - 1
    - "50%"
  max_fail_percentage: 10
  pre_tasks:
    - name: Disable in monitoring
      ansible.builtin.uri:
        url: "http://{{ monitoring_host }}/api/downtime"
        method: POST
        body_format: json
        body:
          host: "{{ inventory_hostname }}"
          duration: 600
      delegate_to: localhost

  roles:
    - myapp

  post_tasks:
    - name: Verify application health
      ansible.builtin.uri:
        url: "http://localhost:{{ app_port }}/health"
        status_code: 200
      retries: 10
      delay: 5

    - name: Re-enable in monitoring
      ansible.builtin.uri:
        url: "http://{{ monitoring_host }}/api/downtime/{{ inventory_hostname }}"
        method: DELETE
      delegate_to: localhost
  tags: app

- name: Update load balancer
  hosts: loadbalancers
  become: yes
  roles:
    - haproxy
  tags: lb
```

Run selectively with tags:
```bash
# Full deployment
ansible-playbook site.yml

# Only application deployment
ansible-playbook site.yml --tags app

# Skip database changes
ansible-playbook site.yml --skip-tags database

# Target specific hosts
ansible-playbook site.yml --limit 'webservers:&staging'
```

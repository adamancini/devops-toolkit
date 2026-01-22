# CMX VM Management

This reference provides detailed patterns for creating, managing, and using Replicated's Compatibility Matrix (CMX) VMs for testing.

## Overview

CMX provides ephemeral VMs for testing Kubernetes distributions and applications across different:
- **Operating Systems**: Ubuntu 22.04, Ubuntu 24.04, AlmaLinux 8
- **Instance Types**: r1.medium (4 vCPU, 8GB RAM), r1.large (8 vCPU, 16GB RAM), r1.xlarge (16 vCPU, 32GB RAM)
- **Cluster Topologies**: Single-node, multi-node, HA configurations

VMs are provisioned on-demand with configurable TTL (time-to-live) and automatic cleanup.

## VM Creation

### Single VM Creation

```bash
replicated vm create \
  --name my-test-vm \
  --distribution ubuntu \
  --version 24.04 \
  --instance-type r1.medium \
  --disk 100 \
  --ttl 8h \
  --wait 5m
```

**Parameters:**
- `--name` - Unique VM name (must be unique across your account)
- `--distribution` - OS distribution (`ubuntu`, `almalinux`)
- `--version` - OS version (`22.04`, `24.04` for Ubuntu; `8` for AlmaLinux)
- `--instance-type` - VM size (`r1.medium`, `r1.large`, `r1.xlarge`)
- `--disk` - Disk size in GB (default: 50, recommended: 100+)
- `--ttl` - Time-to-live (e.g., `8h`, `24h`, `7d`)
- `--wait` - Wait for VM to be ready (e.g., `5m`, `10m`)

**Optional parameters:**
- `--ssh-public-key <path>` - Custom SSH public key file
- `--ssh-public-key-github <username>` - Use GitHub user's public keys
- `--tag <key>=<value>` - Arbitrary tags for organization (e.g., `--tag cluster=myapp`)
- `--network <network-id>` - Attach to existing network (for multi-node clusters)
- `--count <n>` - Create multiple VMs with same config (names will be suffixed)

### Multi-Node Cluster Creation

Multi-node clusters require sequential creation to establish network connectivity:

#### Step 1: Create First Node (Establishes Network)

```bash
replicated vm create \
  --name myapp-control-1 \
  --distribution ubuntu --version 24.04 \
  --instance-type r1.xlarge \
  --disk 100 \
  --ttl 8h \
  --tag role=control \
  --tag cluster=myapp \
  --wait 5m
```

**Output:** VM ID, network ID, IP address

#### Step 2: Get Network ID

```bash
network_id=$(replicated vm ls --output json | \
  jq -r '.[] | select(.name == "myapp-control-1") | .network_id' | head -1)

echo "Network ID: $network_id"
```

#### Step 3: Create Additional Nodes on Same Network

```bash
replicated vm create \
  --name myapp-control-2 \
  --distribution ubuntu --version 24.04 \
  --instance-type r1.xlarge \
  --disk 100 \
  --ttl 8h \
  --network $network_id \
  --tag role=control \
  --tag cluster=myapp \
  --wait 5m
```

**Parallel creation for performance:**

```bash
# Create remaining nodes in parallel
for i in 2 3; do
  replicated vm create \
    --name myapp-control-$i \
    --distribution ubuntu --version 24.04 \
    --instance-type r1.xlarge \
    --disk 100 \
    --ttl 8h \
    --network $network_id \
    --tag role=control \
    --tag cluster=myapp \
    --wait 5m &
done
wait  # Wait for all background jobs to complete
```

### Cluster Topology Patterns

#### 2-Node Cluster (1 Control + 1 Worker)

Minimal HA setup for development:

```bash
# Control node
replicated vm create --name myapp-control-1 \
  --distribution ubuntu --version 24.04 \
  --instance-type r1.medium --disk 100 --ttl 8h \
  --tag role=control --tag cluster=myapp --wait 5m

# Get network ID
network_id=$(replicated vm ls --output json | \
  jq -r '.[] | select(.name == "myapp-control-1") | .network_id')

# Worker node
replicated vm create --name myapp-worker-1 \
  --distribution ubuntu --version 24.04 \
  --instance-type r1.medium --disk 100 --ttl 8h \
  --network $network_id \
  --tag role=worker --tag cluster=myapp --wait 5m
```

#### 3-Node Cluster (All Control Plane)

Recommended HA configuration:

```bash
# Control-1 (establishes network)
replicated vm create --name myapp-control-1 \
  --distribution ubuntu --version 24.04 \
  --instance-type r1.xlarge --disk 100 --ttl 8h \
  --tag role=control --tag cluster=myapp --wait 5m

# Get network ID
network_id=$(replicated vm ls --output json | \
  jq -r '.[] | select(.name == "myapp-control-1") | .network_id')

# Control-2 and Control-3 in parallel
for i in 2 3; do
  replicated vm create --name myapp-control-$i \
    --distribution ubuntu --version 24.04 \
    --instance-type r1.xlarge --disk 100 --ttl 8h \
    --network $network_id \
    --tag role=control --tag cluster=myapp --wait 5m &
done
wait
```

#### 6-Node Cluster (3 Control + 3 Worker)

Production-like HA configuration:

```bash
# Control-1 (establishes network)
replicated vm create --name myapp-control-1 \
  --distribution ubuntu --version 24.04 \
  --instance-type r1.xlarge --disk 100 --ttl 8h \
  --tag role=control --tag cluster=myapp --wait 5m

# Get network ID
network_id=$(replicated vm ls --output json | \
  jq -r '.[] | select(.name == "myapp-control-1") | .network_id')

# Control-2 and Control-3 in parallel
for i in 2 3; do
  replicated vm create --name myapp-control-$i \
    --distribution ubuntu --version 24.04 \
    --instance-type r1.xlarge --disk 100 --ttl 8h \
    --network $network_id \
    --tag role=control --tag cluster=myapp --wait 5m &
done

# Workers 1-3 in parallel
for i in 1 2 3; do
  replicated vm create --name myapp-worker-$i \
    --distribution ubuntu --version 24.04 \
    --instance-type r1.xlarge --disk 100 --ttl 8h \
    --network $network_id \
    --tag role=worker --tag cluster=myapp --wait 5m &
done
wait
```

## VM Listing and Inspection

### List All VMs

```bash
# Table format
replicated vm ls

# JSON format
replicated vm ls --output json

# Filter by tags
replicated vm ls --output json | jq '.[] | select(.tags.cluster == "myapp")'
```

**Output fields:**
- VM ID (unique identifier)
- Name
- Status (running, pending, stopped, terminated)
- IP address (internal and public)
- Distribution and version
- Instance type
- Network ID
- Tags
- Creation time
- TTL expiration

### Get Specific VM Details

```bash
# By ID
replicated vm inspect <vm-id>

# By name (using jq)
replicated vm ls --output json | \
  jq '.[] | select(.name == "myapp-control-1")'
```

### Check VM Status

```bash
# Get VM ID
vm_id=$(replicated vm ls --output json | \
  jq -r '.[] | select(.name == "myapp-control-1") | .id')

# Check status
status=$(replicated vm ls --output json | \
  jq -r ".[] | select(.id == \"$vm_id\") | .status")

echo "VM status: $status"
```

## SSH Access and Command Execution

### Direct SSH Access

```bash
# SSH by VM ID
replicated vm ssh <vm-id>

# SSH by name (resolve ID first)
vm_id=$(replicated vm ls --output json | \
  jq -r '.[] | select(.name == "myapp-control-1") | .id')
replicated vm ssh $vm_id
```

**Interactive session:**
```bash
replicated vm ssh myapp-control-1
# Now in interactive shell on VM
$ kubectl get nodes
$ sudo systemctl status k0scontroller
$ exit
```

### Remote Command Execution

Execute commands without interactive session:

```bash
# Single command
replicated vm ssh <vm-id> -- 'kubectl get nodes'

# Multi-line command
replicated vm ssh <vm-id> -- 'kubectl get nodes && kubectl get pods -A'

# With sudo
replicated vm ssh <vm-id> -- 'sudo systemctl status k0scontroller'
```

### File Transfer

**Download from VM:**
```bash
# Get kubeconfig
replicated vm ssh $vm_id -- \
  'sudo cat /var/lib/embedded-cluster/k0s/pki/admin.conf' > kubeconfig.yaml

# Get logs
replicated vm ssh $vm_id -- \
  'sudo journalctl -u k0scontroller --no-pager' > controller.log
```

**Upload to VM:**
```bash
# Upload via stdin
cat local-file.yaml | \
  replicated vm ssh $vm_id -- 'cat > /tmp/remote-file.yaml'

# Upload script and execute
cat script.sh | \
  replicated vm ssh $vm_id -- 'bash -s'
```

### Parallel Command Execution

Execute commands on multiple nodes simultaneously:

```bash
# Get all control node IDs
control_vms=$(replicated vm ls --output json | \
  jq -r '.[] | select(.tags.cluster == "myapp" and .tags.role == "control") | .id')

# Execute command on all control nodes in parallel
for vm_id in $control_vms; do
  replicated vm ssh $vm_id -- 'kubectl get nodes' &
done
wait
```

### Long-Running Commands

For operations that take >5 minutes, use extended timeouts or background execution:

```bash
# Background execution pattern
replicated vm ssh $vm_id -- 'nohup long-running-command > /tmp/output.log 2>&1 &'

# Poll for completion
while true; do
  status=$(replicated vm ssh $vm_id -- 'pgrep -f long-running-command')
  if [ -z "$status" ]; then
    echo "Command completed"
    replicated vm ssh $vm_id -- 'cat /tmp/output.log'
    break
  fi
  echo "Still running..."
  sleep 30
done
```

## Waiting for VM Readiness

### Wait for SSH Access

VMs need 2-3 minutes after creation for SSH to be ready:

```bash
# Create VM
replicated vm create --name test-vm --distribution ubuntu --version 24.04 --wait 5m

# Wait for SSH to be ready
vm_id=$(replicated vm ls --output json | jq -r '.[] | select(.name == "test-vm") | .id')

for i in {1..30}; do
  if replicated vm ssh $vm_id -- 'echo ready' 2>/dev/null; then
    echo "SSH ready"
    break
  fi
  echo "Waiting for SSH... (attempt $i/30)"
  sleep 10
done
```

### Wait for Cluster Readiness

After installing Kubernetes, wait for cluster to be operational:

```bash
# Wait for nodes to be ready
replicated vm ssh $vm_id -- '
  until kubectl get nodes | grep -q Ready; do
    echo "Waiting for nodes to be ready..."
    sleep 10
  done
  kubectl get nodes
'

# Wait for system pods
replicated vm ssh $vm_id -- '
  until [ $(kubectl get pods -n kube-system -o json | \
    jq "[.items[] | select(.status.phase == \"Running\")] | length") -gt 5 ]; do
    echo "Waiting for system pods..."
    sleep 10
  done
  kubectl get pods -A
'
```

## Port Exposure

Expose VM ports for external access:

### Expose Ports

```bash
# Get VM ID
vm_id=$(replicated vm ls --output json | \
  jq -r '.[] | select(.name == "myapp-control-1") | .id')

# Expose single port
replicated vm port expose $vm_id \
  --host-port 30000 \
  --protocols http,https

# Expose multiple ports
replicated vm port expose $vm_id \
  --host-port 31000 \
  --protocols http,https

replicated vm port expose $vm_id \
  --host-port 31101 \
  --protocols http
```

**Parameters:**
- `--host-port` - Port to expose
- `--vm-port` - VM port to forward to (defaults to same as host-port)
- `--protocols` - Comma-separated protocols (`http`, `https`, `tcp`, `udp`)

### List Exposed Ports

```bash
replicated vm port ls $vm_id
```

**Output:**
- Host port
- VM port
- Protocols
- Public URL (for http/https)

### Access Exposed Ports

```bash
# Get public URLs
urls=$(replicated vm port ls $vm_id --output json | \
  jq -r '.[].url')

echo "Access your application at:"
echo "$urls"
```

**Example output:**
```
https://amancini-control-1-30000.cmx.replicated.com
https://amancini-control-1-31000.cmx.replicated.com
http://amancini-control-1-31101.cmx.replicated.com
```

### Remove Port Exposure

```bash
# Remove specific port
replicated vm port rm $vm_id --host-port 30000

# Remove all ports
replicated vm port ls $vm_id --output json | \
  jq -r '.[].hostPort' | \
  xargs -I {} replicated vm port rm $vm_id --host-port {}
```

## Configuration Management

### Dynamic Configuration Files

Generate configuration files with actual VM hostnames:

```bash
# Get exposed hostname
vm_id=$(replicated vm ls --output json | \
  jq -r '.[] | select(.name == "myapp-control-1") | .id')

hostname=$(replicated vm port ls $vm_id --output json | \
  jq -r '.[0].url' | sed 's|https\?://||' | sed 's|:[0-9]*$||')

# Generate config with hostname
cat > config.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  hostname: "$hostname"
  admin_url: "https://$hostname:30000"
  app_url: "https://$hostname:31000"
EOF
```

### Copy Configuration to VM

```bash
# Copy config file
cat config.yaml | \
  replicated vm ssh $vm_id -- 'cat > /tmp/config.yaml'

# Verify
replicated vm ssh $vm_id -- 'cat /tmp/config.yaml'
```

## VM Lifecycle Management

### Extend TTL

Extend VM lifetime via vendor portal or API:

```bash
# Via vendor portal:
# 1. Navigate to Compatibility Matrix
# 2. Find VM in list
# 3. Click "Extend TTL"
# 4. Set new expiration time
```

### Stop and Start VMs

```bash
# Stop VM (preserves state, stops billing)
replicated vm stop <vm-id>

# Start stopped VM
replicated vm start <vm-id>

# Restart VM
replicated vm restart <vm-id>
```

### Delete VMs

```bash
# Delete single VM
replicated vm rm <vm-id>

# Delete multiple VMs
replicated vm rm <vm-id-1> <vm-id-2> <vm-id-3>

# Delete all VMs in cluster (by tag)
replicated vm ls --output json | \
  jq -r '.[] | select(.tags.cluster == "myapp") | .id' | \
  xargs replicated vm rm

# Interactive deletion (prompt for each)
replicated vm ls --output json | \
  jq -r '.[] | select(.tags.cluster == "myapp") | "\(.id) \(.name)"' | \
  while read vm_id vm_name; do
    read -p "Delete $vm_name ($vm_id)? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      replicated vm rm $vm_id
    fi
  done
```

## Makefile Integration Patterns

### Parameterized Cluster Creation

```makefile
# Variables
CLUSTER_PREFIX ?= myapp
VM_DISTRIBUTION ?= ubuntu
VM_VERSION ?= 24.04
INSTANCE_TYPE ?= r1.xlarge
DISK_SIZE ?= 100
TTL ?= 8h

# Get network ID from control-1
.PHONY: vm-get-network-id
vm-get-network-id:
	@replicated vm ls --output json | \
	  jq -r '.[] | select(.name == "$(CLUSTER_PREFIX)-control-1") | .network_id' | head -1

# Create 3-node cluster
.PHONY: vm-3node
vm-3node:
	@echo "Creating 3-node cluster: $(CLUSTER_PREFIX)"
	replicated vm create \
	  --name $(CLUSTER_PREFIX)-control-1 \
	  --distribution $(VM_DISTRIBUTION) --version $(VM_VERSION) \
	  --instance-type $(INSTANCE_TYPE) --disk $(DISK_SIZE) --ttl $(TTL) \
	  --tag role=control --tag cluster=$(CLUSTER_PREFIX) --wait 5m
	$(eval NETWORK_ID := $(shell $(MAKE) vm-get-network-id))
	for i in 2 3; do \
	  replicated vm create \
	    --name $(CLUSTER_PREFIX)-control-$$i \
	    --distribution $(VM_DISTRIBUTION) --version $(VM_VERSION) \
	    --instance-type $(INSTANCE_TYPE) --disk $(DISK_SIZE) --ttl $(TTL) \
	    --network $(NETWORK_ID) \
	    --tag role=control --tag cluster=$(CLUSTER_PREFIX) --wait 5m & \
	done; \
	wait

# SSH to first control node
.PHONY: vm-ssh
vm-ssh:
	@vm_id=$$(replicated vm ls --output json | \
	  jq -r '.[] | select(.name == "$(CLUSTER_PREFIX)-control-1") | .id'); \
	replicated vm ssh $$vm_id

# Execute kubectl command
.PHONY: vm-kubectl
vm-kubectl:
	@[ "$(CMD)" ] || (echo "CMD not set"; exit 1)
	@vm_id=$$(replicated vm ls --output json | \
	  jq -r '.[] | select(.name == "$(CLUSTER_PREFIX)-control-1") | .id'); \
	replicated vm ssh $$vm_id -- 'kubectl $(CMD)'

# Cleanup cluster
.PHONY: vm-cleanup
vm-cleanup:
	@echo "Cleaning up cluster: $(CLUSTER_PREFIX)"
	@replicated vm ls --output json | \
	  jq -r '.[] | select(.tags.cluster == "$(CLUSTER_PREFIX)") | .id' | \
	  xargs -n 1 replicated vm rm
```

## Troubleshooting

### VM Creation Issues

**"Quota exceeded":**
- List all VMs: `replicated vm ls`
- Delete unused VMs
- Contact Replicated support for quota increase

**Network creation failures:**
- Verify first node completes successfully before creating additional nodes
- Check for naming conflicts
- Ensure network ID is correctly retrieved

**Timeout during creation:**
- Increase `--wait` timeout
- Check Replicated status page for service issues
- Retry creation

### SSH Connection Problems

**Connection timeout:**
- Wait 2-3 minutes after VM creation for SSH to be ready
- Verify VM status is "running": `replicated vm ls`
- Check VM is not being terminated

**Permission denied:**
- Verify SSH key configuration
- Use `--ssh-public-key-github <username>` for GitHub keys
- Check key has correct permissions (600 for private key)

**Command execution failures:**
- Use `--` to separate SSH command from arguments
- Quote complex commands properly
- Check sudo requirements for privileged operations

### Port Exposure Issues

**Cannot access exposed ports:**
- Verify port is exposed: `replicated vm port ls <vm-id>`
- Check firewall rules on VM
- Ensure service is listening on correct port: `replicated vm ssh <vm-id> -- 'ss -tlnp'`
- Wait a few minutes for DNS propagation

**Port already in use:**
- List all exposed ports
- Use different host port number
- Remove conflicting port mapping first

## Best Practices

**Cluster Naming:**
- Use consistent prefix for all VMs in a cluster (e.g., `myapp-control-1`, `myapp-control-2`)
- Include role in name (`control`, `worker`, `backend`)
- Use GitHub username as prefix to avoid collisions (e.g., `adamancini-control-1`)

**Resource Management:**
- Tag VMs with cluster name and role for easy filtering
- Set appropriate TTL values (8h for development, 24h for testing, 7d for long-running)
- Clean up VMs when done to manage costs
- Monitor quota usage regularly

**Network Configuration:**
- Always create first node, get network ID, then create remaining nodes
- Use parallel creation for multiple nodes (background with `&`, then `wait`)
- Verify network connectivity between nodes after creation

**SSH Operations:**
- Use extended timeouts for slow operations (10+ minutes)
- Implement retry logic for transient failures
- Poll for completion on long-running operations
- Capture output for debugging

**Security:**
- Limit VM TTL to minimum necessary time
- Use custom SSH keys when possible
- Don't expose unnecessary ports
- Delete VMs immediately when done testing
- Rotate SSH keys periodically

**Automation:**
- Parameterize cluster creation in Makefiles or scripts
- Implement idempotent operations where possible
- Add error handling and validation
- Log all operations for debugging
- Use consistent naming conventions

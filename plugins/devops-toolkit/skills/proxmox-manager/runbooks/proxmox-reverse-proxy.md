---
name: proxmox-reverse-proxy
description: Configure HAProxy reverse proxy for Proxmox VE web UI with WebSocket support
image_type: none
requires: [ssh]
tested_with:
  proxmox: "8.x"
---

# Proxmox Reverse Proxy (HAProxy)

Configure HAProxy to reverse-proxy the Proxmox VE web UI through a shared VIP, with proper WebSocket support for the VM console and correct session handling.

## Parameters

- pve_backend_name: HAProxy backend name for Proxmox (default: `proxmox_servers`)
- pve_sni: SNI hostname for Proxmox (e.g., `pve.annarchy.net`)
- pve_nodes: List of Proxmox nodes with addresses (e.g., `pve01:10.0.0.21, pve02:10.0.0.22, pve03:10.0.0.23`)
- vip: HAProxy frontend bind address (e.g., `10.0.0.6`)

## Background

The Proxmox web UI (`pveproxy`) has specific requirements that differ from typical HTTP backends:

1. **TLS termination:** pveproxy serves HTTPS on port 8006 with a self-signed certificate. It redirects HTTP to HTTPS internally. If HAProxy terminates TLS and forwards plaintext HTTP, pveproxy sees HTTP and issues a redirect, creating an infinite loop.

2. **WebSocket support:** The VNC/SPICE console uses WebSocket connections that must be kept alive for the duration of the console session. These connections hold a pveproxy worker process.

3. **Session stickiness:** The Proxmox GUI maintains session state per backend node. Without sticky sessions, requests that hit a different node will fail authentication.

4. **Worker limits:** pveproxy has a limited number of worker processes (default: 3). Long-lived WebSocket connections from console sessions consume workers. Under load, new connections get 503 errors.

## Steps

### 1. Configure pveproxy Workers (SSH -- all PVE nodes)

Increase the pveproxy worker count to handle concurrent console sessions:

```bash
ssh <SSH_USER>@<NODE_HOST> 'cat > /etc/default/pveproxy << EOF
WORKERS=4
TIMEOUT=600
ALLOW_FROM=10.0.0.0/23
EOF'
```

Restart pveproxy:

```bash
ssh <SSH_USER>@<NODE_HOST> 'systemctl restart pveproxy'
```

Repeat for all PVE nodes.

**Notes:**
- `WORKERS=4` allows 4 concurrent connections per node (adjust based on console usage)
- `TIMEOUT=600` keeps idle connections alive for 10 minutes (matches HAProxy timeout)
- `ALLOW_FROM` restricts direct API access to the local subnet (optional; HAProxy handles external access)

### 2. Configure HAProxy Frontend (SNI-based TCP passthrough)

**Use TCP passthrough mode** for Proxmox to avoid redirect loops. HAProxy routes by SNI (Server Name Indication) without terminating TLS:

```
frontend https_vhost
  bind <VIP>:443
  mode tcp
  tcp-request inspect-delay 5s
  tcp-request content accept if { req_ssl_hello_type 1 }

  acl is_proxmox req_ssl_sni -i <PVE_SNI>

  use_backend <PVE_BACKEND_NAME> if is_proxmox
```

This frontend inspects the TLS ClientHello to extract the SNI hostname, then routes to the appropriate backend without decrypting the traffic.

### 3. Configure HAProxy Backend (sticky sessions, health checks)

```
backend <PVE_BACKEND_NAME>
  mode tcp
  balance roundrobin
  stick-table type ip size 256 expire 30m
  stick on src
  option tcp-check
  server pve01 10.0.0.21:8006 check check-ssl verify none
  server pve02 10.0.0.22:8006 check check-ssl verify none
  server pve03 10.0.0.23:8006 check check-ssl verify none
```

**Key settings:**
- `stick on src`: Source-IP affinity ensures a user's session stays on the same backend node
- `check-ssl verify none`: Health checks connect via SSL but don't verify the self-signed cert
- `mode tcp`: TCP passthrough -- HAProxy does not inspect or modify the encrypted traffic

### 4. Dedicated Kubernetes API Frontend (port 6443)

If sharing the same VIP for Kubernetes API load balancing:

```
frontend kubernetes_api
  bind <VIP>:6443
  mode tcp
  default_backend kubernetes_api_servers

backend kubernetes_api_servers
  mode tcp
  balance roundrobin
  server cp01 10.0.0.31:6443 check check-ssl verify none
  server cp02 10.0.0.32:6443 check check-ssl verify none
  server cp03 10.0.0.33:6443 check check-ssl verify none
```

**Note for Talos clusters:** If the Talos cluster has a built-in VIP (configured in machine config), the Kubernetes API does not need HAProxy. Point DNS directly at the Talos VIP instead. Only clusters without built-in VIP support (e.g., k0s) need HAProxy for API load balancing.

### 5. Verify Configuration

```bash
# Test HAProxy config syntax
ssh <SSH_USER>@<LB_HOST> 'haproxy -c -f /etc/haproxy/haproxy.cfg'

# Reload HAProxy
ssh <SSH_USER>@<LB_HOST> 'systemctl reload haproxy'

# Test Proxmox access through the proxy
curl -sk -o /dev/null -w "%{http_code}" https://<PVE_SNI>:443/
```

Expected: `200` (or `301` redirect to the login page). If you get a redirect loop, verify you're using TCP passthrough mode (not HTTP mode with TLS termination).

## Cleanup

No cleanup needed -- the configuration is persistent across HAProxy restarts.

## Notes

- **TCP passthrough vs TLS termination:** TCP passthrough is strongly recommended for Proxmox. TLS termination requires setting `X-Forwarded-Proto: https` and configuring pveproxy to trust the proxy header, which is fragile and not officially documented.
- **WebSocket timeout:** The `stick-table expire 30m` and pveproxy `TIMEOUT=600` should be aligned. If console sessions drop after a timeout, increase both values.
- **503 errors during console use:** Increase `WORKERS` in `/etc/default/pveproxy`. Each active console session holds one worker for its duration.
- **DNS configuration:** Create an A record for `<PVE_SNI>` pointing to the HAProxy VIP (e.g., `pve.annarchy.net -> 10.0.0.6`). Do not point it at individual PVE nodes.
- **Multiple services on one VIP:** Use SNI-based routing in the `https_vhost` frontend to multiplex Proxmox, Kubernetes API, and other services on the same IP:443.

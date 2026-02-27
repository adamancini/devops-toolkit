---
topic: synology-dsm-troubleshooting
source: hands-on debugging session 2026-02-27
created: 2026-02-27
updated: 2026-02-27
tags:
  - synology
  - dsm
  - synocgid
  - login
  - kubernetes
  - synology-csi
  - cascading-failure
---

# Synology DSM Login Failure: synocgid Daemon Inactive

## Summary

When `synocgid` (the privileged CGI daemon) is inactive on Synology DSM, the web GUI login page loads but spins forever. Authentication succeeds at the PAM/FIDO layer but session creation fails silently, returning an empty `sid` in the API response. This also breaks the Synology CSI driver in Kubernetes clusters since the CSI driver uses the same webapi for storage operations.

## Symptoms

- DSM web GUI login page loads (HTTP 200) but login spinner never completes
- SSH access works normally
- Auto-block database (`/etc/synoautoblock.db`) is empty -- not an IP block issue
- User account is not locked/disabled/expired
- Firewall rules are permissive (no DROP/REJECT)
- System resources are healthy (CPU, RAM, disk, RAID all fine)

## Diagnostic Flow

### 1. Rule Out Common Causes First

```bash
# Check auto-block (most common cause of login lockout)
sqlite3 /etc/synoautoblock.db 'SELECT * FROM AutoBlockIP WHERE Deny = 1;'

# Check account status
synouser --get <username>
# Look for: Expired: [false]

# Check firewall
/usr/syno/bin/synofirewall --enum IPV4
```

### 2. Test the Login API Directly

```bash
curl -sk http://localhost:5000/webapi/entry.cgi \
  -d 'api=SYNO.API.Auth&version=6&method=login&account=USERNAME&passwd=PASSWORD&session=DSM&format=sid' \
  --max-time 15
```

**Key indicator:** If the response has `"success":true` but `"sid":""` (empty session ID), the auth layer works but session creation is broken.

### 3. Check synocgid Status

```bash
# This is the critical check
synosystemctl get-active-status synocgid
```

If `inactive`, this is the root cause. Also visible in journalctl:

```bash
journalctl -u synoscgi --no-pager -n 30
# Look for: "Failed to connect synocgid socket. (Connection refused)"
```

### 4. Verify with HAR File Analysis (Browser)

If you captured a HAR file from the browser, look for `SYNO.API.Auth` entries. The telltale sign is:
- `"success": true`
- `"sid": ""`  (empty string)
- `"synotoken": ""`  (empty string)

## Resolution

```bash
# Restart synocgid
synosystemctl restart synocgid

# Verify it's running
synosystemctl get-active-status synocgid
# Should show: active

ps aux | grep synocgid | grep -v grep
# Should show: /usr/syno/sbin/synocgid -D

# Test login API again - sid should now be populated
curl -sk http://localhost:5000/webapi/entry.cgi \
  -d 'api=SYNO.API.Auth&version=6&method=login&account=USERNAME&passwd=PASSWORD&session=DSM&format=sid' \
  --max-time 15
```

## Cascading Failures

### Synology CSI Driver in Kubernetes

When `synocgid` is down, the Synology CSI driver loses the ability to manage storage because it communicates with the NAS via the same webapi. This causes:

1. **PVC provisioning failures** -- new PersistentVolumeClaims cannot be fulfilled
2. **Volume attach/detach failures** -- pods requiring Synology-backed PVCs get stuck in Pending/ContainerCreating
3. **iSCSI session disruptions** -- existing iSCSI targets may fail to re-authenticate
4. **Cascading pod failures** -- any pod with a Synology PVC that gets rescheduled (node drain, eviction, OOM) cannot start on the new node
5. **StatefulSet disruptions** -- StatefulSets with Synology PVCs cannot scale or recover from pod failures

### Detection

In Kubernetes, watch for these signs pointing to a NAS-side issue:

```bash
# CSI driver errors
kubectl logs -n synology-csi -l app=synology-csi-controller --tail=50
# Look for: connection refused, auth failures, timeout

# Stuck PVCs
kubectl get pvc -A | grep -v Bound

# Pods stuck on volume operations
kubectl get pods -A | grep -E 'ContainerCreating|Pending'
kubectl describe pod <stuck-pod> -n <ns>
# Look for: "FailedAttachVolume" or "FailedMount" events
```

## DSM Service Architecture

Understanding the service dependency chain helps diagnose similar issues:

```
nginx (port 5000/5001)
  └── synoscgi (CGI workers)
        ├── synocgid (privileged daemon - session mgmt, share listing, root operations)
        │     └── /run/synocgid/*.socket (Unix domain sockets)
        ├── synoscgi_socket.js (Node.js socket bridge)
        └── SecureSignIn (FIDO2/passkey service)
```

- **nginx** -- Serves static assets and proxies API calls to synoscgi
- **synoscgi** -- Worker processes that handle webapi requests
- **synocgid** -- Privileged daemon that synoscgi delegates to for root operations (session creation, share listing, iSCSI management, etc.)
- **synoscgi_socket.js** -- Node.js bridge between nginx and synoscgi

If `synocgid` is down but everything else is up, the login page loads fine (nginx serves static files) and auth succeeds (synoscgi handles PAM), but session creation fails (requires synocgid).

## Key File Locations

| Path | Purpose |
|------|---------|
| `/etc/synoautoblock.db` | SQLite DB for IP auto-block list |
| `/usr/syno/etc/private/session/current.users` | Active session file (JSON lines) |
| `/usr/syno/etc/private/session/syno-access-token.db` | Access token SQLite DB |
| `/usr/syno/etc/private/session/syno-pam-key.db` | PAM key SQLite DB |
| `/run/synocgid/` | synocgid Unix domain sockets |
| `/tmp/SynologyAuthService/` | Loop-mounted auth service filesystem |
| `/var/log/auth.log` | PAM authentication log |
| `/var/log/synoscgi.log` | synoscgi service log |

## Key CLI Tools

| Command | Purpose |
|---------|---------|
| `synosystemctl get-active-status <unit>` | Check service status |
| `synosystemctl restart <unit>` | Restart a service |
| `synouser --get <username>` | Check user account status |
| `synoautoblock --reset <ip>` | Remove IP from auto-block |
| `/usr/syno/bin/synofirewall --enum IPV4` | List firewall rules |
| `synopkg status <package>` | Check package status |

## Key Service Units

| Unit | Purpose |
|------|---------|
| `synocgid` | Privileged CGI daemon (session mgmt, shares, root ops) |
| `synoscgi` | CGI worker processes |
| `syno-login` | Web console login prepare |
| `SecureSignIn` | FIDO2/passkey package |

## Lessons Learned

1. **Empty `sid` with `success:true` always points to synocgid** -- the auth and session layers are separate; auth can succeed while session creation fails
2. **Don't waste time on auto-block, firewall, or account lockout** if SSH works fine and the login page loads -- those would prevent page load entirely
3. **HAR files are invaluable** -- they immediately reveal whether the issue is client-side (page not loading) vs API-side (responses returning errors/empty data)
4. **Check synocgid early** in any DSM web GUI debugging -- it's not obvious but it's the single point of failure for all privileged webapi operations
5. **Synology NAS failures cascade into Kubernetes** when using Synology CSI -- monitor NAS health as part of cluster health
6. **The DSM web stack has multiple layers** -- nginx, synoscgi, synocgid, SecureSignIn -- each can fail independently with different symptoms

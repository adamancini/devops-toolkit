---
topic: nmap
source: https://nmap.org/nsedoc/scripts/http-traceroute.html
created: 2026-02-26
updated: 2026-02-26
tags:
  - nmap
  - network-security
  - proxy-detection
  - http
  - reconnaissance
---

# Nmap http-traceroute NSE Script

## Summary

`http-traceroute` is an Nmap NSE script (categories: `discovery`, `safe`) that detects reverse proxies by exploiting the HTTP `Max-Forwards` header. It sends probes with incrementing Max-Forwards values (0, 1, 2) and reports response differences -- in status code, Server header, Content-Type, Content-Length, Last-Modified, or HTML title -- that indicate proxy hop points.

## Key Concepts

**Mechanism:** The `Max-Forwards` header (RFC 7231) is decremented by each HTTP intermediary on TRACE/OPTIONS requests. By comparing responses at values 0, 1, and 2, the script identifies where responses diverge, revealing proxy nodes.

**What it detects:**
- Reverse proxies (nginx, HAProxy, Traefik, Envoy)
- Load balancers (that modify response headers)
- WAFs and API gateways
- CDN edge nodes

**Limitations:**
- Proxies that ignore or strip `Max-Forwards` will not be detected
- TRACE method is commonly disabled server-side; GET is the default fallback
- Identical responses across all hops = no detected proxy (but not a guarantee)

**Script metadata:**
- Author: Hani Benhabiles
- Based on: Nicolas Gregoire and Julien Cayssol (agarri.fr, 2011)
- Libraries: `http`, `nmap`, `shortport`, `stdnse`, `table`

## Practical Application

### Basic usage

```bash
nmap --script=http-traceroute <target>
```

### Recommended: use TRACE method

```bash
nmap --script=http-traceroute \
  --script-args="http-traceroute.method=TRACE" \
  <target>
```

### Specific path probe

```bash
nmap --script=http-traceroute \
  --script-args="http-traceroute.path=/api/v1,http-traceroute.method=TRACE" \
  <target>
```

### HTTPS target

```bash
nmap -p 443 --script=http-traceroute <target>
```

### Scan multiple HTTP ports with service detection

```bash
nmap -sV -p 80,443,8080,8443 --script=http-traceroute <target>
```

### Script arguments reference

| Argument | Default | Notes |
|----------|---------|-------|
| `http-traceroute.path` | `/` | Path to probe |
| `http-traceroute.method` | `GET` | Use `TRACE` for better proxy detection |
| `http.*` | — | Standard http library args (useragent, pipeline, max-body-size) |
| `slaxml.debug` | — | XML parser debug output |

### Example output

```
PORT   STATE SERVICE
80/tcp open  http
| http-traceroute:
|   Max-Forwards: 0
|     Status Code: 200
|     Server: Apache/2.4.7
|   Max-Forwards: 1
|     Status Code: 200
|     Server: nginx/1.18.0
|_  Max-Forwards: 2
```

In this example, the differing `Server` header between hops 0 and 1 reveals nginx as a reverse proxy in front of Apache.

## Decision Points

**Use GET (default) when:** TRACE is likely disabled (most production environments); still detects proxies that transform response headers.

**Use TRACE when:** Testing a controlled environment where TRACE is known to be enabled; provides cleaner hop-by-hop request echo.

**Complement with:** `http-headers` and `http-server-header` NSE scripts for richer header fingerprinting. Use `ssl-cert` on port 443 targets to identify TLS termination points (often the first proxy hop).

**False negatives:** A proxy that passes through headers unchanged and does not decrement Max-Forwards will be invisible to this script. Corroborate with `traceroute`, CDN headers (`CF-Ray`, `X-Cache`, `Via`), or timing analysis.

## References

- [NSE Script page](https://nmap.org/nsedoc/scripts/http-traceroute.html)
- [RFC 7231 §5.1.2 - Max-Forwards](https://datatracker.ietf.org/doc/html/rfc7231#section-5.1.2)
- [Nmap NSE Documentation](https://nmap.org/book/nse.html)
- Vault note: `personal/homelab/Nmap http-traceroute NSE Script.md`

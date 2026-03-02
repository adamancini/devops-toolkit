---
topic: kubernetes-networking
source: hands-on implementation in fleet-infra (annarchy.net)
created: 2026-03-01
updated: 2026-03-01
tags:
  - kubernetes
  - gateway-api
  - traefik
  - ingress
  - cert-manager
  - external-dns
---

# Gateway API with Traefik

## Summary

Gateway API v1.4.1 (experimental channel) running alongside Traefik v3's existing IngressRoute and Ingress providers. CRDs managed by Flux with safe flags (`prune: false`, `force: true`). cert-manager auto-provisions Gateway listener certificates. external-dns creates DNS records from HTTPRoute hostnames. No migration of existing routes required -- purely additive.

## Key Concepts

### Gateway API CRD Channels

- **Standard**: GatewayClass, Gateway, HTTPRoute, GRPCRoute, ReferenceGrant
- **Experimental** (superset of standard): adds TCPRoute, TLSRoute, UDPRoute, BackendTLSPolicy, ListenerSets
- Traefik's `experimentalChannel: true` enables TCPRoute/TLSRoute support

### CRD Installation Methods

Two methods, used at different lifecycle stages:

1. **Bootstrap** (imperative, before Flux): `kubectl apply --server-side` from GitHub release YAML
2. **Steady-state** (declarative, Flux-managed): Kustomize remote resource with `?ref=<tag>` pin

Both must target the same version. The Flux kustomization takes over management after bootstrap.

### Traefik Gateway Provider

Enabled via Helm values:

```yaml
providers:
  kubernetesGateway:
    enabled: true
    experimentalChannel: true
```

Traefik auto-registers a `traefik` GatewayClass (controller: `traefik.io/gateway-controller`). No manual GatewayClass creation needed.

### Flux CRD Management Flags

| Flag | Value | Why |
|------|-------|-----|
| `prune` | `false` | Prevents Flux from deleting CRDs if source temporarily disappears (would cascade-delete all Gateway/HTTPRoute resources) |
| `force` | `true` | Required for large CRDs that exceed SSA annotation limits; resolves field-manager conflicts during upgrades |
| `wait` | `true` | Ensures CRDs are Established before downstream kustomizations (Traefik, core-config) proceed |

## Practical Application

### Traefik-Specific Port Mapping

Gateway listener ports must match Traefik's internal entrypoint ports, NOT the external service ports:

| Listener | Protocol | Port (Gateway) | Traefik Entrypoint | External Port |
|----------|----------|----------------|-------------------|---------------|
| https | HTTPS | **8443** | websecure | 443 |
| http | HTTP | **8000** | web | 80 |

Using 443/80 in the Gateway spec will fail because Traefik binds to 8443/8000 internally (the Service maps external 443→8443, 80→8000).

### Gateway Resource Pattern

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: traefik-gateway
  namespace: traefik
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
spec:
  gatewayClassName: traefik
  listeners:
    - name: https
      protocol: HTTPS
      port: 8443              # Traefik entrypoint port, not 443
      hostname: "*.example.com"
      tls:
        mode: Terminate
        certificateRefs:
          - name: cluster-wildcard-cert
      allowedRoutes:
        namespaces:
          from: All           # Required for cross-namespace HTTPRoutes
    - name: http
      protocol: HTTP
      port: 8000              # Traefik entrypoint port, not 80
      hostname: "*.example.com"
      allowedRoutes:
        namespaces:
          from: All
```

### HTTPRoute Pattern

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-route
  namespace: my-app
spec:
  parentRefs:
    - name: traefik-gateway
      namespace: traefik
      sectionName: https      # Target specific listener
  hostnames:
    - "myapp.example.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: my-service
          port: 80
```

### cert-manager Integration

Add `--enable-gateway-api` to cert-manager's extraArgs. Then annotate Gateway resources with `cert-manager.io/cluster-issuer: <issuer-name>`. cert-manager watches Gateway listeners and auto-provisions certificates for their hostnames -- same flow as Ingress annotation-based certs.

### external-dns Integration

Add `gateway-httproute` to external-dns sources:

```yaml
sources:
  - service
  - ingress
  - traefik-proxy
  - gateway-httproute
```

Unlike IngressRoutes (which need a `target` annotation), HTTPRoutes get DNS records automatically from their `hostnames` field.

## Decision Points

### Gateway API vs IngressRoute

| Factor | Gateway API (HTTPRoute) | Traefik IngressRoute |
|--------|------------------------|---------------------|
| Portability | Standard K8s API, works with any controller | Traefik-specific CRD |
| Maturity | GA since v1.0 (Oct 2023), v1.2+ well-adopted | Stable, mature |
| Feature coverage | HTTP routing, TLS, traffic splitting | Full Traefik feature set (middleware chains, TCP/UDP, circuit breakers) |
| external-dns | Automatic from hostnames field | Requires `target` annotation |
| cert-manager | Automatic via Gateway annotation | Automatic via Ingress annotation |
| Cross-namespace | Built-in with ReferenceGrant | Requires `allowCrossNamespace: true` |

**Use HTTPRoute when:** New services, standard HTTP routing, portability matters, want automatic DNS/TLS.

**Use IngressRoute when:** Need Traefik-specific middleware chains, complex routing rules, or existing IngressRoutes that work fine.

**Coexistence:** Both providers run simultaneously. No migration pressure -- adopt Gateway API for new services, keep IngressRoutes for existing ones.

### Experimental vs Standard Channel

**Use experimental when:** You need TCPRoute/TLSRoute (Traefik supports them natively), or want the full CRD set for future use.

**Use standard when:** You only need HTTPRoute/GRPCRoute and want a smaller CRD footprint.

### Single Gateway vs Per-Namespace Gateways

**Single shared Gateway** (recommended for small clusters): One Gateway in the `traefik` namespace with `allowedRoutes.namespaces.from: All`. Simpler management, single TLS config.

**Per-namespace Gateways**: Each namespace owns its Gateway. Better isolation and independent TLS, but more complex. Use ReferenceGrant for cross-namespace certificate references.

## References

- [Gateway API Official Docs](https://gateway-api.sigs.k8s.io/)
- [Gateway API v1.4.1 Release](https://github.com/kubernetes-sigs/gateway-api/releases/tag/v1.4.1)
- [Traefik Gateway API Provider](https://doc.traefik.io/traefik/routing/providers/kubernetes-gateway/)
- [cert-manager Gateway API](https://cert-manager.io/docs/usage/gateway/)
- [external-dns Gateway API](https://kubernetes-sigs.github.io/external-dns/latest/sources/gateway-api/)
- Fleet-infra memory: `~/.claude/projects/-Users-ada-src-github-com-adamancini-fleet-infra/memory/gateway-api.md`

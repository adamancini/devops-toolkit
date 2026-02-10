---
topic: kubernetes-networking
source: https://traefik.io/blog/migrate-from-ingress-nginx-to-traefik-now
created: 2026-02-10
updated: 2026-02-10
tags:
  - kubernetes
  - ingress
  - traefik
  - migration
  - security
---

# Migrate from Ingress NGINX to Traefik

## Summary

Ingress NGINX retires March 2026. Traefik provides a drop-in replacement via its NGINX Provider (`--providers.kubernetesIngressNGINX`), which processes existing `nginx.ingress.kubernetes.io` annotations without manifest changes. This enables a two-phase migration: immediate decommissioning, then Gateway API modernization on your own timeline.

## Key Concepts

### Why Migrate Now

- **IngressNightmare CVEs** demonstrated cluster compromise via configuration injection in Ingress NGINX
- Root cause: C/C++ memory safety issues and template-based config generation
- Traefik avoids both attack classes: Go with static linking, structured parsing (no templating)
- Security patches for Ingress NGINX will cease at retirement

### Traefik NGINX Provider

- Enabled with `--providers.kubernetesIngressNGINX` flag
- Processes `nginx.ingress.kubernetes.io` annotations natively
- Covers ~80% of real-world NGINX annotation patterns
- Unsupported annotations can be requested via GitHub issues
- No Ingress manifest modifications required -- same `ingressClassName: nginx` works

### Supported Annotations (Confirmed)

- `nginx.ingress.kubernetes.io/auth-type`
- `nginx.ingress.kubernetes.io/auth-secret-type`
- `nginx.ingress.kubernetes.io/auth-secret`
- `nginx.ingress.kubernetes.io/auth-realm`
- `nginx.ingress.kubernetes.io/ssl-redirect`

### Gateway API

- Traefik v3.6 provides full Gateway API v1.4 support
- Gateway API is the successor to Ingress for Kubernetes networking
- Phase 2 of migration: adopt Gateway API after stabilizing on Traefik

## Practical Application

### Deploy Traefik Alongside Existing NGINX (Testing)

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik --namespace traefik \
  --create-namespace \
  --set="image.tag=v3.6.2" \
  --set="logs.general.level=DEBUG" \
  --set="service.type=ClusterIP" \
  --set="additionalArguments={--providers.kubernetesIngressNGINX}"
```

Key: `service.type=ClusterIP` prevents LoadBalancer conflict during parallel testing.

### Verify with Port-Forward

```bash
kubectl port-forward -n traefik services/traefik 9000:80 9443:443
```

Test all existing Ingress resources against the forwarded Traefik endpoints.

### Cutover to Production

```bash
helm upgrade --install traefik traefik/traefik --namespace traefik \
  --create-namespace \
  --set="image.tag=v3.6.2" \
  --set="service.type=LoadBalancer" \
  --set="additionalArguments={--providers.kubernetesIngressNGINX}"
```

Then: remove Ingress NGINX deployment, update DNS to Traefik's external IP.

### Progressive Migration (Large Deployments)

1. Deploy new clusters running Traefik
2. Gradually transition workloads and Ingress configs
3. Validate per-service before removing legacy NGINX
4. Implement rollback mechanisms at each step

## Decision Points

| Factor | Traefik | F5 NGINX Ingress | HAProxy Ingress | Cloud Provider |
|--------|---------|-------------------|-----------------|----------------|
| NGINX annotation compat | Native (80%) | Partial | None | None |
| Manifest changes needed | None | Some | Full rewrite | Full rewrite |
| Gateway API support | Full v1.4 | Partial | Partial | Varies |
| Architecture safety | Go, structured parsing | C/C++, templates | C, custom | Varies |

**Choose Traefik when:** You need a fast migration path with minimal manifest changes and want a clear path to Gateway API.

**Consider alternatives when:** You need specific NGINX features in the unsupported 20%, or your organization already standardizes on another ingress controller.

## References

- [Traefik NGINX Provider Docs](https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-ingress-nginx/)
- [Traefik Helm Chart](https://traefik.github.io/charts)
- [Traefik GitHub](https://github.com/traefik/traefik)
- [Gateway API Docs](https://gateway-api.sigs.k8s.io/)
- Obsidian note: `~/notes/work/kubernetes/Migrate from Ingress NGINX to Traefik.md`

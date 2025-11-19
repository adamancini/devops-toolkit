# SSL Certificate Manager

Comprehensive SSL/TLS certificate management for Let's Encrypt with automated DNS challenges, Kubernetes integration, and renewal workflows.

## Features

### Automated DNS Challenges

Generate certificates using DNS provider APIs:
- **Google Cloud DNS**: Service account with DNS Administrator role
- **Cloudflare**: API token with Zone DNS Edit permissions
- **Route53**: AWS credentials with route53 permissions

### Manual DNS Challenges

Step-by-step guidance for any DNS provider when API access isn't available.

### Certificate Operations

- Generate wildcard certificates (`*.example.com`)
- Inspect certificates with openssl
- Monitor expiration dates
- Renew certificates before expiry
- Create Kubernetes TLS secrets
- Export for various use cases

## Quick Start

### Automated DNS Challenge (Google Cloud DNS)

```
User: "Create a wildcard certificate for *.example.com using Google Cloud DNS"
```

The skill will:
1. Verify credentials at `~/letsencrypt/credentials.json`
2. Run certbot with dns-google plugin in Docker
3. Generate certificate with both `*.example.com` and `example.com`
4. Display certificate details and expiration
5. Optionally create Kubernetes TLS secret

### Manual DNS Challenge

```
User: "Create a certificate for example.com using manual DNS"
```

The skill will:
1. Start certbot with manual DNS challenge
2. Display TXT record to create: `_acme-challenge.example.com`
3. Guide you through DNS provider setup
4. Verify DNS propagation
5. Complete certificate generation

## Configuration

### Google Cloud DNS

```bash
# Create service account with DNS Administrator role
# Download JSON key and place at:
~/letsencrypt/credentials.json
```

### Cloudflare

```bash
# Create API token with Zone DNS Edit permissions
# Create credentials file:
cat > ~/letsencrypt/cloudflare.ini <<EOF
dns_cloudflare_api_token = your-api-token-here
EOF

chmod 600 ~/letsencrypt/cloudflare.ini
```

### Route53

```bash
# Set environment variables:
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

## Usage Examples

### Generate Wildcard Certificate

```
"Create a wildcard certificate for *.lab.example.com using Cloudflare"
```

Result:
- Certificate: `~/letsencrypt/live/lab.example.com/fullchain.pem`
- Private key: `~/letsencrypt/live/lab.example.com/privkey.pem`
- Valid for 90 days

### Inspect Certificate

```
"Show me the expiration date of my example.com certificate"
```

Output:
```
Certificate: /Users/ada/letsencrypt/live/example.com/cert.pem
Subject: CN=example.com
Issuer: Let's Encrypt Authority X3
Not Before: Nov 19 14:30:00 2025 GMT
Not After: Feb 17 14:30:00 2026 GMT (89 days remaining)
SANs: example.com, *.example.com
```

### Renew Certificate

```
"Renew my example.com certificate"
```

The skill will:
1. Check current expiration (renew if < 30 days)
2. Run renewal command
3. Update Kubernetes secrets if configured
4. Verify new expiration date

### Create Kubernetes TLS Secret

```
"Create a Kubernetes TLS secret from my example.com certificate"
```

Result:
```bash
kubectl create secret tls example-com-tls \
  --cert=/Users/ada/letsencrypt/live/example.com/fullchain.pem \
  --key=/Users/ada/letsencrypt/live/example.com/privkey.pem \
  -n default
```

## Certificate File Structure

After generation, certificates are stored in `~/letsencrypt/live/example.com/`:

```
cert.pem        # Server certificate only
chain.pem       # Intermediate certificates
fullchain.pem   # Server cert + intermediates (use this for most servers)
privkey.pem     # Private key (keep secure!)
README          # Information about the certificate files
```

## Kubernetes Integration

### Create TLS Secret

```bash
kubectl create secret tls example-com-tls \
  --cert=~/letsencrypt/live/example.com/fullchain.pem \
  --key=~/letsencrypt/live/example.com/privkey.pem \
  -n your-namespace
```

### Use in Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
spec:
  tls:
  - hosts:
    - example.com
    - "*.example.com"
    secretName: example-com-tls
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: example-service
            port:
              number: 80
```

## Troubleshooting

### DNS Propagation Issues

```bash
# Check if DNS record exists
dig _acme-challenge.example.com TXT

# Check from different nameservers
dig @8.8.8.8 _acme-challenge.example.com TXT
dig @1.1.1.1 _acme-challenge.example.com TXT

# Use online checker
# https://www.whatsmydns.net/
```

**Solution**: Wait 5-10 minutes for DNS propagation, set TTL to 60 seconds initially.

### Rate Limits

Let's Encrypt limits:
- 50 certificates per registered domain per week
- 5 duplicate certificates per week

**Solution**: Use staging environment for testing:
```bash
--server https://acme-staging-v02.api.letsencrypt.org/directory
```

### Docker Issues

**Error**: `Cannot connect to Docker daemon`

**Solution**:
```bash
# Start Docker
open -a Docker

# Verify Docker is running
docker ps
```

### Permission Issues

**Error**: `Permission denied: '/etc/letsencrypt'`

**Solution**:
```bash
# Ensure directories exist and are writable
mkdir -p ~/letsencrypt ~/opt/letsencrypt/lib ~/opt/letsencrypt/log
chmod 755 ~/letsencrypt
```

## Best Practices

1. **Include both apex and wildcard**:
   ```
   -d example.com -d "*.example.com"
   ```
   This covers both the base domain and all subdomains.

2. **Start with staging for testing**:
   Avoid hitting production rate limits during setup.

3. **Set short TTL initially**:
   Use 60-second TTL for `_acme-challenge` records during testing.

4. **Secure private keys**:
   ```bash
   chmod 600 ~/letsencrypt/live/*/privkey.pem
   ```
   Never commit private keys to git.

5. **Automate renewal**:
   Certificates expire in 90 days. Renew at 60 days.

6. **Monitor expiration**:
   Set reminders 30 days before expiration.

## Advanced: cert-manager for Kubernetes

For production Kubernetes clusters, consider cert-manager for automatic certificate management:

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Create ClusterIssuer
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - dns01:
        cloudDNS:
          project: your-gcp-project
          serviceAccountSecretRef:
            name: clouddns-dns01-solver
            key: key.json
EOF
```

Then annotate Ingress resources for automatic certificate management.

## Security

- Private keys stored locally in `~/letsencrypt/`
- Never commit certificates or keys to git
- DNS provider credentials should be properly secured
- Follow least-privilege principle for service accounts
- Restrict file permissions: `chmod 600` for keys

## Common Workflows

### Development Environment

1. Generate certificate with staging environment
2. Test application with certificate
3. Generate production certificate
4. Deploy to development cluster

### Production Deployment

1. Generate certificate with production Let's Encrypt
2. Create Kubernetes TLS secret
3. Configure Ingress to use secret
4. Set up renewal reminders (60 days)
5. Monitor expiration dates

### Certificate Renewal

1. Check expiration: < 30 days remaining
2. Run renewal command
3. Update Kubernetes secrets
4. Verify new certificate is active
5. Update monitoring/reminders

## Support

For issues or questions:
- Check [main plugin README](../../README.md)
- Review [troubleshooting section](#troubleshooting) above
- Open issue on [GitHub](https://github.com/adamancini/devops-toolkit/issues)

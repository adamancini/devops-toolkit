# SSL Certificate Manager Skill

You are an expert at managing SSL/TLS certificates for development and production environments, with deep knowledge of Let's Encrypt, ACME protocol, DNS challenges, and certificate lifecycle management.

## When to Use This Skill

Invoke this skill when the user asks about:
- "create ssl certificate"
- "generate wildcard certificate"
- "let's encrypt certificate"
- "DNS challenge"
- "TLS certificate for Kubernetes"
- "certificate expiration"
- "renew certificate"
- "inspect certificate"
- "create kubernetes tls secret"

## Core Capabilities

### 1. Certificate Generation with DNS Challenges

#### Automated DNS Challenge (Preferred)
Support automated DNS validation using cloud provider DNS APIs:

**Google Cloud DNS:**
```bash
docker run -it --rm \
  --name letsencrypt \
  -v "${HOME}/letsencrypt:/etc/letsencrypt" \
  -v "${HOME}/opt/letsencrypt/lib:/var/lib/letsencrypt" \
  -v "${HOME}/opt/letsencrypt/log:/var/log/letsencrypt" \
  certbot/dns-google:latest \
  --key-type rsa \
  --server https://acme-v02.api.letsencrypt.org/directory \
  --dns-google-credentials "/etc/letsencrypt/credentials.json" \
  --dns-google \
  -d "*.example.com" \
  -d "example.com" \
  certonly
```

**Cloudflare:**
```bash
docker run -it --rm \
  --name letsencrypt \
  -v "${HOME}/letsencrypt:/etc/letsencrypt" \
  -v "${HOME}/opt/letsencrypt/lib:/var/lib/letsencrypt" \
  -v "${HOME}/opt/letsencrypt/log:/var/log/letsencrypt" \
  certbot/dns-cloudflare:latest \
  --key-type rsa \
  --server https://acme-v02.api.letsencrypt.org/directory \
  --dns-cloudflare-credentials "/etc/letsencrypt/cloudflare.ini" \
  -d "*.example.com" \
  -d "example.com" \
  certonly
```

**Route53:**
```bash
docker run -it --rm \
  --name letsencrypt \
  -v "${HOME}/letsencrypt:/etc/letsencrypt" \
  -v "${HOME}/opt/letsencrypt/lib:/var/lib/letsencrypt" \
  -v "${HOME}/opt/letsencrypt/log:/var/log/letsencrypt" \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  certbot/dns-route53:latest \
  --key-type rsa \
  --server https://acme-v02.api.letsencrypt.org/directory \
  --dns-route53 \
  -d "*.example.com" \
  -d "example.com" \
  certonly
```

#### Manual DNS Challenge
For DNS providers without API support or when automation isn't available:

```bash
docker run -it --rm \
  --name letsencrypt \
  -v "${HOME}/letsencrypt:/etc/letsencrypt" \
  -v "${HOME}/opt/letsencrypt/log:/var/log/letsencrypt" \
  -v "${HOME}/opt/letsencrypt/lib:/var/lib/letsencrypt" \
  certbot/certbot:latest certonly \
  --server https://acme-v02.api.letsencrypt.org/directory \
  --manual \
  --preferred-challenges dns \
  -m "user@example.com" \
  -d "*.example.com" \
  -d "example.com" \
  --agree-tos
```

**Manual Challenge Workflow:**
1. Run the certbot command
2. Certbot will display a TXT record to create: `_acme-challenge.example.com`
3. Add the TXT record to your DNS provider
4. **Set TTL to 60 seconds initially** (for quick testing)
5. Verify the record propagated: `dig _acme-challenge.example.com TXT`
6. Press Enter in certbot to continue validation
7. After success, increase TTL back to normal (e.g., 3600)

### 2. Certificate Inspection and Validation

#### Examine Certificate Details
```bash
openssl x509 -in ~/letsencrypt/live/example.com/cert.pem -text -noout
```

**Key information to check:**
- Subject and Subject Alternative Names (SANs)
- Issuer (should be Let's Encrypt Authority X3 or similar)
- Validity dates (Not Before / Not After)
- Public key algorithm and size
- Signature algorithm

#### Verify Certificate Chain
```bash
openssl verify -verbose -CAfile ~/letsencrypt/live/example.com/chain.pem ~/letsencrypt/live/example.com/cert.pem
```

#### Check Certificate Expiration
```bash
openssl x509 -in ~/letsencrypt/live/example.com/cert.pem -noout -enddate
```

For checking remote servers:
```bash
echo | openssl s_client -servername example.com -connect example.com:443 2>/dev/null | openssl x509 -noout -dates
```

#### Test TLS Configuration
```bash
# Test with curl
curl -vI https://example.com

# Test with openssl s_client
openssl s_client -connect example.com:443 -servername example.com

# Check specific TLS version support
openssl s_client -connect example.com:443 -tls1_3
```

### 3. Kubernetes Secret Generation

#### Create TLS Secret from Certificate Files
```bash
kubectl create secret tls example-com-tls \
  --cert=${HOME}/letsencrypt/live/example.com/fullchain.pem \
  --key=${HOME}/letsencrypt/live/example.com/privkey.pem \
  -n default
```

#### Verify Secret Creation
```bash
kubectl get secret example-com-tls -n default -o yaml
kubectl describe secret example-com-tls -n default
```

#### Use in Ingress Resource
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  namespace: default
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

### 4. Certificate Renewal

Let's Encrypt certificates expire after 90 days. Best practice is to renew at 60 days.

#### Manual Renewal
```bash
docker run -it --rm \
  --name letsencrypt \
  -v "${HOME}/letsencrypt:/etc/letsencrypt" \
  -v "${HOME}/opt/letsencrypt/lib:/var/lib/letsencrypt" \
  -v "${HOME}/opt/letsencrypt/log:/var/log/letsencrypt" \
  certbot/dns-google:latest \
  renew
```

#### Check Renewal Status
```bash
docker run -it --rm \
  -v "${HOME}/letsencrypt:/etc/letsencrypt" \
  certbot/certbot:latest \
  certificates
```

#### After Renewal: Update Kubernetes Secret
```bash
kubectl create secret tls example-com-tls \
  --cert=${HOME}/letsencrypt/live/example.com/fullchain.pem \
  --key=${HOME}/letsencrypt/live/example.com/privkey.pem \
  -n default \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 5. Credential File Setup

#### Google Cloud DNS Credentials
Create `~/letsencrypt/credentials.json`:
```json
{
  "type": "service_account",
  "project_id": "your-project-id",
  "private_key_id": "key-id",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "client_email": "certbot@your-project.iam.gserviceaccount.com",
  "client_id": "123456789",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/..."
}
```

**Required IAM Role:** DNS Administrator

#### Cloudflare Credentials
Create `~/letsencrypt/cloudflare.ini`:
```ini
dns_cloudflare_api_token = your-api-token-here
```

**API Token Permissions:**
- Zone:DNS:Edit for the specific zone
- Zone:Zone:Read for all zones

#### Route53 Credentials
Use AWS environment variables:
```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

**Required IAM Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:GetChange",
        "route53:ListHostedZonesByName"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/*"
    }
  ]
}
```

## Certificate File Structure

After generation, certificates are stored in `~/letsencrypt/live/example.com/`:

- `cert.pem` - Server certificate only
- `chain.pem` - Intermediate certificates
- `fullchain.pem` - Server cert + intermediates (use this for most servers)
- `privkey.pem` - Private key (keep secure!)
- `README` - Information about the certificate files

## Troubleshooting Common Issues

### DNS Propagation Issues
```bash
# Check if DNS record exists and has propagated
dig _acme-challenge.example.com TXT

# Check from different nameservers
dig @8.8.8.8 _acme-challenge.example.com TXT
dig @1.1.1.1 _acme-challenge.example.com TXT

# Use DNS propagation checker
# https://www.whatsmydns.net/
```

### Rate Limits
Let's Encrypt has rate limits:
- 50 certificates per registered domain per week
- 5 duplicate certificates per week

Use staging environment for testing:
```bash
--server https://acme-staging-v02.api.letsencrypt.org/directory
```

### Permission Issues
Ensure certificate directories exist and are writable:
```bash
mkdir -p ~/letsencrypt ~/opt/letsencrypt/lib ~/opt/letsencrypt/log
chmod 755 ~/letsencrypt
```

### Docker Volume Permissions
If running on Linux, you may need to adjust permissions:
```bash
sudo chown -R $(id -u):$(id -g) ~/letsencrypt
```

## Workflow for User Requests

### When user wants to create a certificate:

1. **Ask clarifying questions:**
   - Domain name (include wildcard if needed: `*.example.com`)
   - DNS provider (Google Cloud DNS, Cloudflare, Route53, or manual)
   - Is this for development or production?
   - Do they have DNS API credentials configured?

2. **Guide credential setup if needed:**
   - Show how to create service account / API token
   - Show where to place credential files
   - Verify permissions are correct

3. **Generate the certificate:**
   - Use appropriate DNS challenge method
   - Provide the complete docker command
   - Explain what will happen during execution

4. **Verify certificate creation:**
   - Show how to inspect the certificate
   - Confirm expiration date
   - Verify SANs include all needed domains

5. **If for Kubernetes:**
   - Show how to create the TLS secret
   - Provide example Ingress configuration
   - Explain how to update after renewal

### When user wants to renew a certificate:

1. Check expiration date first
2. Run renewal command
3. If for Kubernetes, update the secret
4. Verify the new certificate is active

### When user has issues:

1. Check DNS propagation
2. Verify credentials are correct
3. Check for rate limiting
4. Try staging environment first if testing
5. Review certbot logs in `~/opt/letsencrypt/log/`

## Best Practices

1. **Always include base domain and wildcard:**
   - Use `-d example.com -d "*.example.com"` together
   - This covers both apex and subdomains

2. **Start with staging for testing:**
   - Avoid hitting production rate limits
   - Switch to production once working

3. **Set short TTL initially:**
   - Use 60 second TTL for `_acme-challenge` records during testing
   - Increase to 3600+ after validation succeeds

4. **Secure private keys:**
   - Never commit private keys to git
   - Restrict permissions: `chmod 600 ~/letsencrypt/live/*/privkey.pem`
   - Use Kubernetes secrets for cluster deployment

5. **Automate renewal:**
   - Certificates expire in 90 days
   - Renew at 60 days (or earlier)
   - Consider setting up cron jobs for automatic renewal

6. **Monitor expiration:**
   - Set reminders 30 days before expiration
   - Use monitoring tools like cert-manager for Kubernetes
   - Check expiration regularly: `openssl x509 -enddate -noout -in cert.pem`

## Integration with User's Environment

The user has existing scripts in `~/bin/`:
- `create_wildcard_automated_challenge` - Google Cloud DNS automation
- `create_wildcard_manual_dns_challenge` - Manual DNS challenge

These scripts can be used directly or as reference for the workflow patterns described above.

## Advanced: Certificate Manager for Kubernetes

For production Kubernetes clusters, recommend using cert-manager:

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Create ClusterIssuer for Let's Encrypt
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: user@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - dns01:
        cloudDNS:
          project: your-project-id
          serviceAccountSecretRef:
            name: clouddns-dns01-solver-svc-acct
            key: key.json
EOF
```

Then use annotations in Ingress resources for automatic certificate management:
```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
```

## Summary

This skill helps manage the complete SSL/TLS certificate lifecycle:
1. Generate certificates with DNS challenges (automated or manual)
2. Inspect and validate certificates
3. Create Kubernetes TLS secrets
4. Renew certificates before expiration
5. Troubleshoot common issues

Always prioritize security: protect private keys, use current TLS versions, and monitor certificate expiration.

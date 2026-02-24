---
topic: proxmox-letsencrypt-gcloud
source:
  - https://forum.proxmox.com/threads/lets-encrypt-gcloud-dns-challange-plugin.168142/
  - https://forum.proxmox.com/threads/google-domains-and-lets-encrypt-certificates-using-dns-validation-for-local-proxmox-servers.70337/
created: 2026-02-24
updated: 2026-02-24
tags:
  - proxmox
  - letsencrypt
  - certbot
  - acme
  - google-cloud-dns
  - ssl
  - certificates
---

# Let's Encrypt with Google Cloud DNS on Proxmox VE

## Summary

Automates TLS certificate issuance on Proxmox VE using Let's Encrypt ACME DNS-01 challenges validated against Google Cloud DNS. This avoids exposing HTTP ports and enables certificate issuance for local/private Proxmox hosts that are not publicly reachable. Supports wildcard certificates. Two authentication methods exist: full gcloud CLI auth (interactive) and service account key files (headless/automated, preferred).

## Key Concepts

### Why DNS-01 Instead of HTTP-01

Standard Let's Encrypt HTTP-01 validation requires the Proxmox host to be reachable on port 80 from the internet. DNS-01 validation proves domain ownership by creating a TXT record in the domain's DNS zone, which works for:

- Local/private Proxmox servers behind NAT
- Hosts with no inbound internet access
- Wildcard certificate requests (`*.home.example.com`)

### Architecture

```
Proxmox ACME client (pvenode)
  └── calls acme.sh with gcloud DNS plugin
        └── uses gcloud CLI to create _acme-challenge TXT record
              └── Google Cloud DNS serves the TXT record
                    └── Let's Encrypt validates and issues certificate
```

The ACME process runs as the `nobody` user on Proxmox, so gcloud credentials must be accessible to that user.

### Two Authentication Methods

| Method | Use Case | Credential Location |
|--------|----------|---------------------|
| Interactive gcloud auth | Initial testing, single host | `~nobody/.config/gcloud/` (copied from root) |
| Service account key file | Production, multi-host, automated | `/home/nobody/gcloud/apikey.json` |

**Service account key file is the recommended approach** -- it is self-contained, does not require interactive login, and supports least-privilege IAM roles.

### DNS Delegation Pattern (for Google Domains users)

If the primary domain is registered with Google Domains but the local subdomain zone is managed by Google Cloud DNS:

1. Create a Cloud DNS zone for the local subdomain (e.g., `home.example.com`)
2. In Google Domains, add NS records delegating the subdomain to Cloud DNS nameservers
3. Add a CNAME record: `_acme-challenge.proxmox.home` -> `home.example.com`
4. Cloud DNS handles the ACME TXT record creation/deletion automatically

This delegation approach keeps the primary domain's DNS untouched while allowing ACME automation on the subdomain.

## Practical Application

### Prerequisites

- Google Cloud project with Cloud DNS API enabled
- A DNS zone in Google Cloud DNS for the domain/subdomain
- A service account with **DNS Administrator** role (or **DNS Reader** for minimal privilege if using delegated zones)
- Service account JSON key file downloaded

### Step 1: Install Google Cloud CLI

```bash
apt update -y
apt install -y apt-transport-https ca-certificates gnupg curl
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
  gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
  tee /etc/apt/sources.list.d/google-cloud-sdk.list
apt update -y && apt install -y google-cloud-cli
```

### Step 2: Configure Nobody User Home Directory

```bash
mkdir -p /home/nobody/gcloud
# Copy service account key file to the host
# (e.g., via scp from workstation)
cp /tmp/my-service-account-key.json /home/nobody/gcloud/apikey.json
chown -R nobody:nogroup /home/nobody/
chmod 600 /home/nobody/gcloud/apikey.json
```

Optional symlink for compatibility (some Proxmox versions reference `/nonexistent` as nobody's home):

```bash
ln -sf /home/nobody /nonexistent
```

### Step 3: Register ACME Account in Proxmox

Via GUI: **Datacenter -> ACME -> Accounts -> Add**

- Account Name: `letsencrypt` (or any name)
- E-Mail: `admin@example.com`
- ACME Directory: `Let's Encrypt V2` (use Staging for testing first)
- Accept Terms of Service

Or via CLI:

```bash
pvenode acme account register letsencrypt admin@example.com --directory https://acme-v02.api.letsencrypt.org/directory
```

### Step 4: Create ACME DNS Challenge Plugin

Via GUI: **Datacenter -> ACME -> Challenge Plugins -> Add**

- Plugin ID: `gcloud`
- Validation Delay: `120` (seconds -- Google Cloud DNS propagation can be slow)
- DNS API: `gcloud`
- API Data (no leading/trailing spaces or blank lines):
  ```
  HOME=/home/nobody
  CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=/home/nobody/gcloud/apikey.json
  CLOUDSDK_CORE_PROJECT=my-gcp-project-id
  ```

Or via CLI:

```bash
pvenode acme plugin add dns gcloud \
  --api gcloud \
  --data 'HOME=/home/nobody' \
  --data 'CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=/home/nobody/gcloud/apikey.json' \
  --data 'CLOUDSDK_CORE_PROJECT=my-gcp-project-id' \
  --validation-delay 120
```

**Critical formatting note:** The API Data field is sensitive to whitespace. No spaces before or after each line, no blank lines in the block.

### Step 5: Add Domain to Node Certificate Config

Via GUI: **Node -> System -> Certificates -> ACME -> Add**

- Challenge Type: DNS
- Plugin: `gcloud`
- Domain: `proxmox.home.example.com`

### Step 6: Order Certificate

Via GUI: **Node -> System -> Certificates -> ACME -> Order Certificates Now**

Or via CLI:

```bash
pvenode acme cert order
```

### Step 7: Verify

Check certificate status:

```bash
pvenode acme cert info
```

Monitor DNS record propagation (for troubleshooting):

```bash
gcloud dns record-sets changes list --zone="my-zone-name"
```

### NTP Configuration (Recommended)

Accurate time is important for ACME certificate validation:

```bash
echo "server time.nist.gov iburst" > /etc/chrony/sources.d/ntp.conf
systemctl restart chronyd
```

## Decision Points

### Service Account vs Interactive Auth

| Factor | Service Account Key | Interactive gcloud auth |
|--------|---------------------|------------------------|
| Setup complexity | Lower (copy one JSON file) | Higher (run gcloud init, copy config dir) |
| Automation-friendly | Yes | No (requires interactive login) |
| Multi-host deployment | Easy (copy same key) | Tedious (per-host login) |
| Security | Key file can be rotated; restrict with IAM roles | Full user credentials; broader access |
| Recommended for | Production | One-off testing only |

### Validation Delay Tuning

- Default: 30 seconds
- Recommended: 90-120 seconds for Google Cloud DNS
- Google Cloud DNS propagation can take 60+ seconds
- If certificate orders fail with "DNS record not found" errors, increase the delay
- Maximum useful value: ~300 seconds (beyond this, investigate DNS config)

### Known Issues

**Validation delay bug in older PVE versions:** The `validation-delay` plugin setting may not be read correctly. If increasing the delay via GUI/CLI has no effect, patch `/usr/share/perl5/PVE/ACME/DNSChallenge.pm`:

```perl
# Change this line:
my $delay = $data->{'validation-delay'} // 30;
# To:
my $delay = $data->{plugin}->{'validation-delay'} // 30;
```

This bug has been observed in PVE 7.x. Check if your version is affected before applying.

### Renewal

Proxmox automatically handles certificate renewal via a daily timer. The ACME plugin configuration persists across renewals. Verify the timer is active:

```bash
systemctl list-timers | grep acme
```

## References

- [Proxmox ACME Certificate Management](https://pve.proxmox.com/wiki/Certificate_Management)
- [Google Cloud DNS Quickstart](https://cloud.google.com/dns/docs/quickstart)
- [Google Cloud Service Account Keys](https://cloud.google.com/iam/docs/keys-create-delete)
- [acme.sh DNS API - Google Cloud](https://github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_gcloud)
- [Proxmox Forum: gcloud DNS challenge plugin](https://forum.proxmox.com/threads/lets-encrypt-gcloud-dns-challange-plugin.168142/)
- [Proxmox Forum: Google Domains DNS validation](https://forum.proxmox.com/threads/google-domains-and-lets-encrypt-certificates-using-dns-validation-for-local-proxmox-servers.70337/)

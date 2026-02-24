---
name: letsencrypt-gcloud-dns
description: Configure Let's Encrypt certificates on Proxmox VE using Google Cloud DNS-01 challenge
image_type: none
requires: [ssh]
tested_with:
  proxmox: "8.x"
---

# Let's Encrypt with Google Cloud DNS Challenge

## Parameters

- gcp_project_id: Google Cloud project ID (required)
- service_account_key: Path to GCP service account JSON key on local workstation (required)
- domain: FQDN for the certificate, e.g., `proxmox.home.example.com` (required)
- plugin_name: ACME plugin identifier (default: `gcloud`)
- acme_account: ACME account name (default: `letsencrypt`)
- acme_email: Email for ACME account registration (required)
- validation_delay: Seconds to wait for DNS propagation (default: `120`)

## Prerequisites

- Google Cloud project with Cloud DNS API enabled
- DNS zone in Google Cloud DNS for the target domain/subdomain
- Service account with **DNS Administrator** IAM role
- Service account JSON key file downloaded to local workstation
- Proxmox host reachable via SSH

## Steps

1. **Install Google Cloud CLI** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'apt update -y && apt install -y apt-transport-https ca-certificates gnupg curl && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee /etc/apt/sources.list.d/google-cloud-sdk.list && apt update -y && apt install -y google-cloud-cli'
   ```
   Expected result: `google-cloud-cli` package installed successfully

2. **Create nobody home directory and deploy service account key** (SSH)
   ```bash
   scp <service_account_key> <SSH_USER>@<NODE_HOST>:/tmp/gcloud-apikey.json
   ssh <SSH_USER>@<NODE_HOST> 'mkdir -p /home/nobody/gcloud && mv /tmp/gcloud-apikey.json /home/nobody/gcloud/apikey.json && chown -R nobody:nogroup /home/nobody/ && chmod 600 /home/nobody/gcloud/apikey.json'
   ```
   Expected result: Key file at `/home/nobody/gcloud/apikey.json` owned by `nobody:nogroup`

3. **Create symlink for compatibility** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'ln -sf /home/nobody /nonexistent'
   ```
   Expected result: `/nonexistent` symlinks to `/home/nobody`

4. **Configure NTP** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'echo "server time.nist.gov iburst" > /etc/chrony/sources.d/ntp.conf && systemctl restart chronyd'
   ```
   Expected result: chronyd restarted with NTP source configured

5. **Register ACME account** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'pvenode acme account register <acme_account> <acme_email> --directory https://acme-v02.api.letsencrypt.org/directory'
   ```
   Expected result: ACME account registered with Let's Encrypt

6. **Create ACME DNS challenge plugin** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> "pvenode acme plugin add dns <plugin_name> --api gcloud --data 'HOME=/home/nobody' --data 'CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=/home/nobody/gcloud/apikey.json' --data 'CLOUDSDK_CORE_PROJECT=<gcp_project_id>' --validation-delay <validation_delay>"
   ```
   Expected result: Plugin `<plugin_name>` created with gcloud DNS API

7. **Add domain to node certificate configuration** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'pvenode config set --acme domains=<domain> --acmedomain0 <domain>,plugin=<plugin_name>'
   ```
   Expected result: Domain configured for ACME certificate

8. **Order certificate** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'pvenode acme cert order'
   ```
   Expected result: Certificate issued and installed; Proxmox web UI accessible via HTTPS with valid cert

9. **Verify certificate** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'pvenode acme cert info'
   ```
   Expected result: Certificate details showing correct domain and valid expiry

10. **Verify renewal timer** (SSH)
    ```bash
    ssh <SSH_USER>@<NODE_HOST> 'systemctl list-timers | grep acme'
    ```
    Expected result: Active timer for automatic certificate renewal

## Cleanup

- Remove the temporary key file from `/tmp` on the Proxmox host if not already moved
- Remove `gcloud-apikey.json` from local workstation `/tmp` if copied there

## Notes

- **Validation delay:** Google Cloud DNS propagation can take 60+ seconds. Start with 120s; increase to 180-300s if orders fail with "DNS record not found"
- **Multi-node:** Repeat steps 5-10 on each Proxmox node. Steps 1-4 only need to run once per host. The same service account key can be deployed to all nodes.
- **Staging first:** For initial testing, use `--directory https://acme-staging-v02.api.letsencrypt.org/directory` in step 5 to avoid rate limits
- **Validation delay bug (PVE 7.x):** If the `--validation-delay` setting has no effect, patch `/usr/share/perl5/PVE/ACME/DNSChallenge.pm` -- change `$data->{'validation-delay'}` to `$data->{plugin}->{'validation-delay'}`
- **API Data formatting:** The plugin data fields are whitespace-sensitive. No leading/trailing spaces, no blank lines between entries.
- **IAM least privilege:** The service account needs at minimum the `roles/dns.admin` IAM role on the project. For delegated zone setups, `roles/dns.reader` may suffice at project level with `roles/dns.admin` on the specific zone.
- **DNS delegation pattern:** If the primary domain uses a different registrar/DNS, delegate a subdomain's NS records to Google Cloud DNS, then create the zone in Cloud DNS for that subdomain. Add a CNAME for `_acme-challenge.<host>.<subdomain>` pointing to the Cloud DNS zone.

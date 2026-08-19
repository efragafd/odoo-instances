# GCE bootstrap

Operator quick reference for `gce-startup.sh`. The full narrative runbook is
Phase 6's job (`docs/server-deployment.md`); this covers the `gcloud`
commands the script assumes.

## Before creating the VM

1. **Reserve a static external IP:**
   ```
   gcloud compute addresses create odoo-server-ip --region=REGION
   gcloud compute addresses describe odoo-server-ip --region=REGION --format='get(address)'
   ```
2. **Point DNS at it, before the VM boots.** `gce-startup.sh` creates the
   first instance (if you pass `odoo-instance` metadata) on first boot, and
   acme-companion will try to get a Let's Encrypt certificate for it
   immediately. If the domain doesn't resolve to this IP yet, that request
   fails — a wrong-order run isn't fatal (Let's Encrypt is rate-limited, not
   one-shot; acme-companion retries), but it's needless failed attempts and
   delay. Create the A record first.

## Firewall

Only 80/443 need to be open to the internet; everything else, including
SSH, should go through [Identity-Aware Proxy
(IAP)](https://docs.cloud.google.com/iap/docs/using-tcp-forwarding) instead
of a public port.

```
gcloud compute firewall-rules create allow-http-https \
  --allow=tcp:80,tcp:443 \
  --target-tags=odoo-server

gcloud compute firewall-rules create allow-iap-ssh \
  --allow=tcp:22 \
  --source-ranges=35.235.240.0/20 \
  --target-tags=odoo-server
```

`35.235.240.0/20` is Google's documented IAP source range — not a
placeholder to fill in. Most GCP projects also carry a default
`default-allow-ssh` rule open to `0.0.0.0/0`; delete or disable it, or the
IAP-only restriction above does nothing:

```
gcloud compute firewall-rules delete default-allow-ssh
```

SSH in via:

```
gcloud compute ssh odoo-server --zone=ZONE --tunnel-through-iap
```

### Portainer

The original `user-data` this replaces ran a Portainer agent on 9000/9001
with no firewall rule of its own — reachable by anyone who found the IP.
`gce-startup.sh` does not install it. If you want it, add your own firewall
rule scoped to a specific source (your IP, or better, tunnel through IAP the
same way as SSH) before running it — don't publish 9000/9001 to
`0.0.0.0/0`.

## Sizing

- **Machine type:** `e2-medium` (2 vCPU / 4 GB) is the floor for one Odoo +
  Postgres instance. Size up per additional instance on the same VM.
- **Disk:** 30 GB minimum — Odoo's filestore and Postgres data both grow
  over time, on top of Docker images.
- **Swap:** `gce-startup.sh` creates a 2 GB `/swapfile` as a safety margin,
  not a substitute for right-sizing the machine.

## Create the VM

```
gcloud compute instances create odoo-server \
  --zone=ZONE \
  --machine-type=e2-medium \
  --image-family=ubuntu-2404-lts-amd64 \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=30GB \
  --address=odoo-server-ip \
  --tags=odoo-server \
  --metadata=odoo-instance=myclient,odoo-domain=odoo.example.com,odoo-version=19.0,odoo-contact=you@example.com \
  --metadata-from-file=startup-script=server/bootstrap/gce-startup.sh
```

Drop the `odoo-instance`/`odoo-domain`/`odoo-version`/`odoo-contact`
metadata entirely to provision just Docker + the shared proxy, and create
instances by hand afterward (`ssh` in, then
`instance-new NAME VERSION --profile server --domain D --contact E` — the
repo is cloned to `/opt/odoo-instances` by the startup script, and its
`bin/` is where that command lives).

## Re-running

`gce-startup.sh` runs on every boot (that's how GCE's `startup-script`
metadata works, unlike cloud-init's `user-data`). Every step in it is
written to be safe to repeat: package installs, the swap file, `git pull`,
`docker compose up -d`, and instance creation (skipped if the instance
directory already exists) all no-op cleanly on a re-run.

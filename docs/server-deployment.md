# Server deployment

End-to-end: a bare GCP project to a TLS-served Odoo instance. The
`gcloud`-level detail (firewall rules, sizing, IAP) lives in
`server/bootstrap/README.md`; this is the narrative walkthrough.

## 0. Before you start

- A GCP project with billing enabled and the Compute Engine API turned on.
- A domain (or subdomain) you control, so you can point a DNS A record at
  the VM.
- `gcloud` installed and authenticated (`gcloud auth login`,
  `gcloud config set project YOUR_PROJECT`).

## 1. Reserve a static IP and point DNS at it

```bash
gcloud compute addresses create odoo-server-ip --region=REGION
gcloud compute addresses describe odoo-server-ip --region=REGION --format='get(address)'
```

Create an A record for your domain pointing at that IP, **before**
continuing. `acme-companion` requests a Let's Encrypt certificate as soon
as the instance comes up; if DNS doesn't resolve yet, that request just
fails and retries later, but there's no reason to make it.

## 2. Firewall

```bash
gcloud compute firewall-rules create allow-http-https \
  --allow=tcp:80,tcp:443 \
  --target-tags=odoo-server

gcloud compute firewall-rules create allow-iap-ssh \
  --allow=tcp:22 \
  --source-ranges=35.235.240.0/20 \
  --target-tags=odoo-server

gcloud compute firewall-rules delete default-allow-ssh
```

The last line matters: most GCP projects ship a `default-allow-ssh` rule
open to `0.0.0.0/0`, which defeats the IAP-only restriction above if left
in place. See `server/bootstrap/README.md` for why `35.235.240.0/20`
specifically (it's Google's documented IAP range, not a placeholder).

## 3. Create the VM

```bash
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

On first boot, `gce-startup.sh` (see `server/bootstrap/`):

1. Installs Docker + the compose plugin, creates a 2 GB swap file
2. Clones this repo to `/opt/odoo-instances`
3. Brings up the shared `nginx-proxy` + `acme-companion` stack
4. Reads the `odoo-*` metadata above and runs
   `instance-new myclient 19.0 --profile server --domain odoo.example.com --contact you@example.com`
5. Installs the backup cron (see `docs/backup-restore.md`)

Boot takes a few minutes — package installs and the first `docker build`
aren't instant.

## 4. Verify

```bash
gcloud compute ssh odoo-server --zone=ZONE --tunnel-through-iap
```

On the VM:

```bash
docker ps                                   # nginx-proxy, acme-companion, myclient, myclient_db
docker logs myclient | tail                 # Odoo starting up
cat ~/dockers/myclient/config/odoo.conf     # confirm proxy_mode/list_db/admin_passwd landed
```

Then from your own machine: `https://odoo.example.com` should load Odoo,
with a valid certificate. If it doesn't yet, acme-companion may still be
retrying — check `docker logs nginx-proxy-le`.

**The database-manager password was printed once**, during instance
creation (in the VM's serial console output / `gcloud compute instances
get-serial-port-output` if you weren't watching), and is saved in
`~/dockers/myclient/config/odoo.conf`'s `admin_passwd` line. There's no
second place to recover it from.

## 5. Adding more instances on the same VM

The metadata-driven instance in step 3 is optional — `gce-startup.sh`
skips it entirely if `odoo-instance` metadata isn't set. Either way, add
more instances by hand over SSH:

```bash
instance-new secondclient 19.0 --profile server --domain second.example.com --contact you@example.com
```

Each is a fully separate container pair with its own domain — see "Where
are subdomains configured?" in `docs/troubleshooting.md` if you need one
instance answering on multiple hostnames.

## 6. Sizing beyond one instance

`e2-medium` (2 vCPU / 4 GB) is the floor for *one* Odoo + Postgres pair.
Each additional instance roughly doubles the load — size up
(`gcloud compute instances set-machine-type`, VM must be stopped) rather
than assuming the same VM scales indefinitely.

## What's not automated

- **Off-box backup copies** — `server/backup/` writes to local disk only.
  See `docs/backup-restore.md`.
- **OS patching** — `apt-get upgrade` isn't part of the boot script (it
  only installs what it needs, once, idempotently). Patch on your own
  schedule.
- **Portainer** — deliberately not installed by default; see
  `server/bootstrap/README.md` if you want it, and firewall it yourself.

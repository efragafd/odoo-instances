# odoo-instances

Tooling to run Odoo Community — locally for module development, or on a
VPS for real deployments. One set of templates, one set of scripts; local
vs. server is a `--profile` flag, not a different codebase.

Supports Odoo 12.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0 — see
`docs/version-matrix.md`.

## Setup

```bash
./setup
```

Checks for Docker + the compose plugin, and adds `bin/` to your `PATH`.

## Local development (5 minutes)

```bash
instance-new mymodule-dev 19.0        # dev profile by default: debugpy on :5678
instance-code mymodule-dev            # open it in VS Code
mkmod mymodule-dev my_module          # scaffold a module
```

Then in VS Code, run the "Odoo: Update" launch config to update the module
and attach the debugger. Full walkthrough: `docs/local-development.md`.

## Server deployment (VPS)

```bash
gcloud compute instances create odoo-server \
  --zone=ZONE --machine-type=e2-medium \
  --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
  --boot-disk-size=30GB --address=odoo-server-ip --tags=odoo-server \
  --metadata=odoo-instance=myclient,odoo-domain=odoo.example.com,odoo-version=19.0,odoo-contact=you@example.com \
  --metadata-from-file=startup-script=server/bootstrap/gce-startup.sh
```

Provisions Docker, a shared `nginx-proxy` + Let's Encrypt stack, and (given
the metadata above) a running Odoo instance with a TLS certificate. Needs
a static IP, DNS, and firewall rules set up first — full runbook:
`docs/server-deployment.md`.

Add more instances to an existing VM the same way as local, just with a
different profile:

```bash
instance-new secondclient 19.0 --profile server --domain second.example.com --contact you@example.com
```

## How it fits together

```
bin/            instance-* scripts (on PATH after ./setup) + mkmod
templates/
  _common/      compose base + local/dev/server overlays, odoo.conf, .vscode — shared by every version
  <version>/    just odoo_debug/Dockerfile + postgres-version.default — the only things that actually vary by version
server/
  bootstrap/    GCE startup script + the gcloud setup it expects
  proxy/        the shared nginx-proxy + acme-companion stack
  backup/       per-instance backup/restore/retention scripts
```

An instance is `~/dockers/<name>/` — its own `config/`, `addons/` (for
local/dev), `.env` (which version, which profile, generated credentials
for server instances), built from `templates/_common/compose.yml` plus
whichever `compose.<profile>.yml` overlay matches its `.env`.

## Docs

| | |
|---|---|
| `docs/local-development.md` | Full local dev walkthrough |
| `docs/server-deployment.md` | Full VPS deployment runbook |
| `docs/backup-restore.md` | Backup schedule, restore drill |
| `docs/version-matrix.md` | Odoo ↔ PostgreSQL ↔ base image, per version |
| `docs/tools-reference.md` | Every script's `--help`, generated — not hand-maintained |
| `docs/troubleshooting.md` | Failures actually hit while building this, and why |
| `docs/MIGRATION-PLAN.md` | How this repo got here — the audit, the decisions, what changed and why |

Every script also answers `--help` directly.

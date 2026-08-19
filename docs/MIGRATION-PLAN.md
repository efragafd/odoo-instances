# Migration Plan: unify `odoo-server-instances` into `odoo-instances`

Status: **in progress** — Phase 1 complete, awaiting go-ahead on Phase 2
Drafted: 2026-08-19
Scope: merge the VPS deployment tooling into this repo, modernize the runtime, add Odoo 17/18/19, and document everything.

---

## 1. Starting point

### `odoo-instances` (this repo, `master`)

Local development tooling. 18 `instance-*` bash scripts template a per-version folder from `templates/` into `~/dockers/$INSTANCE` by `sed`-replacing `{instance}`, then run `docker-compose up`.

- Templates: `12.0`, `14.0`, `15.0`
- Each has `docker-compose.yml`, `config/odoo.conf`, `.vscode/{launch,tasks,settings}.json`
- `.vscode` is wired for a debugpy *attach* on port 5678

### `odoo-instances` branch `origin/debug` (unmerged)

**Ahead of `master` and should be merged first.** Adds:

- `templates/16.0/`
- `templates/15.0-dev/`, `templates/16.0-dev/` — with `odoo_debug/Dockerfile` (multi-stage `base` → `debug`, installs debugpy, publishes 5678)
- `mkmod` that copies `.vscode` into the scaffolded module
- `instance-new` / `instance-up` fixes

### `odoo-server-instances`

VPS deployment. Five files:

| File | Role |
|---|---|
| `user-data` | cloud-init: apt, docker, Portainer agent, nginx-proxy, first instance |
| `nginx-proxy-le.yml` | jwilder nginx-proxy + Let's Encrypt companion |
| `odoo-postgres.yml` | per-instance stack with `VIRTUAL_HOST` / `LETSENCRYPT_HOST` |
| `new` | curl compose from GitHub, `sed` the `${VARS}`, up, symlink volumes |
| `images/14.0/Dockerfile` | odoo:14.0 + debugpy |

### The core observation

Both repos do the same thing: **render one compose file per instance and bring it up**. They differ only in placeholder syntax (`{instance}` vs `${INSTANCE}`) and which knobs are set — local publishes ports and bind-mounts addons; server sets proxy vhost env and uses named volumes.

That is a compose *overlay*, not a fork. The whole plan follows from this.

---

## 2. Defects found during the audit

| # | Issue | Location |
|---|---|---|
| 1 | `setup` clones branch `server` and copies `manager/nginx` + `manager_api.service` — none exist in any branch | `setup` |
| 2 | `instance-cp` calls `volume-cp` and `instance-rename` — neither script exists | `instance-cp` |
| 3 | `new` curls `github.com/.../tree/master/...` (an HTML page, not raw content) and points at repo `odoo-server`, not `odoo-server-instances` | server `new` |
| 4 | `ports: "8070:8069"` maps host 8070 → container **8069**, but `instance-dev` starts Odoo on container port **8070**. Unreachable. | all templates |
| 5 | `proxy_mode = True` is never set — Odoo behind nginx-proxy generates wrong URLs and logs proxy IPs instead of client IPs | server `odoo.conf` |
| 6 | `list_db = True`, no `admin_passwd`, `POSTGRES_PASSWORD=odoo` — internet-facing database manager, wide open | server stack |
| 7 | `jwilder/nginx-proxy` + `jrcs/letsencrypt-nginx-proxy-companion` are legacy; superseded by `nginxproxy/nginx-proxy` + `nginxproxy/acme-companion` | `nginx-proxy-le.yml` |
| 8 | `docker-compose` v1 (Python) is EOL; the `version:` key and `networks.x.external.name` long syntax are **removed** in Compose v2 | every script + yml |
| 9 | `VIRTUAL_HOST` hardcodes `farma.` / `test.` / `seasons.` subdomains from an old client | `odoo-postgres.yml` |
| 10 | A `backups` volume is declared and mounted; nothing ever writes to it | `odoo-postgres.yml` |
| 11 | `instance-dev-open` uses `wslview` — WSL only | `instance-dev-open` |
| 12 | Six near-identical template directories; one change means editing six files | `templates/` |

---

## 3. Decisions taken

| Decision | Choice | Rationale |
|---|---|---|
| Merge mechanics | **`git subtree`, history preserved** | All 10 commits of `odoo-server-instances` land under `server/`. The old GitHub repo can then be archived. |
| Database hosting | **Container on the same VM** | Keeps the current architecture, no extra cost, one machine to manage. Backup automation is added in Phase 4. |
| Version coverage | **Add 17/18/19, keep 12–16** | Once version is a variable in the base+overlay design, new versions are nearly free; legacy templates stay available for old client modules. |

---

## 4. Target layout

```
odoo-instances/
├── README.md                     # entry point, quickstart for both modes
├── docs/                         # Phase 6 deliverables
├── bin/                          # all instance-* scripts, moved off root
├── templates/
│   ├── _common/                  # shared .vscode, base odoo.conf
│   └── {12.0,14.0,15.0,16.0,17.0,18.0,19.0}/
│       ├── compose.yml           # base: web + db, nothing host-specific
│       ├── compose.dev.yml       # overlay: debugpy, :5678, published ports
│       ├── compose.server.yml    # overlay: VIRTUAL_HOST, restart:always, no published ports
│       ├── config/odoo.conf
│       ├── odoo_debug/Dockerfile
│       └── .env.example
└── server/
    ├── proxy/compose.yml         # nginxproxy/nginx-proxy + acme-companion
    ├── bootstrap/gce-startup.sh  # was user-data, GCE-flavoured
    └── backup/                   # pg_dump + filestore cron
```

Two structural changes carry most of the value:

**a. Drop `sed` templating for Compose-native `.env`.**
Compose already interpolates `${INSTANCE}`, `${ODOO_VERSION}`, `${POSTGRES_VERSION}`, `${DOMAIN}`. `instance-new` writes a `.env` instead of rewriting files in place. The server repo already worked this way. Side benefit: instances stay re-templatable after creation, which they are not today.

**b. Overlays instead of duplicated template directories.**
`docker compose -f compose.yml -f compose.dev.yml`. One base per version; local / dev / server become flags rather than copies. Resolves defect #12 and collapses `15.0` + `15.0-dev` into a single directory.

---

## 5. Phases

### Phase 0 — consolidate what exists (no behaviour change)

- [x] Tag current `master` as `pre-merge` for rollback
- [x] Merge `origin/debug` → `master` (brings 16.0 + the debugpy templates)
- [x] `git subtree add --prefix=server <odoo-server-instances> master`
- [x] Delete `setup` (defect #1) and `instance-cp` (defect #2). `setup` is replaced in Phase 5; `instance-cp` depends on two scripts that were never committed.
- [x] Commit a `.gitignore` for `.vs/` (currently untracked noise)

### Phase 1 — modernize the runtime

- [x] `docker-compose` → `docker compose` across all scripts
- [x] Drop the obsolete `version:` key from every compose file
- [x] `networks.nginx-proxy` → `{external: true}` (Compose v2 syntax)
- [x] Fix the 8070 port mapping (defect #4)
- [x] `nginxproxy/nginx-proxy:1.11.6` + `nginxproxy/acme-companion:2.8.2`, pinned (defect #7)
- [x] Guard `instance-dev-open` for WSL / Linux / macOS (defect #11)

### Phase 2 — restructure

- [ ] `git mv` scripts into `bin/`; the new setup script puts `bin/` on PATH
- [ ] Convert `16.0` to base+overlay as the pilot; verify locally
- [ ] Backport the shape to 15.0 / 14.0 / 12.0
- [ ] Introduce `.env` templating
- [ ] `instance-new INSTANCE VERSION [--profile local|dev|server]`

### Phase 3 — Odoo 17 / 18 / 19

Verified: `odoo:19.0`, `odoo:18.0`, `odoo:17.0` all exist on Docker Hub (19.0 last pushed 2026-08-18).

- [ ] `templates/19.0/`, `18.0/`, `17.0/` from the Phase-2 shape
- [ ] **Pin `postgres:16`.** Odoo 19 raised the minimum from PG 12 to **PG 13**; 15+ is recommended and is required for pgvector. The current `postgres:13.0` pin sits exactly at the floor.
- [ ] **debugpy gotcha:** `odoo:19.0` is built on `ubuntu:noble` / Python 3.12, which enforces PEP 668. The existing `RUN pip3 install debugpy` **fails** with `error: externally-managed-environment`.
      Fix: `RUN pip3 install --break-system-packages debugpy`
- [ ] Modernize `odoo.conf` keys for 16+: `xmlrpc_port` → `http_port`, `longpolling_port` → `gevent_port`
- [ ] `.vscode/launch.json`: `"type": "python"` is deprecated → `"debugpy"`

### Phase 4 — production-worthy server profile

- [ ] `proxy_mode = True` — not optional behind nginx-proxy (defect #5)
- [ ] `list_db = False`, generated `admin_passwd`, generated DB password into `.env` (defect #6)
- [ ] `workers = 2*vCPU+1`, `limit_time_real`, `max_cron_threads` — the current `workers = 0` runs single-threaded
- [ ] Parametrize `VIRTUAL_HOST` from `${DOMAIN}` (defect #9)
- [ ] `server/backup/`: nightly `pg_dump` + filestore tar into the `backups` volume, retention policy, documented restore path (defect #10)

### Phase 5 — GCE bootstrap

- [ ] Rewrite `user-data` → `server/bootstrap/gce-startup.sh`. GCE reads the **`startup-script`** metadata key; `user-data` (cloud-init) only works on some images. Target Ubuntu 24.04 LTS + `startup-script`.
- [ ] Document the surrounding GCP setup:
  - static external IP
  - DNS A record **before** first boot (Let's Encrypt needs resolvable DNS)
  - firewall: 80/443 only; SSH via IAP rather than an open 22
  - `e2-medium` (2 vCPU / 4 GB) minimum for one Odoo + PG
  - 30 GB+ disk, swap file
- [ ] Reconsider the Portainer agent on 9000/9001 — currently started with no firewall story at all

### Phase 6 — documentation

| File | Contents |
|---|---|
| `README.md` | What this is, the two modes, a 5-minute quickstart for each |
| `docs/tools-reference.md` | Every `instance-*` script: synopsis, args, what it touches, exit codes. **Does not exist today in any form.** |
| `docs/local-development.md` | Create instance → scaffold module → attach VS Code debugger → update module |
| `docs/server-deployment.md` | End-to-end GCE runbook, `gcloud compute instances create` through TLS-served Odoo |
| `docs/version-matrix.md` | Odoo ↔ PostgreSQL ↔ Python ↔ base image, per supported version |
| `docs/backup-restore.md` | Backup schedule, restore drill |
| `docs/troubleshooting.md` | Common failures and their causes |

- [ ] Add `--help` to every script and generate `tools-reference.md` from it so the docs cannot drift from the code

### Phase 7 — verification

- [ ] Local: create a 19.0 dev instance, scaffold a module, hit a breakpoint
- [ ] Server: deploy 19.0 to a throwaway GCE VM on a test subdomain
- [ ] Confirm TLS issuance, confirm `proxy_mode` (client IPs in logs, correct generated URLs)
- [ ] Run a full backup + restore cycle
- [ ] Destroy the test VM

---

## 6. Ordering note

Phases 0–2 are refactors with no behaviour change and can be done in one pass.

Phase 3 technically only depends on Phase 0. If Odoo 19 on a VPS is needed urgently, the order 0 → 3 → 4 → 5 works — at the cost of adding a seventh duplicated template directory that Phase 2 then has to undo.

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| Phase 0 changes the shape of `master` history | `pre-merge` tag; a subtree merge is an ordinary commit and is revertable |
| Existing `~/dockers/*` instances predate the `.env` change | Phase 2 ships a one-shot `instance-migrate` that converts a sed-templated instance to `.env`; old instances keep working until it is run |
| Let's Encrypt rate limits during Phase 7 testing | Use the staging ACME endpoint on the throwaway VM |
| PG 13 → 16 is not an in-place upgrade | Only new instances default to 16; existing instances keep their pin. Document the `pg_upgrade` / dump-restore path. |

# Migration Plan: unify `odoo-server-instances` into `odoo-instances`

Status: **in progress** — Phase 6 complete, awaiting go-ahead on Phase 7 (final phase)
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
| 13 | `postgres:13.0` is not a real image tag — PostgreSQL dropped the `.0` suffix after v10. Every `db` container in this repo would have failed to pull. Found during Phase 3. | every template's `POSTGRES_VERSION` default + `server/user-data` |

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
├── setup                         # local dev setup: checks docker, puts bin/ on PATH
├── bin/                          # all instance-* scripts + mkmod, moved off root
├── templates/
│   ├── _common/                  # everything version-independent (was
│   │   │                         # identical across every version already)
│   │   ├── compose.yml           # base: web + db, nothing host-specific
│   │   ├── compose.local.yml     # overlay: published ports, no debugger
│   │   ├── compose.dev.yml       # overlay: debugpy image, :5678, published ports
│   │   ├── compose.server.yml    # overlay: VIRTUAL_HOST, restart:always, named
│   │   │                         # addons volume instead of a bind mount, no
│   │   │                         # published ports
│   │   ├── config/odoo.conf
│   │   ├── .vscode/
│   │   └── .env.example
│   └── {12.0,14.0,15.0,16.0,17.0,18.0,19.0}/
│       └── odoo_debug/Dockerfile # the only thing that's actually version-specific
└── server/
    ├── proxy/compose.yml         # nginxproxy/nginx-proxy + acme-companion
    ├── bootstrap/gce-startup.sh  # was user-data, GCE-flavoured
    └── backup/                   # pg_dump + filestore cron
```

`instance-new` copies `templates/_common/config` and (for local/dev profiles)
`templates/_common/.vscode` into the instance directory, plus
`templates/<version>/odoo_debug` for the dev profile, and writes the real
`.env`. `instance-up`/`instance-down`/`instance-rm` read that `.env`'s
`COMPOSE_PROFILE` and invoke `docker compose -f templates/_common/compose.yml
-f templates/_common/compose.$PROFILE.yml --project-directory
<instance-dir>`.

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

- [x] `git mv` scripts into `bin/`; the new setup script puts `bin/` on PATH
- [x] Convert all versions to base+overlay (not just 16.0 — the `.vscode`/`odoo.conf`/compose content was identical everywhere, so there was no reason to pilot one and backport); verified with `docker compose config`
- [x] Introduce `.env` templating
- [x] `instance-new INSTANCE VERSION [--profile local|dev|server]`

### Phase 3 — Odoo 17 / 18 / 19

Verified: `odoo:19.0`, `odoo:18.0`, `odoo:17.0` all exist on Docker Hub (19.0 last pushed 2026-08-18).

- [x] `templates/{17.0,18.0,19.0}/odoo_debug/Dockerfile` (the base+overlay design from Phase 2 means that's the only version-specific file needed)
- [x] **Pin `postgres:16`** for 17.0/18.0/19.0 via `templates/<version>/postgres-version.default`. Odoo 19 raised the minimum from PG 12 to **PG 13**; 15+ is recommended and is required for pgvector.
      While implementing this, found that the pre-existing `postgres:13.0` pin wasn't just minimal — **it doesn't exist as a tag at all** (Postgres dropped the `.0` suffix after v10; valid tags are `13`, `13.23`, `16`, `16.13`, ...). Every instance in this repo, local or server, would have failed to pull its db image. Fixed the default to `13` for 12.0-16.0 too, and fixed the same literal in `server/user-data`.
- [x] **debugpy gotcha**, checked per-version rather than assumed: `odoo:18.0` and `odoo:19.0` are both built on `ubuntu:noble` / Python 3.12 (PEP 668 enforced) — their Dockerfiles use `RUN pip3 install --break-system-packages debugpy`. `odoo:17.0` is still `ubuntu:jammy`, so it keeps the plain `pip3 install debugpy` like 12.0-16.0.
- [x] Modernize `odoo.conf` keys, verified against Odoo's own docs rather than assumed: `xmlrpc_port`/`xmlrpc_interface` → `http_port`/`http_interface` (renamed in Odoo **11**, so this was already stale advice for the whole 12.0-19.0 range, not just 16+) and `longpolling_port` → `gevent_port` (renamed in **16.0** specifically — left a one-line compat note in the shared file since that split is real)
- [x] `.vscode/launch.json`: `"type": "python"` → `"debugpy"` (confirmed deprecated by Microsoft; the old type still works today but warns)

### Phase 4 — production-worthy server profile

- [x] `proxy_mode = True` — not optional behind nginx-proxy (defect #5)
- [x] `list_db = False`, generated `admin_passwd`, generated `DB_PASSWORD` into `.env` (defect #6). Two independent secrets, generated by `instance-new` for the server profile only: `DB_PASSWORD` wired to both containers via the odoo image entrypoint's `HOST`/`USER`/`PASSWORD` env vars (deliberately not written into `odoo.conf`, which would silently override it), `admin_passwd` appended straight into the instance's `odoo.conf` (no `${VAR}` interpolation in Odoo config files) and printed once at creation time.
- [x] `workers = 2*vCPU+1` (computed via `nproc` on the machine `instance-new` actually runs on), `limit_time_cpu`/`limit_time_real`, `max_cron_threads` — the previous unset `workers = 0` ran single-threaded and never enforced request time limits at all
- [x] Parametrize `VIRTUAL_HOST` from `${DOMAIN}` (defect #9) — turned out to already be fixed as a side effect of the Phase 2 rewrite; `templates/_common/compose.server.yml` never carried the old hardcoded `farma.`/`test.`/`seasons.` subdomains that only existed in the now-superseded `server/odoo-postgres.yml`
- [x] `server/backup/`: `backup-instance.sh` (`pg_dumpall` + filestore tar), `backup-all.sh` (auto-discovers server-profile instances), `prune-backups.sh` (retention), `restore-instance.sh`, README with the crontab lines (defect #10). Removed the `backups` named volume from `compose.server.yml` instead of finally using it — the scripts write host-side via `docker exec ... > file`, so nothing needed it. The full narrative runbook is Phase 6's job.

### Phase 5 — GCE bootstrap

- [x] Rewrite `user-data` → `server/bootstrap/gce-startup.sh`, targeting the **`startup-script`** metadata key on Ubuntu 24.04 LTS. GCE re-runs `startup-script` on *every* boot (unlike cloud-init's `user-data`, which normally runs once) — every step (apt installs, swap file, `git pull`/clone, `docker compose up -d`, instance creation) is written to be idempotent, not just a one-shot port of the old script. Calls `bin/instance-new --profile server` directly instead of the old curl-and-sed flow, and reads per-instance config from GCE metadata instead of a hardcoded client domain/instance name.
- [x] Document the surrounding GCP setup (`server/bootstrap/README.md`):
  - static external IP
  - DNS A record **before** first boot (Let's Encrypt needs resolvable DNS)
  - firewall: 80/443 only; SSH via IAP rather than an open 22 — IAP source range `35.235.240.0/20` verified against Google's own docs, plus a reminder to delete the default `default-allow-ssh` rule most GCP projects ship with (it undoes the IAP-only restriction otherwise)
  - `e2-medium` (2 vCPU / 4 GB) minimum for one Odoo + PG, 30 GB+ disk
  - 2 GB swap file, created idempotently by the script itself
- [x] Reconsider the Portainer agent on 9000/9001 (no firewall story at all): dropped it from the default script entirely rather than trying to patch around the exposure inside the boot script (firewall rules are a VPC-level concern the script can't fix on its own); documented as an explicit, separately-firewalled opt-in instead

Also retired `server/new`, `server/odoo-postgres.yml`, `server/user-data`, and `server/images/` (fully superseded by `gce-startup.sh` calling `instance-new` directly), and relocated `nginx-proxy-le.yml` to `server/proxy/compose.yml` per the target layout, with its `client_max_body_size.conf` now a tracked file instead of something the boot script `echo`'d into existence.

### Phase 6 — documentation

| File | Contents |
|---|---|
| `README.md` | ✅ What this is, the two modes, a 5-minute quickstart for each |
| `docs/tools-reference.md` | ✅ Generated from every script's own `--help` — see below |
| `docs/local-development.md` | ✅ Create instance → scaffold module → attach VS Code debugger → update module |
| `docs/server-deployment.md` | ✅ End-to-end GCE runbook, `gcloud compute instances create` through TLS-served Odoo |
| `docs/version-matrix.md` | ✅ Odoo ↔ PostgreSQL ↔ base image, per supported version — states what was directly verified vs. corroborated-not-reverified rather than presenting both the same way |
| `docs/backup-restore.md` | ✅ Backup schedule, a runnable restore drill, off-box copy guidance |
| `docs/troubleshooting.md` | ✅ Failures actually hit while building this repo, plus ones that follow from the design |

- [x] Add `--help` to every script (17 total) and generate `tools-reference.md` from it (`bin/_generate-tools-reference.sh`) so the docs cannot drift from the code. Found and fixed two real bugs while doing this, both in code this phase's docs directly describe:
  - `instance-new`'s argument parser infinite-looped on an unknown flag (a `case` branch with no `shift`/`exit`) — confirmed with `timeout` before and after the fix
  - `templates/_common/.vscode/tasks.json` still called the removed `docker-compose` v1 binary (missed in Phase 1 — the grep there only checked scripts, not this JSON file) **and** its bare `docker-compose up -d` couldn't have found a compose file at all since Phase 2 replaced the per-instance file with the centralized base+overlay scheme — every debugger-attach task in it was non-functional. Rewritten to delegate to `instance-up`/`instance-stop`/`instance-exec-odoo` via `${workspaceFolderBasename}` instead of reimplementing compose invocation in JSON.

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

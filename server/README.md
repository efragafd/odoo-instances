# server/

VPS deployment tooling — the counterpart to `bin/`/`templates/` (local
development). See `docs/MIGRATION-PLAN.md` for how this fits together.

| Directory | Purpose |
|---|---|
| `bootstrap/` | `gce-startup.sh` — GCE `startup-script` that provisions Docker, the shared reverse proxy, and (optionally) the first Odoo instance. `README.md` has the full `gcloud` setup it expects. |
| `proxy/` | The shared `nginx-proxy` + `acme-companion` stack every server-profile instance sits behind. |
| `backup/` | Per-instance backup/restore/retention scripts. See `README.md` there for the crontab setup. |

A server-profile Odoo instance itself is created the same way as a local
one — `instance-new INSTANCE VERSION --profile server --domain D --contact
E` (see `bin/instance-new`) — it just lands in `templates/_common/
compose.server.yml`'s profile instead of `local`/`dev`.

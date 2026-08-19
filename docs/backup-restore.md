# Backup & restore

The full runbook. `server/backup/README.md` is the short version kept next
to the scripts.

## What's covered

Every `COMPOSE_PROFILE=server` instance found under `~/dockers/*/.env`.
Local/dev instances aren't backed up by this mechanism — they're
disposable by design (`instance-rm` + `instance-new` recreates one from
scratch).

For each server instance, a snapshot is:

```
~/backups/<instance>/<timestamp>/
├── db.sql.gz          # pg_dumpall -U odoo | gzip — every database + role
└── filestore.tar.gz   # tar of /var/lib/odoo/filestore inside the web container
```

`pg_dumpall` rather than `pg_dump` on a specific database name is
deliberate: this repo doesn't assume a fixed database-name convention, and
a cluster dump backs up everything in the instance regardless of what
databases exist inside it.

## Schedule

`gce-startup.sh` installs this crontab automatically (see
`server/backup/README.md` for the exact lines): nightly `backup-all.sh` at
03:00, `prune-backups.sh` (default 14-day retention) at 03:30.

Adjust retention: `RETENTION_DAYS=30 server/backup/prune-backups.sh`, or
edit the crontab line directly (`crontab -e`).

## Restore drill

Do this on a fresh instance, not by overwriting a live one —
`restore-instance.sh` replays `pg_dumpall`'s `CREATE DATABASE`/`CREATE
ROLE` statements, which fails partway through if those already exist.

```bash
# 1. Pick a snapshot
ls ~/backups/myclient/

# 2. Create a fresh instance to restore into (different name, same version)
instance-new myclient-restore-test 19.0 --profile server \
  --domain restore-test.example.com --contact you@example.com

# 3. Restore into it
server/backup/restore-instance.sh myclient-restore-test \
  ~/backups/myclient/20260819T030000Z

# 4. Verify, then decide: promote it (swap DNS/domain), or tear it down
instance-status myclient-restore-test
```

**A restore drill you haven't run is a backup you don't actually have.**
Run one on a real schedule (quarterly is a reasonable floor), not just
once when this repo was set up.

## Off-box copies

Nothing in `server/backup/` leaves the VM. A backup that lives on the same
disk as what it's backing up doesn't survive that disk failing, the VM
being deleted, or a compromised host. Sync `~/backups/` somewhere else on
its own schedule — `rsync` to another machine, or `rclone` to object
storage (GCS, S3, B2, ...). This repo doesn't pick one for you since it
depends on what you already have access to; whatever you choose, make
sure the destination isn't reachable with the same credentials as the VM
itself, or a compromise of one is a compromise of both.

## Restoring after losing the whole VM

1. Recreate the VM (`docs/server-deployment.md`, steps 1-3) — without the
   `odoo-*` metadata this time, so `gce-startup.sh` only provisions Docker
   + the proxy stack and doesn't try to create an instance you're about to
   restore by hand.
2. Copy your off-box backup copies back onto the new VM, under
   `~/backups/`.
3. `instance-new <name> <version> --profile server --domain <domain> --contact <email>`
4. `server/backup/restore-instance.sh <name> ~/backups/<name>/<snapshot>`
5. `instance-up <name>` if it isn't already running.

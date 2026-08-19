# Backups

Operator quick reference. The full runbook (with worked examples) lands in
`docs/backup-restore.md` as part of Phase 6 of `docs/MIGRATION-PLAN.md`.

## What gets backed up

For each server-profile instance (`COMPOSE_PROFILE=server` in its `.env`):

- **Database cluster** — `pg_dumpall`, so every database and role in the
  instance's Postgres container, not just one named database
- **Filestore** — a tar of `/var/lib/odoo/filestore` from the web container
  (attachments, binary fields — not stored in Postgres)

Both land under `$BACKUP_ROOT/<instance>/<timestamp>/` (`$BACKUP_ROOT`
defaults to `~/backups`).

## Scripts

| Script | Purpose |
|---|---|
| `backup-instance.sh INSTANCE` | Back up one instance |
| `backup-all.sh` | Back up every server-profile instance found under `~/dockers` |
| `prune-backups.sh` | Delete snapshots older than `$RETENTION_DAYS` (default 14) |
| `restore-instance.sh INSTANCE SNAPSHOT_DIR` | Restore a snapshot onto a running instance |

## Cron

```
0 3 * * * /path/to/odoo-instances/server/backup/backup-all.sh >> /var/log/odoo-backup.log 2>&1
30 3 * * * /path/to/odoo-instances/server/backup/prune-backups.sh >> /var/log/odoo-backup.log 2>&1
```

Back up nightly at 03:00, prune 30 minutes later once that run has landed.

## Off-box copies

None of these scripts copy backups off the VPS. A single-machine backup is
not a backup — sync `$BACKUP_ROOT` somewhere else (`rsync`, `rclone` to
object storage, etc.) on its own schedule.

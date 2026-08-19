#!/bin/bash
# Restore an instance's database cluster + filestore from a snapshot
# produced by backup-instance.sh.
#
# The instance's containers must be running (this uses `docker exec`), and
# its Postgres cluster should be empty — this replays pg_dumpall's CREATE
# DATABASE/CREATE ROLE statements, so it's meant for restoring onto a
# freshly created instance (instance-new ... --profile server), not for
# overwriting databases that already exist in place. See
# docs/backup-restore.md (Phase 6) for the full runbook.
#
# USAGE: restore-instance.sh INSTANCE SNAPSHOT_DIR
#   SNAPSHOT_DIR is e.g. ~/backups/myinstance/20260819T120000Z
set -e

INSTANCE=$1
SNAPSHOT_DIR=$2

if [ -z "$INSTANCE" ] || [ -z "$SNAPSHOT_DIR" ]; then
    echo "USAGE: $0 INSTANCE SNAPSHOT_DIR" >&2
    exit 1
fi

if [ ! -f "$SNAPSHOT_DIR/db.sql.gz" ]; then
    echo "No db.sql.gz found in $SNAPSHOT_DIR" >&2
    exit 1
fi

echo "[$INSTANCE] restoring database cluster from $SNAPSHOT_DIR/db.sql.gz..."
gunzip -c "$SNAPSHOT_DIR/db.sql.gz" | docker exec -i "${INSTANCE}_db" psql -U odoo -d postgres

if [ -f "$SNAPSHOT_DIR/filestore.tar.gz" ]; then
    echo "[$INSTANCE] restoring filestore from $SNAPSHOT_DIR/filestore.tar.gz..."
    docker exec -i "$INSTANCE" tar -xzf - -C /var/lib/odoo < "$SNAPSHOT_DIR/filestore.tar.gz"
else
    echo "[$INSTANCE] warning: no filestore.tar.gz in snapshot, skipping" >&2
fi

echo "[$INSTANCE] restore complete. Start the instance: instance-up $INSTANCE"

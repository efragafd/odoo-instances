#!/bin/bash
# Back up one server-profile Odoo instance: a full PostgreSQL cluster dump
# (pg_dumpall, so it covers every database in the instance plus roles) and
# a tar of the filestore, written to $BACKUP_ROOT/<instance>/<timestamp>/.
#
# USAGE: backup-instance.sh INSTANCE
#   BACKUP_ROOT   defaults to $HOME/backups
set -e

INSTANCE=$1

if [ -z "$INSTANCE" ]; then
    echo "USAGE: $0 INSTANCE" >&2
    exit 1
fi

BACKUP_ROOT=${BACKUP_ROOT:-$HOME/backups}
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
DEST="$BACKUP_ROOT/$INSTANCE/$TIMESTAMP"

mkdir -p "$DEST"

echo "[$INSTANCE] dumping database cluster..."
docker exec "${INSTANCE}_db" pg_dumpall -U odoo | gzip > "$DEST/db.sql.gz"

echo "[$INSTANCE] archiving filestore..."
if ! docker exec "$INSTANCE" tar -czf - -C /var/lib/odoo filestore > "$DEST/filestore.tar.gz" 2>/dev/null; then
    echo "[$INSTANCE] warning: filestore archive failed or filestore is empty" >&2
    rm -f "$DEST/filestore.tar.gz"
fi

echo "[$INSTANCE] backup written to $DEST"

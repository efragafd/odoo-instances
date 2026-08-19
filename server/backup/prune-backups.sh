#!/bin/bash
# Deletes backup snapshots older than $RETENTION_DAYS for every instance
# under $BACKUP_ROOT. A snapshot is $BACKUP_ROOT/<instance>/<timestamp>/.
#
#   BACKUP_ROOT       defaults to $HOME/backups
#   RETENTION_DAYS    defaults to 14
set -e

BACKUP_ROOT=${BACKUP_ROOT:-$HOME/backups}
RETENTION_DAYS=${RETENTION_DAYS:-14}

if [ ! -d "$BACKUP_ROOT" ]; then
    echo "$BACKUP_ROOT does not exist, nothing to prune" >&2
    exit 0
fi

find "$BACKUP_ROOT" -mindepth 2 -maxdepth 2 -type d -mtime "+$RETENTION_DAYS" -print -exec rm -rf {} \;

#!/bin/bash
# Runs backup-instance.sh for every server-profile instance under
# $HOME/dockers. Intended to run from cron — see README.md.
set -e

SCRIPTPATH=$(cd "$(dirname "$0")" && pwd)

for env_file in "$HOME"/dockers/*/.env; do
    [ -f "$env_file" ] || continue

    instance_dir=$(dirname "$env_file")
    instance=$(basename "$instance_dir")
    profile=$(grep -E '^COMPOSE_PROFILE=' "$env_file" | cut -d= -f2)

    [ "$profile" = "server" ] || continue

    "$SCRIPTPATH/backup-instance.sh" "$instance"
done

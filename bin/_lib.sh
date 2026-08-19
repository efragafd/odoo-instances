# Shared helpers for instance-* scripts. Not a standalone entrypoint —
# sourced, not executed.

repo_root() {
    local lib_dir
    lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    dirname "$lib_dir"
}

# Reads <instance>/.env and populates the COMPOSE_ARGS array with the
# -f/--env-file/--project-directory flags needed to operate on it, based on
# the profile (local/dev/server) it was created with.
instance_compose_args() {
    local instance=$1
    local instance_dir="$HOME/dockers/$instance"
    local root
    root=$(repo_root)

    if [ ! -f "$instance_dir/.env" ]; then
        echo "Instance '$instance' has no .env file — was it created with instance-new?" >&2
        return 1
    fi

    set -a
    # shellcheck disable=SC1091
    source "$instance_dir/.env"
    set +a

    local profile=${COMPOSE_PROFILE:-local}

    if [ ! -f "$root/templates/_common/compose.$profile.yml" ]; then
        echo "Instance '$instance' has an unknown COMPOSE_PROFILE '$profile' in its .env" >&2
        return 1
    fi

    COMPOSE_ARGS=(
        --env-file "$instance_dir/.env"
        --project-directory "$instance_dir"
        -f "$root/templates/_common/compose.yml"
        -f "$root/templates/_common/compose.$profile.yml"
    )
}

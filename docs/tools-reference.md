# Tools reference

Generated from each script's own `--help` output by
`bin/_generate-tools-reference.sh` — do not hand-edit; run that
script again after changing a script's `--help` text.

`setup` is at the repo root; everything else is on `PATH` after
running it (see `README.md`).

## `setup`

```
USAGE: setup

  One-time local setup: checks for docker + the compose plugin, and adds
  bin/ to PATH via ~/.profile. Safe to re-run.
```

## `instance-attach`

```
USAGE: instance-attach INSTANCE

  Attach an interactive root shell inside INSTANCE's web container.
```

## `instance-attach-sql`

```
USAGE: instance-attach-sql INSTANCE DB

  Open an interactive psql shell against database DB on INSTANCE's db
  container, as the odoo role.
```

## `instance-code`

```
USAGE: instance-code INSTANCE

  Open INSTANCE's directory (~/dockers/INSTANCE) in VS Code.
```

## `instance-code-m`

```
USAGE: instance-code-m INSTANCE MODULE

  Open one module's directory (~/dockers/INSTANCE/addons/MODULE) in VS Code.
```

## `instance-dev`

```
USAGE: instance-dev INSTANCE [ODOO_ARGS...]

  Run a second, foreground Odoo process inside INSTANCE's web container on
  port 8070 (published by the "dev" and "local" profiles), separate from
  the container's main process on 8069. Extra ODOO_ARGS are passed through
  — e.g. -u mymodule to update a module while watching the output.
```

## `instance-dev-open`

```
USAGE: instance-dev-open INSTANCE

  Open http://localhost:8069 (INSTANCE's web UI) in the default browser.
  Assumes the instance's ports are published on localhost — true for the
  "local" and "dev" profiles, not "server".
```

## `instance-down`

```
USAGE: instance-down INSTANCE

  Stop and remove INSTANCE's containers (docker compose down). Volumes are
  kept — use instance-rm to delete an instance entirely.
```

## `instance-exec`

```
USAGE: instance-exec INSTANCE CMD [ARGS...]

  Run CMD interactively inside INSTANCE's web container (as the odoo user).
```

## `instance-exec-odoo`

```
USAGE: instance-exec-odoo INSTANCE DB [ODOO_ARGS...]

  Run a one-shot Odoo command inside INSTANCE's web container against
  database DB, with --no-http --stop-after-init. Extra ODOO_ARGS are
  passed through — e.g. -i mymodule or -u mymodule to install/update.
```

## `instance-new`

```
USAGE: instance-new INSTANCE VERSION [options]

  Create a new Odoo instance under ~/dockers/INSTANCE and bring it up.
  VERSION must have a directory under templates/, e.g. 19.0.

  --profile local|dev|server   default: dev
                                  local   published ports, no debugger
                                  dev     local + debugpy attach on :5678
                                  server  restart=always, named addons
                                          volume, nginx-proxy vhost
  --postgres-version VERSION   default: the version in
                                templates/VERSION/postgres-version.default
                                (falls back to 13 if that file is absent)
  --domain DOMAIN               required for --profile server
  --contact EMAIL                required for --profile server
```

## `instance-restart`

```
USAGE: instance-restart INSTANCE

  instance-stop followed by instance-up.
```

## `instance-rm`

```
USAGE: instance-rm INSTANCE

  Permanently delete INSTANCE: stops its containers, removes every volume
  it declared (web-data/db-data, plus extra-addons for server instances),
  and deletes ~/dockers/INSTANCE. Not recoverable unless you have a backup
  (see server/backup/ for server-profile instances).
```

## `instance-status`

```
USAGE: instance-status INSTANCE [ANYTHING]

  Print docker ps status for INSTANCE's web container, as one line of
  JSON: {"name": ..., "status": ...}. Pass any second argument (its value
  is ignored — it's a presence check, not a database name) to check the
  db container instead.
```

## `instance-stop`

```
USAGE: instance-stop INSTANCE

  docker stop INSTANCE's web and db containers directly, without removing
  them (unlike instance-down, this doesn't need INSTANCE's .env/profile).
```

## `instance-up`

```
USAGE: instance-up INSTANCE

  Bring up an existing instance (docker compose up -d --build), using the
  profile recorded in its .env. Called automatically by instance-new; use
  this directly after instance-down/instance-stop, or after editing an
  instance's config.
```

## `mkmod`

```
USAGE: mkmod INSTANCE MODULE_NAME

  Scaffold a new Odoo module named MODULE_NAME into INSTANCE's addons/
  (via odoo scaffold), fix its ownership (scaffold runs as root inside the
  container), and copy the instance's .vscode/ into the new module
  directory so a per-module VS Code workspace can be opened with
  instance-code-m.
```


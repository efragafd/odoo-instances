# Local development

End-to-end: create an instance, scaffold a module, attach the VS Code
debugger, update the module.

## 1. Create an instance

```bash
instance-new mymodule-dev 19.0
```

With no `--profile`, this defaults to `dev` — a debugpy-enabled image,
published on `localhost:8069` (Odoo), `:8070` (a second manually-started
Odoo process, see `instance-dev` below), and `:5678` (the debugger).

`~/dockers/mymodule-dev/` now has:

```
addons/       # bind-mounted into the container at /mnt/extra-addons — your code
config/       # odoo.conf, bind-mounted at /etc/odoo
.vscode/      # launch.json (debugpy attach) + tasks.json
odoo_debug/   # the Dockerfile the dev profile built from
.env          # INSTANCE, ODOO_VERSION, POSTGRES_VERSION, COMPOSE_PROFILE=dev
```

Open it: `instance-code mymodule-dev`

## 2. Scaffold a module

```bash
mkmod mymodule-dev my_module
```

Runs `odoo scaffold` inside the container, fixes ownership (scaffold runs
as root), and copies `.vscode/` into the new module directory so it can
also be opened standalone: `instance-code-m mymodule-dev my_module`.

## 3. Attach the debugger

1. In VS Code, open `~/dockers/mymodule-dev` (or the module directory).
2. Run the **"Odoo: Update"** launch config (`.vscode/launch.json`) — it
   runs the `update&restart` task first (module update inside the
   container, then a container restart), then attaches to port 5678.
3. Set breakpoints in your module code under `addons/my_module/`.

The debugger needs the container's main process (the one on 8069) to be
the one running with `-u`/`-d` flags matching what you're debugging — the
`update&restart` task's `docker-compose exec` step in `tasks.json` is
where you fill in `-d <db>` / `-u <module>` (commented placeholders are
there by default).

## 4. Iterate

- **Restart after code changes that need a full reload:**
  `instance-restart mymodule-dev`
- **Update one module without a debugger, from the shell:**
  `instance-exec-odoo mymodule-dev <db> -u my_module`
- **A second foreground Odoo process on :8070** (useful for watching
  update output live, separate from the container's main process):
  `instance-dev mymodule-dev -u my_module`
- **Open the web UI:** `instance-dev-open mymodule-dev`
- **Shell into the container:** `instance-attach mymodule-dev`
- **psql into the database:** `instance-attach-sql mymodule-dev <db>`
- **Check container status:** `instance-status mymodule-dev`

Full flag/argument reference for every tool: `docs/tools-reference.md`.

## Profiles other than `dev`

- **`--profile local`** — same as `dev` but without the debugpy image
  (plain `odoo:<version>`, no `:5678`). Slightly faster to build, no
  debugger.
- **`--profile server`** — see `docs/server-deployment.md`. Not meant for
  local use (no published ports, generated credentials, `restart: always`).

## Cleaning up

- `instance-down mymodule-dev` — stop and remove containers, keep volumes
  (your database and filestore survive)
- `instance-rm mymodule-dev` — stop, remove containers **and volumes**,
  delete `~/dockers/mymodule-dev`. Not recoverable.

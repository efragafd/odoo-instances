# Troubleshooting

Failures actually encountered while building/testing this tooling, plus
ones that follow directly from how it's designed.

## "docker-compose: command not found"

You're missing the Compose v2 plugin, or something (a script, a
`.vscode/tasks.json` you haven't updated) is still calling the removed v1
binary. Everything in this repo uses `docker compose` (a Docker CLI
subcommand, no hyphen) — see `docs/MIGRATION-PLAN.md` Phase 1. Install
`docker-compose-plugin` (Docker Desktop bundles it already).

## Two local instances won't both come up on :8069

They can't — `compose.local.yml`/`compose.dev.yml` both publish a fixed
`8069:8069` (and `8070`/`5678`), so only one instance can be running with
either profile at a time on one machine. `instance-down` the one you're
not using, or stick to one active local instance. There's no dynamic port
allocation in this repo; if you need several running simultaneously,
you'd need to hand-write a per-instance compose override remapping the
published ports — nothing here generates one for you.

## `instance-new` exits 2, "already exists"

The instance directory (`~/dockers/NAME`) is already there. Either use a
different name, or `instance-rm` the old one first if you meant to
recreate it — **`instance-rm` deletes its volumes too**, so only do that
if you don't need what's in it (or you have a backup: `docs/backup-restore.md`).

## The debugger won't attach

- Confirm the instance was created with `--profile dev`, not `local` — the
  `local` profile's image has no debugpy in it at all. Check
  `~/dockers/NAME/.env`'s `COMPOSE_PROFILE`.
- Confirm you actually ran the `update&restart` VS Code task (or otherwise
  restarted the container) after code changes — debugpy attaches to a
  freshly started process.
- The "module update" task's `-d`/`-u` args are commented out by default
  in `.vscode/tasks.json` — uncomment and fill them in for your database
  and module, or the task runs `--stop-after-init` with no db/module and
  does nothing useful.

## Server: locked out of the database manager

`admin_passwd` is generated once by `instance-new --profile server` and
printed to the terminal (or the VM's serial console log, if this ran via
`gce-startup.sh`) at creation time — that's the only time it's shown.
It's saved in `~/dockers/NAME/config/odoo.conf`'s `admin_passwd` line;
`cat`/edit that file directly (as root, or via `instance-attach`) if you've
lost it. There's no separate recovery flow.

## Server: certificate never issues

`acme-companion`'s HTTP-01 challenge needs your domain to resolve to the
VM's IP *and* port 80 to be reachable, at the moment it tries. Check:

```bash
docker logs nginx-proxy-le
```

The most common cause is DNS not having propagated yet, or the A record
being created after the instance already came up — acme-companion retries
on its own schedule, it isn't a one-shot failure, but there's no reason to
wait it out if the actual cause is fixable now. See "1. Reserve a static
IP and point DNS at it" in `docs/server-deployment.md` for the intended
order.

## `nproc`-computed `workers` looks wrong

`instance-new --profile server` computes `workers = 2*nproc+1` from the
CPU count of the machine `instance-new` actually runs on — correct when
run directly on the target VM (the normal flow), but if you ever run
`instance-new` somewhere else and copy the result over, it'll reflect the
wrong machine. Recreate the instance on the actual target, or edit
`workers` in `odoo.conf` by hand.

## Scripts lost their executable bit after editing on Windows

If `git status`/`git diff` shows a script you edited as unexpectedly
non-executable (`100644` instead of `100755` — check with
`git ls-files -s <path>`), this checkout has `core.filemode=false` (common
on Windows), so Git ignores real `chmod` calls entirely. Fix with:

```bash
git update-index --chmod=+x path/to/script
```

## I have instances from before this repo's Phase 2 restructure

Older instances (created before `instance-new` started writing a real
`.env` and using the base+overlay compose files — see
`docs/MIGRATION-PLAN.md` Phase 2) don't have a `.env` at all, and
`instance-up`/`instance-down`/`instance-rm` will refuse to operate on them
("has no .env file — was it created with instance-new?"). There's no
automatic migration for these; recreate the instance with the current
`instance-new` (your addons/ and database survive independently as long
as you don't delete the old instance's volumes — copy `addons/` over by
hand, and either restore into the new instance from a backup or point it
at the same named Postgres volume manually).

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

## `docker exec`/`instance-exec-odoo`/`mkmod`/`instance-status` fail or return nothing, only on Windows

Git Bash's MSYS layer rewrites any argument starting with `/` into a
Windows path before handing it to a native `.exe` — so `/usr/bin/odoo`
(meant as a path *inside the container*) becomes something like
`C:/Program Files/Git/usr/bin/odoo`, and `docker exec` fails with `exec:
"C:/Program Files/Git/usr/bin/odoo": stat ...: no such file or directory`.
The same thing silently empties out `instance-status`'s `--filter
name=^/...$` (no error, just no output). These scripts already prefix the
affected `docker` calls with `MSYS_NO_PATHCONV=1` to disable that
rewriting — if you hit this anyway (e.g. running a `docker exec ... /abs/path`
command directly, or through `instance-exec` with your own leading-slash
command), prefix it the same way. Confirmed by actually hitting both
failure modes against a real instance during Phase 7 verification, not
theoretical.

## `mkmod`/anything using `docker exec -it` fails with "the input device is not a TTY"

`-it` needs a real interactive terminal. This is expected in a script
piped through something else (CI, an editor's non-interactive terminal,
this repo's own AI-assisted development sessions) — run it from an actual
terminal window instead. On Windows, if it still complains inside a real
terminal, try prefixing with `winpty` (a Git Bash / MSYS quirk with
allocating TTYs for non-MSYS binaries like `docker.exe`).

## `mkmod` used to abort after a successful scaffold, only on Windows

Fixed, but worth knowing why if you're on an older checkout: `mkmod` used
a hard `sudo chown`/`sudo cp` with `set -e`. On Linux/macOS this is
usually needed (scaffold runs as container-root, which leaves root-owned
files on the host bind mount). On Windows, Docker Desktop's file-sharing
layer already presents them as your own user — no `sudo` needed — but
Windows 11's built-in `sudo.exe` exists and is disabled by default, so
calling it exits non-zero anyway, and `set -e` aborted the whole script
right after the module had already been scaffolded successfully. Current
`mkmod` tries without `sudo` first and treats either step failing as a
warning, not a fatal error — confirmed by running it against a real
instance on this exact platform.

## Server: `instance-*` says "has no .env file", but the instance is clearly running

You're running it as your own SSH user. `gce-startup.sh` runs as **root**,
and `instance-new` puts instances in `$HOME/dockers` — so on a GCE VM they
live in `/root/dockers`, not `/home/you/dockers`. Same reason plain
`docker ps` fails: only root is in the `docker` group on a fresh VM.

```bash
sudo -i
```

Then `instance-status`, `instance-up`, etc. work normally (`bin/` is on
PATH via `/etc/profile.d/odoo-instances.sh`, written by the bootstrap).

## Server: the VM booted but nothing is running at all

Check the serial console (`gcloud compute instances get-serial-port-output
VM --zone=ZONE`) for `FATAL: could not clone`. The bootstrap clones this
repo over HTTPS with no credentials, so it only works if the repo is
**public**. If it's private, the clone fails and everything downstream —
proxy stack, instance creation, backup cron — never runs. Either make the
repo public, or give the VM a read-only deploy key and switch `REPO_URL`
in `gce-startup.sh` to an SSH URL.

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

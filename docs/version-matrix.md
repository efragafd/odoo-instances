# Version matrix

What each supported Odoo version actually runs on, and the two things that
change per-version behavior: the debugpy install flag, and the PostgreSQL
floor.

| Odoo | `templates/<v>/` | Base image (odoo:X) | `pip3 install debugpy` needs `--break-system-packages`? | Postgres floor (Odoo's own minimum) | `postgres-version.default` here |
|---|---|---|---|---|---|
| 12.0 | ✅ | Debian (Buster-era) | No | ~12 (long-standing floor; not independently re-verified for this specific version) | 13 |
| 14.0 | ✅ | Debian (Buster/Bullseye-era) | No | ~12 | 13 |
| 15.0 | ✅ | Debian Bullseye | No | ~12 | 13 |
| 16.0 | ✅ | Debian Bullseye | No | ~12 | 13 |
| 17.0 | ✅ | `ubuntu:jammy` (22.04) | No | 12 | 16 |
| 18.0 | ✅ | `ubuntu:noble` (24.04) | **Yes** | 12 | 16 |
| 19.0 | ✅ | `ubuntu:noble` (24.04) | **Yes** | **13** (raised from 12; 15+ recommended, required for pgvector) | 16 |

## How to read this

- **Base image** for 17.0/18.0/19.0 was checked directly against
  `odoo/docker`'s own Dockerfiles (Phase 3 of `docs/MIGRATION-PLAN.md`).
  12.0-16.0 predate what's kept in that repo's current tree — those rows
  are corroborated from multiple secondary sources, not a direct Dockerfile
  read, hence the softer wording.
- **The `--break-system-packages` split is the load-bearing fact here.**
  It follows from PEP 668 enforcement, which landed in Debian 12
  (Bookworm) and Ubuntu 23.04+ — both `ubuntu:jammy` (17.0) and every
  Debian release 12.0-16.0 ran on predate that entirely, so they don't
  need it regardless of the exact point release. `ubuntu:noble` (18.0,
  19.0) does. This is why `templates/18.0/odoo_debug/Dockerfile` and
  `templates/19.0/odoo_debug/Dockerfile` differ from the other five.
- **`postgres-version.default`** is what `instance-new` picks when you
  don't pass `--postgres-version` — see `templates/<version>/postgres-version.default`.
  It's a *default*, not a ceiling: Postgres is generally forward-compatible
  within Odoo's supported range, so pointing an older Odoo version at a
  newer Postgres (e.g. `--postgres-version 16` on Odoo 15) is usually fine.
  Going *below* the floor in the table isn't.
- **`postgres:13.0` doesn't exist as a tag** — see defect #13 in
  `docs/MIGRATION-PLAN.md`. Valid tags look like `13`, `13.23`, `16`,
  `16.13`. `postgres-version.default` files always use the bare-major form.

## Adding a new version

1. `mkdir -p templates/<version>/odoo_debug`
2. Check that version's actual base image
   (`https://raw.githubusercontent.com/odoo/docker/master/<version>/Dockerfile`,
   or Docker Hub if it's aged out of that repo's tree) — don't assume it
   matches the previous version.
3. Write `odoo_debug/Dockerfile` from an existing one, adjusting the `FROM`
   tag and the pip install line if the base image enforces PEP 668.
4. Write `postgres-version.default` — check that version's own minimum
   (its `administration/on_premise/deploy.html` docs page) rather than
   copying the previous entry.
5. `bash bin/_generate-tools-reference.sh` if you touched anything with a
   `--help` block; update this table.

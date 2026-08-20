#!/bin/bash
# GCE startup-script: provisions Docker and the shared nginx-proxy +
# acme-companion stack, and — if this VM's metadata names one — creates the
# first Odoo server instance.
#
# GCE re-runs the startup-script on every boot, not just the first one, so
# every step here has to be safe to repeat.
#
# Set as this VM's startup-script metadata:
#   gcloud compute instances create ... \
#     --metadata-from-file startup-script=server/bootstrap/gce-startup.sh
#
# Optional per-instance metadata (instance creation is skipped entirely if
# odoo-instance is unset):
#   odoo-instance   instance name
#   odoo-domain     domain the instance answers on — its DNS A record must
#                   already resolve to this VM before first boot, or
#                   acme-companion's certificate request will fail
#   odoo-version    Odoo version, e.g. 19.0 (default: 19.0)
#   odoo-contact    email address for Let's Encrypt expiry notices
#
# See server/bootstrap/README.md for the full gcloud setup this expects
# (static IP, DNS, firewall rules, machine sizing).

set -e

REPO_DIR=/opt/odoo-instances
REPO_URL='https://github.com/efragafd/odoo-instances'

metadata() {
    curl -sf -H "Metadata-Flavor: Google" \
        "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1" 2>/dev/null || true
}

# --- base packages -----------------------------------------------------

apt-get update -y
# docker-compose-v2 is the Ubuntu/Debian package that ships the Compose v2
# CLI plugin, and it depends on docker.io — which is what we install here.
# NOT docker-compose-plugin: that name only exists in Docker's own APT
# repository, which this script deliberately doesn't add, so asking for it
# fails with "Unable to locate package".
apt-get install -y --no-install-recommends \
    vim \
    git \
    docker.io \
    docker-compose-v2

systemctl enable --now docker

# Everything below shells out to `docker compose`. Verify it actually
# resolves before continuing, so a packaging problem surfaces here with an
# explanation instead of as a confusing failure three steps later.
if ! docker compose version >/dev/null 2>&1; then
    echo "FATAL: 'docker compose' is not available after installing docker-compose-v2." >&2
    echo "Check that the 'universe' component is enabled for this image, or" >&2
    echo "install Compose v2 by another route before re-running." >&2
    exit 1
fi

# --- swap ----------------------------------------------------------------
# A safety margin on small VMs (e.g. e2-medium's 4 GB) running Odoo + Postgres
# together. 2G is a starting point, not a sizing recommendation — see
# server/bootstrap/README.md.

if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
elif ! swapon --show=NAME --noheadings | grep -qx /swapfile; then
    swapon /swapfile
fi

# --- this repo -----------------------------------------------------------

if [ -d "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" pull --ff-only
elif ! git clone --depth 1 "$REPO_URL" "$REPO_DIR"; then
    # The VM has no GitHub credentials, so this only works if $REPO_URL is
    # public. Fail loudly here rather than letting `set -e` abort with no
    # explanation — everything below depends on the clone having worked.
    echo "FATAL: could not clone $REPO_URL" >&2
    echo "The VM has no GitHub credentials. Either make the repository" >&2
    echo "public, or give this VM a read-only deploy key and use an SSH" >&2
    echo "clone URL. Nothing else in this script can run without it." >&2
    exit 1
fi

# Put bin/ on PATH for every login shell. Server instances live in root's
# home (this script runs as root, and instance-new uses $HOME), so instance
# management on this box means `sudo -i` first — see the closing message.
cat > /etc/profile.d/odoo-instances.sh <<PROFILE
export PATH="\$PATH:$REPO_DIR/bin"
PROFILE
chmod 644 /etc/profile.d/odoo-instances.sh

# --- shared reverse proxy --------------------------------------------------

docker network create nginx-proxy 2>/dev/null || true
docker compose -f "$REPO_DIR/server/proxy/compose.yml" \
    --project-directory "$REPO_DIR/server/proxy" -p nginx-proxy up -d

# --- first instance (optional, metadata-driven) -----------------------------

ODOO_INSTANCE=$(metadata odoo-instance)

if [ -n "$ODOO_INSTANCE" ] && [ ! -d "$HOME/dockers/$ODOO_INSTANCE" ]; then
    ODOO_DOMAIN=$(metadata odoo-domain)
    ODOO_CONTACT=$(metadata odoo-contact)
    ODOO_VERSION=$(metadata odoo-version)
    ODOO_VERSION=${ODOO_VERSION:-19.0}

    if [ -z "$ODOO_DOMAIN" ] || [ -z "$ODOO_CONTACT" ]; then
        echo "odoo-instance metadata is set but odoo-domain/odoo-contact are missing — skipping instance creation" >&2
    else
        "$REPO_DIR/bin/instance-new" "$ODOO_INSTANCE" "$ODOO_VERSION" \
            --profile server --domain "$ODOO_DOMAIN" --contact "$ODOO_CONTACT"
    fi
fi

# --- backups ---------------------------------------------------------------

BACKUP_ALL="$REPO_DIR/server/backup/backup-all.sh"
PRUNE="$REPO_DIR/server/backup/prune-backups.sh"

if ! crontab -l 2>/dev/null | grep -qF "$BACKUP_ALL"; then
    { crontab -l 2>/dev/null; \
      echo "0 3 * * * $BACKUP_ALL >> /var/log/odoo-backup.log 2>&1"; \
      echo "30 3 * * * $PRUNE >> /var/log/odoo-backup.log 2>&1"; \
    } | crontab -
fi

# --- how to actually operate this box ---------------------------------------
# This script runs as root, so instances live in /root/dockers and only root
# is in the docker group. Say so explicitly in the serial console output
# rather than letting the operator discover it by hitting errors.

cat <<'DONE'

=============================================================
 odoo-instances bootstrap finished.

 Manage this box as ROOT — instances live in /root/dockers,
 and docker access is root-only on a fresh GCE VM:

     sudo -i
     instance-status <instance>
     instance-up / instance-down / instance-new ...

 (bin/ is on PATH via /etc/profile.d/odoo-instances.sh.)

 Running instance-* as your own SSH user will report
 "has no .env file" — that is this, not a broken instance.
=============================================================

DONE

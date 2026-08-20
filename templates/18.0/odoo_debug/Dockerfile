FROM odoo:18.0 as base

# >>>>>>> DEBUGGER MODE >>>>>>>>>>>>>
FROM base AS debug
# odoo:18.0 is built on ubuntu:noble (Python 3.12), which enforces PEP 668 —
# a plain `pip3 install` fails with "externally-managed-environment".
# Must install as root: the odoo user can't write system site-packages, so
# pip falls back to a --user install under $HOME (/var/lib/odoo) — which
# compose.yml mounts as a volume, shadowing the package at container start.
USER root
RUN pip3 install --break-system-packages debugpy
USER odoo

CMD python3 -m debugpy --listen 0.0.0.0:5678 /usr/bin/odoo --db_user=odoo --db_host=db --db_password=odoo

# >>>>>>> PRODUCTION MODE >>>>>>>>>>>

FROM odoo:12.0 as base

# >>>>>>> DEBUGGER MODE >>>>>>>>>>>>>
FROM base AS debug
# odoo's default user can't write system site-packages; installing as root
# avoids the --user fallback, which would land under $HOME (/var/lib/odoo)
# — a path compose.yml mounts as a volume, shadowing the package at
# container start.
USER root
RUN pip3 install debugpy
USER odoo

CMD python3 -m debugpy --listen 0.0.0.0:5678 /usr/bin/odoo --db_user=odoo --db_host=db --db_password=odoo

# >>>>>>> PRODUCTION MODE >>>>>>>>>>>

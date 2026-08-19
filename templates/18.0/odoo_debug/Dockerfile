FROM odoo:18.0 as base

# >>>>>>> DEBUGGER MODE >>>>>>>>>>>>>
FROM base AS debug
# odoo:18.0 is built on ubuntu:noble (Python 3.12), which enforces PEP 668 —
# a plain `pip3 install` fails with "externally-managed-environment".
RUN pip3 install --break-system-packages debugpy

CMD python3 -m debugpy --listen 0.0.0.0:5678 /usr/bin/odoo --db_user=odoo --db_host=db --db_password=odoo

# >>>>>>> PRODUCTION MODE >>>>>>>>>>>

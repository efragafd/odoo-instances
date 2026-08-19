FROM odoo:14.0 as base

# >>>>>>> DEBUGGER MODE >>>>>>>>>>>>>
FROM base AS debug
RUN pip3 install debugpy

CMD python3 -m debugpy --listen 0.0.0.0:5678 /usr/bin/odoo --db_user=odoo --db_host=db --db_password=odoo

# >>>>>>> PRODUCTION MODE >>>>>>>>>>>

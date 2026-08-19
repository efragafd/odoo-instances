FROM odoo:14.0
USER root

RUN pip3 install wheel

RUN pip3 install debugpy

USER odoo

CMD [ "python3", "-m", "debugpy", "--listen", "0.0.0.0:5678", "/usr/bin/odoo", "--db_user=odoo", "--db_host=db", "--db_password=odoo"]

FROM planitar/postgresql

USER root

RUN apt-get install -y nginx nginx-extras curl supervisor && \
    service nginx stop && apt-get clean

# Nginx
ADD nginx/default /etc/nginx/sites-available/default
ADD static/ /src/html/static

# Postgres
RUN sed -e "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" \
        -i /etc/postgresql/9.3/main/postgresql.conf && \
    sed -e "/^local *all *postgres *peer/a host iguidedb view_api 127.0.0.1/32 trust" \
        -i /etc/postgresql/9.3/main/pg_hba.conf
ADD postgres/config.sql /src/sql/config.sql
RUN service postgresql start && \
    su postgres -c "psql -f /src/sql/config.sql" && \
    service postgresql stop

# App
ADD bin/app /src/app

# s3cmd
RUN apt-get install -y python-setuptools && easy_install pip
RUN pip install s3cmd python-dateutil

EXPOSE 80

ADD run.sh /src/run.sh
CMD /src/run.sh

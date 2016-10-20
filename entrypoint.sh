#!/bin/bash
set -e

ARCHIVE_HOME="/var/www/html"

### auto-configure database from environment-variables

DB_DRIVER=pgsql
DB_HOST=postgres
: ${DB_PORT:='5432'}
: ${DB_NAME:='postgres'}
: ${DB_USER:='postgres'}
: ${DB_PASS:='postgres'}

export DB_DRIVER DB_HOST DB_PORT DB_NAME DB_USER DB_PASS
echo -e "# Database configuration\n
export DB_DRIVER=${DB_DRIVER} DB_HOST=${DB_HOST} DB_PORT=${DB_PORT} DB_NAME=${DB_NAME} DB_USER=${DB_USER} DB_PASS=${DB_PASS}" >> /etc/profile
echo -e "# Database configuration\n
export DB_DRIVER=${DB_DRIVER} DB_HOST=${DB_HOST} DB_PORT=${DB_PORT} DB_NAME=${DB_NAME} DB_USER=${DB_USER} DB_PASS=${DB_PASS}" >> /etc/bash.bashrc

export ARCHIVE_HTTP_HOST ARCHIVE_HTTP_ROOT ARCHIVE_TITLE ARCHIVE_FTP ARCHIVE_EXT_FTP
echo -e "# archive config\n
export ARCHIVE_HTTP_HOST=${ARCHIVE_HTTP_HOST} ARCHIVE_HTTP_ROOT=${ARCHIVE_HTTP_ROOT} ARCHIVE_TITLE=${ARCHIVE_TITLE} ARCHIVE_FTP=${ARCHIVE_FTP} ARCHIVE_EXT_FTP=${ARCHIVE_EXT_FTP}" >> /etc/profile
echo -e "# archive config\n
export ARCHIVE_HTTP_HOST=${ARCHIVE_HTTP_HOST} ARCHIVE_HTTP_ROOT=${ARCHIVE_HTTP_ROOT} ARCHIVE_TITLE=${ARCHIVE_TITLE} ARCHIVE_FTP=${ARCHIVE_FTP} ARCHIVE_EXT_FTP=${ARCHIVE_EXT_FTP}" >> /etc/bash.bashrc

###  connect to database

echo
echo "=> Trying to connect to a database using:"
echo "      Database Driver:   $DB_DRIVER"
echo "      Database Host:     $DB_HOST"
echo "      Database Port:     $DB_PORT"
echo "      Database Username: $DB_USER"
echo "      Database Password: $DB_PASS"
echo "      Database Name:     $DB_NAME"
echo

for ((i=0;i<20;i++))
do
    DB_CONNECTABLE=$(PGPASSWORD=$DB_PASS psql -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" -l >/dev/null 2>&1; echo "$?")
	if [[ $DB_CONNECTABLE -eq 0 ]]; then
		break
	fi
    sleep 3
done

if ! [[ $DB_CONNECTABLE -eq 0 ]]; then
	echo "Cannot connect to database"
    exit "${DB_CONNECTABLE}"
fi

# Load postgres schema if not present
if [[ `PGPASSWORD=$DB_PASS psql -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" $DB_NAME -tAc "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'archive_user');"` != "t" ]]
then
    echo "No database content detected, installing the db schema"
    PGPASSWORD=$DB_PASS psql -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" $DB_NAME < $ARCHIVE_HOME/site/sql/archive.v2.sql
fi

for ((i=0;i<20;i++))
do
    ES_CONNECTABLE=$(curl -XGET 'http://elasticsearch:9200/' >/dev/null 2>&1; echo "$?")
	if [[ $ES_CONNECTABLE -eq 0 ]]; then
		break
	fi
    sleep 3
done

if ! [[ $ES_CONNECTABLE -eq 0 ]]; then
	echo "Cannot connect to elasticsearch"
    exit "${ES_CONNECTABLE}"
fi

# Create the elasticsearch index if it doesn't exist yet
curl -XPUT 'http://elasticsearch:9200/archive' 2>&1 > /dev/null

# Write http conf to config file
echo "Updating conf files"
bash -c "sed \"s|__ARCHIVE_HTTP_HOST__|${ARCHIVE_HTTP_HOST}|g\" /var/www/html/site/cfg/archive.cfg.docker_template | sed \"s|__ARCHIVE_HTTP_ROOT__|${ARCHIVE_HTTP_ROOT}|g\" | sed \"s|__ARCHIVE_TITLE__|${ARCHIVE_TITLE}|g\" | sed \"s|__ARCHIVE_FTP__|${ARCHIVE_FTP}|g\" | sed \"s|#admin=|admin=${ARCHIVE_ADMINS}|g\" > /var/www/html/site/cfg/archive.cfg"
bash -c "sed \"s|__ARCHIVE_EXT_FTP__|${ARCHIVE_EXT_FTP}|g\" /etc/apache2/conf-enabled/archive.conf.template > /etc/apache2/conf-enabled/archive.conf"
bash -c "sed \"s|_HOST__/__ARCHIVE|_HOST____ARCHIVE|g\" /var/www/html/site/cfg/apache.cfg.docker_template | sed \"s|__ARCHIVE_HTTP_HOST__|${ARCHIVE_HTTP_HOST}|g\" | sed \"s|__ARCHIVE_HTTP_ROOT__|${ARCHIVE_HTTP_ROOT}|g\" > /var/www/html/site/cfg/apache.cfg"
bash -c "echo \"incoming_http_path=/data/http\" >> /var/www/html/site/cfg/archive.cfg"

# Create storage dir if not mounted
mkdir -p /data/store/
mkdir -p /data/http/
mkdir -p /data/http_tmp/
mkdir -p /data/ftp/

# Ensure permissions are ok
chown -R www-data: /data/store/
chown -R www-data: /data/http/
chown -R www-data: /data/http_tmp/

# Create a symbolic link corresponding to $ARCHIVE_HTTP_ROOT
if [[ "${ARCHIVE_HTTP_ROOT}" != "" ]]
then
    if [ ! -L "./${ARCHIVE_HTTP_ROOT}" ]
    then
        basedir=`dirname "./${ARCHIVE_HTTP_ROOT}"`
        if [[ "$basedir" != "." ]]
        then
            mkdir -p $basedir
        fi
        ln -s . "./${ARCHIVE_HTTP_ROOT}"
    fi
fi

service cron start

exec apache2-foreground

exit 1

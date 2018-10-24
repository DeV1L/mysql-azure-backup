#!/bin/bash

if [ "${RESTORE_DB_CHARSET}" = "" ]; then
  export RESTORE_DB_CHARSET=utf8
fi

if [ "${RESTORE_DB_COLLATION}" = "" ]; then
  export RESTORE_DB_COLLATION=utf8_bin
fi

PASS_OPT=

if [ -n $MYSQL_PASSWORD ]; then
    PASS_OPT="--password=${MYSQL_PASSWORD}"
fi

if [ "$1" == "backup" ]; then
    if [ -n "$2" ]; then
        databases=$2
    else
        databases=`mysql --user=$MYSQL_USER --host=$MYSQL_HOST --port=$MYSQL_PORT ${PASS_OPT} -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema)"`
    fi

    for db in $databases; do
        echo "dumping $db"

        mysqldump --force --opt --host=$MYSQL_HOST --port=$MYSQL_PORT --user=$MYSQL_USER --databases $db ${PASS_OPT} | gzip > "/tmp/$db.gz"

        if [ $? == 0 ]; then
            az storage blob upload --file /tmp/$db.gz --account-name $AZURE_STORAGE_ACCOUNT --container-name $AZURE_STORAGE_CONTAINER --account-key $AZURE_STORAGE_ACCESS_KEY --name $db/$(date +%Y_%m_%d).gz

            if [ $? == 0 ]; then
                rm /tmp/$db.gz
            else
                >&2 echo "couldn't transfer $db.gz to Azure"
            fi
        else
            >&2 echo "couldn't dump $db"
        fi
    done
elif [ "$1" == "restore" ]; then
    if [ -n "$2" ]; then
        archives=$2.gz
    else
        archives=`az storage blob list -a $AZURE_STORAGE_ACCOUNT -k "$AZURE_STORAGE_ACCESS_KEY" $AZURE_STORAGE_CONTAINER | grep ".gz" | awk '{print $2}'`
    fi

    for archive in $archives; do
        tmp=/tmp/$archive

        echo "restoring $archive"
        echo "...transferring"

        yes | az storage blob download  -a $AZURE_STORAGE_ACCOUNT -k "$AZURE_STORAGE_ACCESS_KEY" $AZURE_STORAGE_CONTAINER $archive $tmp

        if [ $? == 0 ]; then
            echo "...restoring"
            db=`basename --suffix=.gz $archive`

            if [ -n $MYSQL_PASSWORD ]; then
                yes | mysqladmin --host=$MYSQL_HOST --port=$MYSQL_PORT --user=$MYSQL_USER --password=$MYSQL_PASSWORD drop $db

                mysql --host=$MYSQL_HOST --port=$MYSQL_PORT --user=$MYSQL_USER --password=$MYSQL_PASSWORD -e "CREATE DATABASE $db CHARACTER SET $RESTORE_DB_CHARSET COLLATE $RESTORE_DB_COLLATION"
                gunzip -c $tmp | mysql --host=$MYSQL_HOST --port=$MYSQL_PORT --user=$MYSQL_USER --password=$MYSQL_PASSWORD $db
            else
                yes | mysqladmin --host=$MYSQL_HOST --port=$MYSQL_PORT --user=$MYSQL_USER drop $db

                mysql --host=$MYSQL_HOST --port=$MYSQL_PORT --user=$MYSQL_USER -e "CREATE DATABASE $db CHARACTER SET $RESTORE_DB_CHARSET COLLATE $RESTORE_DB_COLLATION"
                gunzip -c $tmp | mysql --host=$MYSQL_HOST --port=$MYSQL_PORT --user=$MYSQL_USER $db
            fi
        else
            rm $tmp
        fi
    done
else
    >&2 echo "You must provide either backup or restore to run this container"
    exit 64
fi

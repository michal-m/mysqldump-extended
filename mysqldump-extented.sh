#!/usr/bin/env bash
# mmusial 25-05-2010, updated 28-06-2011
# backup each mysql db into a different file, rather than one big file
# as with --all-databases - will make restores easier
# based on:
# http://soniahamilton.wordpress.com/2005/11/16/backup-multiple-databases-into-separate-files/
# http://mysqlpreacher.com/wordpress/2010/08/dumping-ddl-mysqldump-tables-stored-procedures-events-triggers-separately/

echo "START"
echo

DATE=`date +'%Y%m%d'`

DIR_BACKUP="/home/update"
DIR_SQL="mysqldumps_${DATE}"

# MYSQL_USER must have following global privileges:
# SHOW DATABASES, SELECT, LOCK TABLES
MYSQL_USER="mysqldump"
MYSQL_PASSWORD="*****"
MYSQLDUMP="/usr/local/bin/mysqldump"
MYSQL="/usr/local/bin/mysql"

STAT="/usr/bin/stat"
TAR="/usr/bin/tar"
OUTPUT_FILE="mysqldumps.tar.gz"

echo "Deleting any old backups..."
rm -fv ${DIR_BACKUP}/mysqldump*.tar.gz

echo
echo "Creating temporary folder: ${DIR_SQL}."
mkdir ${DIR_BACKUP}/${DIR_SQL}

echo
echo -n "Retrieving list of all databases... "
aDatabases=( $($MYSQL --user=$MYSQL_USER --password=$MYSQL_PASSWORD -N -e "SHOW DATABASES;" | grep -Ev "(test|information_schema|mysql|performance_schema)") )
echo "done."
echo "Found" ${#aDatabases[@]}" valid database(s)."
echo

sDatabases=${aDatabases[*]}

echo "Beginning dump process..."
STATIC_PARAMS="--default-character-set=utf8 --user=$MYSQL_USER --password=$MYSQL_PASSWORD"
for db in $sDatabases; do
    echo -n "- dumping '${db}'... "
    SECONDS=0
    # dumping database tables structure
    $MYSQLDUMP \
        --no-data \
        --set-charset \
        --skip-triggers \
        --skip-opt \
        $STATIC_PARAMS \
        --databases $db > ${DIR_BACKUP}/${DIR_SQL}/$db.1-DB+TABLES+VIEWS.sql

    # dumping routines
    $MYSQLDUMP \
        --no-create-db \
        --no-create-info \
        --no-data \
        --routines \
        --skip-opt \
        --skip-triggers \
        $STATIC_PARAMS \
        --databases $db > ${DIR_BACKUP}/${DIR_SQL}/$db.2-ROUTINES.sql

    # dumping triggers
    $MYSQLDUMP \
        --no-create-db \
        --no-create-info \
        --no-data \
        --skip-opt \
        --triggers \
        $STATIC_PARAMS \
        --databases $db > ${DIR_BACKUP}/${DIR_SQL}/$db.3-TRIGGERS.sql

    # dumping events (works in MySQL 5.1+)
    $MYSQLDUMP \
        --events \
        --no-create-db \
        --no-create-info \
        --no-data \
        --skip-opt \
        --skip-triggers \
        $STATIC_PARAMS \
        --databases $db > ${DIR_BACKUP}/${DIR_SQL}/$db.4-EVENTS.sql

    # dumping data
    $MYSQLDUMP \
        --force \
        --hex-blob \
        --no-create-db \
        --no-create-info \
        --opt \
        --skip-triggers \
        $STATIC_PARAMS \
        --databases $db > ${DIR_BACKUP}/${DIR_SQL}/$db.5-DATA.sql

    echo "done in" $SECONDS "second(s);"
done

echo -n "- dumping PRIVILEGES... "
SECONDS=0
$MYSQL -B -N --user=$MYSQL_USER --password=$MYSQL_PASSWORD -e "SELECT DISTINCT CONCAT(
        'SHOW GRANTS FOR ''', user, '''@''', host, ''';'
        ) AS query FROM mysql.user" | \
        $MYSQL --user=$MYSQL_USER --password=$MYSQL_PASSWORD | \
        sed 's/\(GRANT .*\)/\1;/;s/^\(Grants for .*\)/## \1 ##/;/##/{x;p;x;}' > "${DIR_BACKUP}/${DIR_SQL}/PRIVILEGES.sql"
echo "done in" $SECONDS "second(s)."
echo "Dump process completed."

echo
echo -n "Tarballing all sql dumps... "
cd ${DIR_BACKUP}
SECONDS=0
$TAR cfz ${OUTPUT_FILE} ${DIR_SQL}
echo "done in" $SECONDS "second(s)."

output_file_size=`$STAT -f %z $OUTPUT_FILE`

echo
echo "Deleting sql files... "
rm -fvR ${DIR_BACKUP}/${DIR_SQL}
echo "done."

echo
echo "Final dump file: ${DIR_BACKUP}/${OUTPUT_FILE} (${output_file_size} bytes)."
echo

echo "END."
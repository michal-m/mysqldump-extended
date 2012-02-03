#!/usr/bin/env bash
# backup each mysql database into a different file, rather than one big file
# as with --all-databases - will make restores easier
# based on:
# http://soniahamilton.wordpress.com/2005/11/16/backup-multiple-databases-into-separate-files/
# http://mysqlpreacher.com/wordpress/2010/08/dumping-ddl-mysqldump-tables-stored-procedures-events-triggers-separately/

# Functions
function verbose {
    if [ "$VERBOSE" ]; then
        if [ "$2" ]; then
            echo -en $1;
        else
            echo -e $1;
        fi
    fi
}

# Initial Variable definitions
# MYSQL_USER must have following global privileges:
# SELECT, SHOW DATABASES, LOCK TABLES, EVENT, TRIGGER, SHOW VIEW
MYSQL_USER="mysqldump"
MYSQL_HOST="localhost"
MYSQL_CHARSET="utf8"
BACKUP_DIR="."

# Parse commandline options first
while :
do
    case "$1" in
        -c | --default-charset)
            if [ -z "$2" ]; then echo "Error: Default character set not specified" >&2; exit 1; fi
            MYSQL_CHARSET=$2
            shift 2
            ;;
        -d | --output-directory)
            if [ -z "$2" ]; then echo "Error: Output directory not specified" >&2; exit 1; fi
            BACKUP_DIR=$2
            shift 2
            ;;
        -h | --host)
            if [ -z "$2" ]; then echo "Error: MySQL server hostname not specified" >&2; exit 1; fi
            MYSQL_HOST=$2
            shift 2
            ;;
        -p | --pass)
            if [ -z "$2" ]; then echo "Error: MySQL password not specified" >&2; exit 1; fi
            MYSQL_PASSWORD=$2
            shift 2
            ;;
        -u | --user)
            if [ -z "$2" ]; then echo "Error: MySQL username not specified" >&2; exit 1; fi
            MYSQL_USER=$2
            shift 2
            ;;
        -v | --verbose)
            VERBOSE="verbose"
            shift
            ;;
#        --) # End of all options
#            shift
#            break;
        -*)
            echo "Error: Unknown option: $1" >&2
            exit 1
            ;;
        *)  # No more options
            break
            ;;
    esac
done

# Checking if required parameters are present and valid
if [ ! -d "$BACKUP_DIR" ]; then echo "Error: Specified output is not a directory" >&2; exit 1; fi
if [ ! -w "$BACKUP_DIR" ]; then echo "Error: Output directory is not writable" >&2; exit 1; fi
if [ -z "$MYSQL_PASSWORD" ]; then echo "Error: MySQL password not provided or empty" >&2; exit 1; fi

# OK, let's roll
verbose "START\n" 1

DATE=`date +'%Y%m%d'`

DIR_SQL="mysqldumps_${DATE}"

STATIC_PARAMS="--default-character-set=$MYSQL_CHARSET --host=$MYSQL_HOST --user=$MYSQL_USER --password=$MYSQL_PASSWORD"
MYSQLDUMP="/usr/local/bin/mysqldump"
MYSQL="/usr/local/bin/mysql"

STAT="/usr/bin/stat"
TAR="/usr/bin/tar"
OUTPUT_FILE="mysqldumps.tar.gz"

verbose "Deleting any old backups..."
rm -fv ${BACKUP_DIR}/mysqldump*.tar.gz

verbose "\nCreating temporary folder: ${DIR_SQL}."
mkdir ${BACKUP_DIR}/${DIR_SQL}

verbose "\nRetrieving list of all databases... " 1
aDatabases=( $($MYSQL $STATIC_PARAMS -N -e "SHOW DATABASES;" | grep -Ev "(test|information_schema|mysql|performance_schema|phpmyadmin)") )
verbose "done."
verbose "Found" ${#aDatabases[@]}" valid database(s).\n"

sDatabases=${aDatabases[*]}

verbose "Beginning dump process..."
for db in $sDatabases; do
    verbose "- dumping '${db}'... " 1
    SECONDS=0
    # dumping database tables structure
    $MYSQLDUMP $STATIC_PARAMS \
        --no-data \
        --opt \
        --set-charset \
        --skip-triggers \
        --databases $db > ${BACKUP_DIR}/${DIR_SQL}/$db.1-DB+TABLES+VIEWS.sql

    # dumping data
    $MYSQLDUMP $STATIC_PARAMS \
        --force \
        --hex-blob \
        --no-create-db \
        --no-create-info \
        --opt \
        --skip-triggers \
        --databases $db > ${BACKUP_DIR}/${DIR_SQL}/$db.2-DATA.sql

    # dumping triggers
    $MYSQLDUMP $STATIC_PARAMS \
        --no-create-db \
        --no-create-info \
        --no-data \
        --skip-opt --create-options \
        --triggers \
        --databases $db > ${BACKUP_DIR}/${DIR_SQL}/$db.3-TRIGGERS.sql

    # dumping events (works in MySQL 5.1+)
    $MYSQLDUMP $STATIC_PARAMS \
        --events \
        --no-create-db \
        --no-create-info \
        --no-data \
        --skip-opt --create-options \
        --skip-triggers \
        --databases $db > ${BACKUP_DIR}/${DIR_SQL}/$db.4-EVENTS.sql

    # dumping routines
    $MYSQLDUMP $STATIC_PARAMS \
        --no-create-db \
        --no-create-info \
        --no-data \
        --routines \
        --skip-opt --create-options \
        --skip-triggers \
        --databases $db > ${BACKUP_DIR}/${DIR_SQL}/$db.5-ROUTINES.sql

    verbose "done in" $SECONDS "second(s);"
done

verbose "- dumping PRIVILEGES... " 1
SECONDS=0
$MYSQL $STATIC_PARAMS -B -N -e "SELECT DISTINCT CONCAT(
        'SHOW GRANTS FOR ''', user, '''@''', host, ''';'
        ) AS query FROM mysql.user" | \
        $MYSQL $STATIC_PARAMS | \
        sed 's/\(GRANT .*\)/\1;/;s/^\(Grants for .*\)/## \1 ##/;/##/{x;p;x;}' > "${BACKUP_DIR}/${DIR_SQL}/PRIVILEGES.sql"
verbose "done in" $SECONDS "second(s)."
verbose "Dump process completed."

verbose "\nTarballing all sql dumps... " 1
cd ${BACKUP_DIR}
SECONDS=0
$TAR cfz ${OUTPUT_FILE} ${DIR_SQL}
verbose "done in" $SECONDS "second(s)."

output_file_size=`$STAT -f %z $OUTPUT_FILE`

verbose "\nDeleting sql files... " 1
rm -fvR ${BACKUP_DIR}/${DIR_SQL}
verbose "done."

verbose "\nFinal dump file: ${BACKUP_DIR}/${OUTPUT_FILE} (${output_file_size} bytes).\n"
verbose "END."

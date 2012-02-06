#!/usr/bin/env bash
#
# Fork me on github:
#   http://github.com/michal-m/mysqldump-extended
#
# Author:
#   Michał Musiał <michal.j.musial@gmail.com>
#   Copyright 2012, no rights reserved.

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

# Exit on errors
set -e

# Initial Variable definitions
DATE=`date +'%Y%m%d'`
TAR="/usr/bin/tar"
MYSQL_BIN_DIR="/usr/local/bin"
MYSQL_USER="mysqldump"
MYSQL_HOST="localhost"
MYSQL_CHARSET="utf8"
OUTPUT_DIR="."
OUTPUT_FILE="mysqldumps.tar.gz"
DUMPS_DIRNAME="mysqldumps_${DATE}"

# Parse commandline options first
while :
do
    case "$1" in  
        -B | --bin-dir)
            if [ -z "$2" ]; then echo "Error: MySQL binaries directory not specified" >&2; exit 1; fi
            MYSQL_BIN_DIR=$2
            shift 2
            ;;
        -c | --default-charset)
            if [ -z "$2" ]; then echo "Error: Default character set not specified" >&2; exit 1; fi
            MYSQL_CHARSET=$2
            shift 2
            ;;
        -d | --database)
            if [ -z "$2" ]; then echo "Error: Database name not specified" >&2; exit 1; fi
            DATABASE_NAME=$2
            shift 2
            ;;
        -D | --output-directory)
            if [ -z "$2" ]; then echo "Error: Output directory not specified" >&2; exit 1; fi
            OUTPUT_DIR=$2
            shift 2
            ;;
        -h | --host)
            if [ -z "$2" ]; then echo "Error: MySQL server hostname not specified" >&2; exit 1; fi
            MYSQL_HOST=$2
            shift 2
            ;;
        -F | --output-file)
            if [ -z "$2" ]; then echo "Error: Output filename not specified" >&2; exit 1; fi
            OUTPUT_FILE=$2
            TAR_GZ="tar gz"
            shift 2
            ;;
        -k | --skip-delete-previous)
            SKIP_DELETE_PREVIOUS="skip delete previous"
            shift
            ;;
        -p | --pass)
            if [ -z "$2" ]; then echo "Error: MySQL password not specified" >&2; exit 1; fi
            MYSQL_PASSWORD=$2
            shift 2
            ;;
        -s | --split-database-files)
            SPLIT_DATABASE_FILES="split database files"
            shift
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
        -z | --tar-gz)
            TAR_GZ="tar gz"
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

# First, make sure mysql binaries are accessible
if [ ! -d "$MYSQL_BIN_DIR" ]; then
	echo "Error: Speciefied MySQL binaries directory is not valid" >&2
	exit 1
elif [ ! -x "${MYSQL_BIN_DIR}/mysql" -o ! -x "${MYSQL_BIN_DIR}/mysqldump" ] ; then
	echo "Error: MySQL binaries don't exits or are not executable" >&2
	exit 1
else
	MYSQL="${MYSQL_BIN_DIR}/mysql"
	MYSQLDUMP="${MYSQL_BIN_DIR}/mysqldump"
fi

# Checking if other required parameters are present and valid
if [ ! -d "$OUTPUT_DIR" ]; then echo "Error: Specified output is not a directory" >&2; exit 1; fi
if [ ! -w "$OUTPUT_DIR" ]; then echo "Error: Output directory is not writable" >&2; exit 1; fi
if [ -e "${OUTPUT_DIR}/${OUTPUT_FILE}" ]; then echo "Error: Specified output file already exists" >&2; exit 1; fi
if [ -z "$MYSQL_PASSWORD" ]; then echo "Error: MySQL password not provided or empty" >&2; exit 1; fi
if [ -e "${OUTPUT_DIR}/${DUMPS_DIRNAME}" ]; then echo "Error: Output directory already contains a file/folder with the same name as temporary folder required: ${OUTPUT_DIR}/$DUMPS_DIRNAME" >&2; exit 1; fi
if [ "$TAR_GZ" ] && [ ! -x "$TAR" ]; then echo "Error: Tar not found or not executable (looking at: $TAR)" >&2; exit 1; fi

# OK, let's roll
verbose "START\n"

STATIC_PARAMS="--default-character-set=$MYSQL_CHARSET --host=$MYSQL_HOST --user=$MYSQL_USER --password=$MYSQL_PASSWORD"

STAT="/usr/bin/stat"

if [ "$SKIP_DELETE_PREVIOUS" ]; then
    verbose "NOT deleting any old backups..."
else
    verbose "Deleting any old backups..."
    
    if [ "$TAR_GZ" ]; then
        rm -fv ${OUTPUT_DIR}/mysqldump*.tar.gz
    else
        rm -fRv ${OUTPUT_DIR}/${DUMPS_DIRNAME}
    fi
fi

if [ "$DATABASE_NAME" ]; then
    verbose "\nDatabase to be dumped: $DATABASE_NAME"
    sDatabases=$DATABASE_NAME
else
    verbose "\nRetrieving list of all databases...\t" 1
    aDatabases=( $($MYSQL $STATIC_PARAMS -N -e "SHOW DATABASES;" | grep -Ev "(test|information_schema|mysql|performance_schema|phpmyadmin)") )
    verbose "done."
    verbose "Found ${#aDatabases[@]} valid database(s).\n"

    sDatabases=${aDatabases[*]}
fi

verbose "\nCreating temporary folder: ${DUMPS_DIRNAME}."
mkdir ${OUTPUT_DIR}/${DUMPS_DIRNAME}

verbose "Beginning dump process..."
for db in $sDatabases; do
    verbose "- dumping '${db}'...\t" 1
    SECONDS=0
	if [ "$SPLIT_DATABASE_FILES" ]; then
	    # dumping database tables structure
	    $MYSQLDUMP $STATIC_PARAMS \
	        --no-data \
	        --opt \
	        --set-charset \
	        --skip-triggers \
	        --databases $db > ${OUTPUT_DIR}/${DUMPS_DIRNAME}/$db.1-DB+TABLES+VIEWS.sql

	    # dumping data
	    $MYSQLDUMP $STATIC_PARAMS \
	        --force \
	        --hex-blob \
	        --no-create-db \
	        --no-create-info \
	        --opt \
	        --skip-triggers \
	        --databases $db > ${OUTPUT_DIR}/${DUMPS_DIRNAME}/$db.2-DATA.sql

	    # dumping triggers
	    $MYSQLDUMP $STATIC_PARAMS \
	        --no-create-db \
	        --no-create-info \
	        --no-data \
	        --skip-opt --create-options \
	        --triggers \
	        --databases $db > ${OUTPUT_DIR}/${DUMPS_DIRNAME}/$db.3-TRIGGERS.sql

	    # dumping events (works in MySQL 5.1+)
	    $MYSQLDUMP $STATIC_PARAMS \
	        --events \
	        --no-create-db \
	        --no-create-info \
	        --no-data \
	        --skip-opt --create-options \
	        --skip-triggers \
	        --databases $db > ${OUTPUT_DIR}/${DUMPS_DIRNAME}/$db.4-EVENTS.sql

	    # dumping routines
	    $MYSQLDUMP $STATIC_PARAMS \
	        --no-create-db \
	        --no-create-info \
	        --no-data \
	        --routines \
	        --skip-opt --create-options \
	        --skip-triggers \
	        --databases $db > ${OUTPUT_DIR}/${DUMPS_DIRNAME}/$db.5-ROUTINES.sql
	else
		$MYSQLDUMP $STATIC_PARAMS \
			--events \
			--force \
			--hex-blob \
			--opt \
			--routines \
			--triggers \
            --databases $db > ${OUTPUT_DIR}/${DUMPS_DIRNAME}/$db.sql
    fi
        
    verbose "done in $SECONDS second(s);"
done

# We're not going to dump Privileges if only a single Database dumped
if [ -z "$DATABASE_NAME" ]; then
    verbose "- dumping PRIVILEGES...\t" 1
    SECONDS=0
    $MYSQL $STATIC_PARAMS -B -N -e "SELECT DISTINCT CONCAT(
            'SHOW GRANTS FOR ''', user, '''@''', host, ''';'
            ) AS query FROM mysql.user" | \
            $MYSQL $STATIC_PARAMS | \
            sed 's/\(GRANT .*\)/\1;/;s/^\(Grants for .*\)/## \1 ##/;/##/{x;p;x;}' > "${OUTPUT_DIR}/${DUMPS_DIRNAME}/PRIVILEGES.sql"
    verbose "done in  $SECONDS second(s)."
fi

verbose "Dump process completed."

if [ "$TAR_GZ" ]; then
    verbose "\nTarballing all sql dumps...\t" 1
    cd ${OUTPUT_DIR}
    SECONDS=0
    $TAR cfz ${OUTPUT_FILE} ${DUMPS_DIRNAME}
    verbose "done in  $SECONDS second(s)."

    verbose "\nDeleting sql files...\t" 1
    rm -fvR ${OUTPUT_DIR}/${DUMPS_DIRNAME}
    verbose "done."

    verbose "\nFinal dump file: ${OUTPUT_DIR}/${OUTPUT_FILE}" 1

    if [ -x "$STAT" ]; then
        output_file_size=`$STAT -f %z $OUTPUT_FILE`
        verbose " (${output_file_size} bytes).\n"
    else
        verbose "\n"
    fi
fi

verbose "END."

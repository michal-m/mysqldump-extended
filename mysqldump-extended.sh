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
STAT="/usr/bin/stat"
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
        -e | --enclose)
            ENCLOSE="enclose"
            shift
            ;;
        -F | --output-file)
            if [ -z "$2" ]; then echo "Error: Output filename not specified" >&2; exit 1; fi
            OUTPUT_FILE=$2
            OUTPUT_FILE_EXT=${2}.tar.gz
            TAR_GZ="tar gz"
            shift 2
            ;;
        -f | --force)
            FORCE="force"
            shift
            ;;
        -h | --host)
            if [ -z "$2" ]; then echo "Error: MySQL server hostname not specified" >&2; exit 1; fi
            MYSQL_HOST=$2
            shift 2
            ;;
        -o | --overwrite)
            OVERWRITE="overwrite"
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
            ENCLOSE="enclose"
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

verbose "-- Dump process started on `date`"

if [ "$FORCE" ]; then
    set +e
    verbose "!!! Force mode enabled !!!"
fi

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

# Secondly, apply compatibility tweaks based on MySQL version
verbose "\n---------------------------------------------------"
verbose "mysqldump compatibility check..."
MYSQL_V=`$MYSQL -V | sed -E 's/.*Distrib ([0-9]\.[0-9]+\.[0-9]+).*/\1/'`
verbose "MySQL Version: ${MYSQL_V}"

MYSQL_VERSIONS=(${MYSQL_V//./ })
MYSQL_VER=${MYSQL_VERSIONS[0]}
MYSQL_MAJ=${MYSQL_VERSIONS[1]}
MYSQL_MIN=${MYSQL_VERSIONS[2]}

verbose "- Triggers..." 1
if [ "${MYSQL_VER}" -gt 5 -o \
     "${MYSQL_VER}" -eq 5 -a "${MYSQL_MAJ}" -ge 1 -o \
     "${MYSQL_VER}" -eq 5 -a "${MYSQL_MAJ}" -eq 0 -a "${MYSQL_MIN}" -ge 11 ]; then
    NO_TRIGGERS="--skip-triggers"
    TRIGGERS="--triggers"
    verbose "enabled"
else
    NO_TRIGGERS=""
    TRIGGERS=""
    verbose "disabled"
fi

verbose "- Routines..." 1
if [ "${MYSQL_VER}" -gt 5 -o \
     "${MYSQL_VER}" -eq 5 -a "${MYSQL_MAJ}" -ge 2 -o \
     "${MYSQL_VER}" -eq 5 -a "${MYSQL_MAJ}" -eq 1 -a "${MYSQL_MIN}" -ge 2 -o \
     "${MYSQL_VER}" -eq 5 -a "${MYSQL_MAJ}" -eq 0 -a "${MYSQL_MIN}" -ge 13 ]; then
    ROUTINES="--routines"
    verbose "enabled"
else
    ROUTINES=""
    verbose "disabled"
fi

verbose "- Events..." 1
if [ "${MYSQL_VER}" -gt 5 -o \
     "${MYSQL_VER}" -eq 5 -a "${MYSQL_MAJ}" -ge 2 -o \
     "${MYSQL_VER}" -eq 5 -a "${MYSQL_MAJ}" -eq 1 -a "${MYSQL_MIN}" -ge 8 ]; then
    EVENTS="--events"
    verbose "enabled"
else
    EVENTS=""
    verbose "disabled"
fi
verbose "---------------------------------------------------\n"

# Checking if other required parameters are present and valid
if [ ! -d "$OUTPUT_DIR" ]; then echo "Error: Specified output is not a directory" >&2; exit 1; fi
if [ ! -w "$OUTPUT_DIR" ]; then echo "Error: Output directory is not writable" >&2; exit 1; fi
if [ "$TAR_GZ" -a -e "${OUTPUT_DIR}/${OUTPUT_FILE}" -a -z "$OVERWRITE" ]; then echo "Error: Specified output file already exists" >&2; exit 1; fi
if [ -z "$MYSQL_PASSWORD" ]; then echo "Error: MySQL password not provided or empty" >&2; exit 1; fi
if [ -e "${OUTPUT_DIR}/${DUMPS_DIRNAME}" -a -z "$OVERWRITE" ]; then echo "Error: Output directory already contains a file/folder with the same name as temporary folder required: ${OUTPUT_DIR}/$DUMPS_DIRNAME" >&2; exit 1; fi
if [ "$TAR_GZ" ] && [ ! -x "$TAR" ]; then echo "Error: Tar not found or not executable (looking at: $TAR)" >&2; exit 1; fi

# OK, let's roll
STATIC_PARAMS="--default-character-set=$MYSQL_CHARSET --host=$MYSQL_HOST --user=$MYSQL_USER --password=$MYSQL_PASSWORD"

if [ "$OVERWRITE" -a "$ENCLOSE" ]; then
    verbose "Deleting any old backups..."

    if [ "$TAR_GZ" ]; then
        rm -fv ${OUTPUT_DIR}/${OUTPUT_FILE}
    else
        rm -fRv ${OUTPUT_DIR}/${DUMPS_DIRNAME}
    fi
else
    verbose "NOT deleting any old backups..."
fi

if [ "$DATABASE_NAME" ]; then
    verbose "\nDatabase to be dumped: $DATABASE_NAME"
    sDatabases=$DATABASE_NAME
else
    verbose "\nRetrieving list of all databases..." 1
    aDatabases=( $($MYSQL $STATIC_PARAMS -N -e "SHOW DATABASES;" | grep -Ev "(test|information_schema|mysql|performance_schema|phpmyadmin)") )

    if [ -z "$aDatabases" ]; then
        verbose "found NONE."
        sDatabases=""
    else
        verbose "found ${#aDatabases[@]}."
        sDatabases=${aDatabases[*]}
    fi
fi

if [ "$ENCLOSE" ]; then
    if [ -d "${OUTPUT_DIR}/${DUMPS_DIRNAME}" ]; then
        verbose "\nTemporary folder already exists: ${DUMPS_DIRNAME}."
    else
        verbose "\nCreating temporary folder: ${DUMPS_DIRNAME}."
        mkdir ${OUTPUT_DIR}/${DUMPS_DIRNAME}
    fi

    OUTPUT_PATH=${OUTPUT_DIR}/${DUMPS_DIRNAME}
else
    OUTPUT_PATH=${OUTPUT_DIR}
fi

verbose "Beginning dump process..."
for db in $sDatabases; do
    verbose "- dumping '${db}'..." 1
    SECONDS=0
    if [ "$SPLIT_DATABASE_FILES" ]; then
        i=1

        # DATABASE + TABLE SCHEMA
        $MYSQLDUMP $STATIC_PARAMS \
            --no-data \
            --opt \
            --set-charset \
            $NO_TRIGGERS \
            --databases $db > ${OUTPUT_PATH}/${db}.${i}-DB+TABLES+VIEWS.sql

        (( i++ ))

        # DATA
        $MYSQLDUMP $STATIC_PARAMS \
            --force \
            --hex-blob \
            --no-create-db \
            --no-create-info \
            --opt \
            $NO_TRIGGERS \
            --databases $db > ${OUTPUT_PATH}/${db}.${i}-DATA.sql

        (( i++ ))

        # TRIGGERS
        if [ "${TRIGGERS}" ]; then
            $MYSQLDUMP $STATIC_PARAMS \
                --no-create-db \
                --no-create-info \
                --no-data \
                --skip-opt --create-options \
                $TRIGGERS \
                --databases $db > ${OUTPUT_PATH}/${db}.${i}-TRIGGERS.sql
        fi

        (( i++ ))

        # EVENTS
        if [ "${EVENTS}" ]; then
            $MYSQLDUMP $STATIC_PARAMS \
                $EVENTS \
                --no-create-db \
                --no-create-info \
                --no-data \
                --skip-opt --create-options \
                $NO_TRIGGERS \
                --databases $db > ${OUTPUT_PATH}/${db}.${i}-EVENTS.sql
        fi

        (( i++ ))

        # ROUTINES
        if [ "${ROUTINES}" ]; then
            $MYSQLDUMP $STATIC_PARAMS \
                --no-create-db \
                --no-create-info \
                --no-data \
                $ROUTINES \
                --skip-opt --create-options \
                $NO_TRIGGERS \
                --databases $db > ${OUTPUT_PATH}/${db}.${i}-ROUTINES.sql
        fi
    else
        $MYSQLDUMP $STATIC_PARAMS \
            $EVENTS \
            --force \
            --hex-blob \
            --opt \
            ${ROUTINES} \
            ${TRIGGERS} \
            --databases $db > ${OUTPUT_PATH}/${db}.sql
    fi

    verbose "done in $SECONDS second(s)"
done

# We're not going to dump Privileges if only a single Database dumped
if [ -z "$DATABASE_NAME" ]; then
    verbose "- dumping PRIVILEGES..." 1
    SECONDS=0
    $MYSQL $STATIC_PARAMS -B -N -e "SELECT DISTINCT CONCAT(
            'SHOW GRANTS FOR ''', user, '''@''', host, ''';'
            ) AS query FROM mysql.user" | \
            $MYSQL $STATIC_PARAMS | \
            sed 's/\(GRANT .*\)/\1;/;s/^\(Grants for .*\)/## \1 ##/;/##/{x;p;x;}' > "${OUTPUT_PATH}/PRIVILEGES.sql"
    verbose "done in  $SECONDS second(s)."
fi

verbose "Dump process completed."

if [ "$TAR_GZ" ]; then
    verbose "\nTarballing all sql dumps..." 1
    cd ${OUTPUT_DIR}
    SECONDS=0
    $TAR cfz ${OUTPUT_FILE_EXT} ${DUMPS_DIRNAME}
    verbose "done in  $SECONDS second(s)."

    verbose "\nDeleting sql files..."
    rm -fvR ${OUTPUT_DIR}/${DUMPS_DIRNAME}
    verbose "...done."

    verbose "\nFinal dump file: ${OUTPUT_DIR}/${OUTPUT_FILE_EXT}\t" 1

    if [ -x "$STAT" ]; then
        output_file_size=`$STAT -f %z $OUTPUT_FILE_EXT`
        verbose "(${output_file_size} bytes).\n"
    else
        verbose "\n"
    fi
fi

verbose "-- Dump process completed on `date`"

# mysqldump-extended

**mysqldump-extended** is a handy wrapper for mysqldump binary. It provides several additional features that mysqldump doesn't, e.g. each database is dumped in separate set of files, which makes reading and analysing dumped files a lot easier.

## Key features
- **Databases dumped in separate set of files**  
The output is no longer one large file, but instead each database has its own file (or set of files).
- **Each Database can be dumped into a separate set of files**  
This files follow [mysqldump output order](http://stackoverflow.com/a/9136706/108878):
  1. Database
  2. Tables and Views
     1. Table schema (inc. constraints)
     2. Table data
     3. Table triggers
  3. Views - temporary tables only!
  4. Events.
  5. Routines.
- **The dumped files can be optionally tarballed+gzipped after the dump process is completed**
- **Includes a complete privileges dump**

## Requirements
For this script to work there must be a user defined in the database with following permissions:
`SELECT, SHOW DATABASES, LOCK TABLES, EVENT, TRIGGER, SHOW VIEW`.
An example code to create such user would look like this:
`GRANT SELECT, SHOW DATABASES, LOCK TABLES, EVENT, TRIGGER, SHOW VIEW 
ON *.* TO 'username'@'hostname' IDENTIFIED BY PASSWORD 'password';`

## Usage
`mysqldump-extended.sh -p <password> OPTIONS`

### Options
    -B, --bin-dir <path>
                        Path to folder containing MySQL binaries.
                        Default: /usr/local/bin
    -b, --subdir        Contain dumped files in a subfolder. If enabled
						subfolder name is `mysqldumps_%Y%m%d`
    -c, --default-charset <charset>
                        Same as --default-character-set in mysqldump.
                        Default: utf8
    -d, --database <name>
                        Name of the database to be dumped. If provided,
                        only this database will be dumped, otherwise all
                        databases will be dumped.
						If set, privileges will not be dumped.
    -D, --output-directory <path>
                        The path to directory where the dumps will be places.
                        Default: .
    -h, --host <name>   Database server hostname.
                        Default: localhost
    -F, --output-file <name>
                        Name of the output file. Implies -z.
                        Default: mysqldumps.tar.gz
    -f, --force         Carry on on errors.
    -k, --skip-delete-previous
                        Skips deleting previous dump file/folder if exists.
    -p, --password <pass>
                        Password to use when connecting.
                        *Required*
                        *Must not be empty*
    -s, --split-database-files
						Will split database dump into separate files.
    -u, --user <name>   User for login if not current.
                        Default: mysqldump
    -v, --verbose       Print out details of the backup process.
    -z, --tar-gz        Tarball and Gzip dumped files.
						Implies -b
                        

### Examples
`mysqldump-extended.sh -h 127.0.0.1 -u backup-client -p password`

Overrides the default database server hostname and username.

`mysqldump-extended.sh -p password -d test -c latin1`

Dumps only a single database 'test' with --default-character-set set to 'latin1'.

`mysqldump-extended.sh -p password -s -z`

Splits database dumps onto separate files and tarballs the dumps.

`mysqldump-extended.sh -h 127.0.0.1 -u backup-client -p password -D /var/backups -F mysql-backup.tar.gz -s -v`

Overrides the default hostname, username, output directory and fileneame (implies tarballing as well) and splits the database dump into separate files.

## Acknowledgments
This script is heavily based on MySQL Backup scripts by [Sonia Hamilton](http://soniahamilton.wordpress.com/2005/11/16/backup-multiple-databases-into-separate-files/) and [Darren Cassar](http://mysqlpreacher.com/wordpress/2010/08/dumping-ddl-mysqldump-tables-stored-procedures-events-triggers-separately/).

## Warranty
None. Use responsibly, because I take none for any problems this script may cause.
#!/bin/sh
# Copy remote database files to local database directory.
# Uses Percona XtraBackup 2.4, requires package 'percona-xtrabackup-24' installed remotely and locally.
# IMPORTANT: this script must run as the 'root' user, since it needs to reload database files.
# IMPORTANT: this script requires an SSH key with the 'root' user
# to access the remote server passwordless.
# WARNING: this script will create an exact replica of the remote database locally,
# this includes all databases/tables/triggers/views/users/etc.
# Any modified local data since last copy WILL BE PERMANENTLY LOST.
# WARNING: this script requires both the remote and local servers to have enough
# free disk space for the backup files (a copy of the full database).
# WARNING: this script will stop and start mysql on the local server.

# A remote directory used to store the backup files.
REMOTE_BACKUP_PATH="/var/lib/percona/"
# A local directory used to store the backup files,
# do not empty this directory for optimal rsync functionality.
LOCAL_BACKUP_PATH="/var/lib/percona/"
# The local directory that stores the database files,
# this path will be overwritten with the backup.
LOCAL_MYSQL_PATH="/var/lib/mysql/"
# Required remote config file specifying mysql user and credentials to use,
# to avoid passing passwords via command line, ensure user has proper privileges by running:
# "GRANT RELOAD, LOCK TABLES, PROCESS, REPLICATION CLIENT ON *.* TO  'user'@'localhost';".
MYSQL_CONFIG_FILE="/root/.xtrabkpuser.cnf"
# To debug with verbose logging set command-line argument '-d true'.
DEBUG=false

while getopts i:d: opt; do
    case $opt in
    i)
        REMOTE_IP=$OPTARG
        ;;
    d)
        DEBUG=$OPTARG
        ;;
    esac
done

if [ -z $REMOTE_IP ]; then
    printf "Must set valid remote IP address from which to copy database [-i]\n"
    exit 1
elif [ ! -d $LOCAL_MYSQL_PATH ]; then
    printf "Local database directory does not exist ($LOCAL_MYSQL_PATH)\n"
    exit 2
elif ! dpkg-query -W -f '${Status}' percona-xtrabackup-24 | grep -q 'install ok'; then
    printf "Required local package 'percona-xtrabackup-24' is not found\n"
    exit 3
else

    printf "\n+++++Run on $(date)\n"

    START_TIME=$(date +%s)

    if $DEBUG; then
        ssh -o StrictHostKeyChecking=no -T root@$REMOTE_IP <<ENDSSH
DEBIAN_FRONTEND=noninteractive
printf "\n\n+++++Checking if remote backup directory exists, creating if not ($REMOTE_BACKUP_PATH)...\n\n"
mkdir -p $REMOTE_BACKUP_PATH

printf "\n\n+++++Clearing out remote backup directory ($REMOTE_BACKUP_PATH)...\n\n"
rm -rf $REMOTE_BACKUP_PATH*
printf "\n\n+++++Generating backup of remote database...\n\n"
xtrabackup --defaults-extra-file=$MYSQL_CONFIG_FILE --backup --target-dir=$REMOTE_BACKUP_PATH
exit
ENDSSH
    else
        ssh -o StrictHostKeyChecking=no -T root@$REMOTE_IP <<ENDSSH >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive
mkdir -p $REMOTE_BACKUP_PATH
rm -rf $REMOTE_BACKUP_PATH*
xtrabackup --defaults-extra-file=$MYSQL_CONFIG_FILE --backup --target-dir=$REMOTE_BACKUP_PATH
exit
ENDSSH
    fi

    if $DEBUG; then printf "\n\n+++++Checking if local backup directory exists, creating if not ($LOCAL_BACKUP_PATH)...\n\n"; fi
    mkdir -p $LOCAL_BACKUP_PATH

    if $DEBUG; then printf "\n\n+++++Copying backup files to local server...\n\n"; fi
    # After testing various combinations of compression (xbstream, tar, gzip) a plain rsync performed best.
    rsync -rt -e "ssh -o StrictHostKeyChecking=no" root@$REMOTE_IP:$REMOTE_BACKUP_PATH $LOCAL_BACKUP_PATH

    if $DEBUG; then
        printf "\n\n+++++Run prepare, first run makes files point-in-time consistent...\n\n"
        xtrabackup --prepare --target-dir=$LOCAL_BACKUP_PATH
    else
        xtrabackup --prepare --target-dir=$LOCAL_BACKUP_PATH >/dev/null 2>&1
    fi

    if $DEBUG; then
        printf "\n\n+++++Run prepare, second run creates fresh InnoDB log files...\n\n"
        xtrabackup --prepare --target-dir=$LOCAL_BACKUP_PATH
    else
        xtrabackup --prepare --target-dir=$LOCAL_BACKUP_PATH >/dev/null 2>&1
    fi

    if $DEBUG; then printf "\n\n+++++Shutting down mysql...\n\n"; fi
    service mysql stop

    if $DEBUG; then printf "\n\n+++++Clearing out local database directory ($LOCAL_MYSQL_PATH)...\n\n"; fi
    rm -rf $LOCAL_MYSQL_PATH*

    if $DEBUG; then
        printf "\n\n+++++Copying backup files to database directory...\n\n"
        xtrabackup --copy-back --target-dir=$LOCAL_BACKUP_PATH
    else
        xtrabackup --copy-back --target-dir=$LOCAL_BACKUP_PATH >/dev/null 2>&1
    fi

    if $DEBUG; then printf "\n\n+++++Updating file ownership in database directory...\n\n"; fi
    chown -R mysql:mysql $LOCAL_MYSQL_PATH

    if $DEBUG; then printf "\n\n+++++Starting mysql...\n\n"; fi
    service mysql start

    END_TIME=$(date +%s)
    RUN_TIME=$(expr $END_TIME - $START_TIME)

    if $DEBUG; then printf "\n\n+++++Done, execution took: $RUN_TIME seconds\n\n"; fi

fi

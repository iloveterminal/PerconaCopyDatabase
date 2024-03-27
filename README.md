# Percona Copy Database

A shell script that copies a remote MySQL or MariaDB database to the local database from which server the script executes using [Percona XtraBackup 2.4](https://www.percona.com/doc/percona-xtrabackup/2.4/index.html). It can be used, for example, to copy a production database to staging.

## Requirements

Install:

- [percona-xtrabackup-24](https://www.percona.com/doc/percona-xtrabackup/2.4/index.html)
- rsync
- ssh
- dpkg
- grep
- mysql

## Installation

First ensure that Percona XtraBackup 2.4 is installed on both the remote and local database servers by running the following (assuming any Debian distribution):

```shell
sudo apt-cache policy percona-xtrabackup-24;
wget https://repo.percona.com/apt/percona-release_0.1-4.$(lsb_release -sc)_all.deb;
sudo dpkg -i percona-release_0.1-4.$(lsb_release -sc)_all.deb;
sudo rm percona-release_0.1-4.$(lsb_release -sc)_all.deb;
sudo apt-get update;
sudo apt-get install percona-xtrabackup-24;
sudo apt-cache policy percona-xtrabackup-24;
```

The script requires a MySQL user on the remote database which can be created with the following: 
```SQL
CREATE USER 'xtrabkpuser'@'localhost' IDENTIFIED BY '[PASSWORD]';
GRANT RELOAD, LOCK TABLES, PROCESS, REPLICATION CLIENT ON *.* TO  'xtrabkpuser'@'localhost';
FLUSH PRIVILEGES;
```

Once this is done, log in as the 'root' user on the remote server and create a MySQL config file for the above user in `/root/.xtrabkpuser.cnf` with the contents:
```
[xtrabackup]
user=xtrabkpuser
password=[PASSWORD]
```

Ensure this config has the proper secure permissions with:

 `chmod 600 /root/.xtrabkpuser.cnf;`

You can log out of the remote server now. Log in as the 'root' user on the local server to which you would like to copy the remote database, and create a 'root' user SSH key to the remote server. First check if a public key has already been generated for this server. To do this, run `ls -la ~/.ssh/`. If you see a `.pub` file, key-gen has already been run. DO NOT run it again, you will wipe all current keys. If a `.pub` file does not exist, run `ssh-keygen;`.

Now run the following:

`ssh-copy-id -i ~/.ssh/id_rsa.pub [REMOTE_DB_IP];`

Test with:

`ssh root@[REMOTE_DB_IP];`

Now clone the `percona-copy-database.sh` script from this repository into `/usr/local/bin/`. Modify the script's permissions to make it executable:

 `chmod 744 /usr/local/bin/percona-copy-database.sh;`

Now create an easy access symbolic link via:

`ln -s /usr/local/bin/percona-copy-database.sh percona-bckp;`

Please read through and understand the script and all warnings fully before executing it to avoid any costly mistakes, and always make a database backup before the first run of the script. This script must run as the 'root' user, since it needs to reload database files. To test the script manually in debug mode with verbose logging enabled, just pass in an additional argument `-d true`, so the full command would be `percona-bckp -i [REMOTE_DB_IP] -d true >> /var/log/percona-bckp.log 2>&1;`. Inspect the log and make sure there were no errors, also run some queries on the local database to make sure everything runs as expected. After you are done testing, you can add the script to the local 'root' user's crontab via: `crontab -e -u root;` to run at the desired frequency with the production command (minimal logging):

`percona-bckp -i [REMOTE_DB_IP] >> /var/log/percona-bckp.log 2>&1;`
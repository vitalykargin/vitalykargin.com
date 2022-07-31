#!/bin/bash

# Variables ##########################################

DBHost=127.0.0.1
DBName=zabbix
DBUser=zabbix
DBPassword=JX62fh83fBj4*dwk
Port=80
FQDN=zabbix.corp.lan

# PostgreSQL ##########################################

sudo yum -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo yum -y install postgresql14 postgresql14-server

sudo chown -R postgres:postgres /data
sudo chmod 700 /data

UNIT='postgresql-14.service'
DIR="/etc/systemd/system/${UNIT}.d"
sudo mkdir $DIR
echo -e "[Service]\nEnvironment=PGDATA=/data/pgsql/14/data" | sudo tee -a ${DIR}/override.conf
sudo systemctl daemon-reload

sudo /usr/pgsql-14/bin/postgresql-14-setup initdb
sudo systemctl enable --now postgresql-14

sudo -u postgres psql -c "show config_file;"
sudo -u postgres psql -c "show data_directory;"

# TimescaleDB ##########################################

sudo yum install -y yum-utils cmake gcc git python-devel postgresql14-devel openssl-devel krb5-devel redhat-rpm-config

find / -name "pg_config" 2>/dev/null
export PATH=$PATH:/usr/pgsql-14/bin

cd /tmp
git clone https://github.com/timescale/timescaledb.git
cd timescaledb
git checkout 2.6.0
./bootstrap
cd build && make
sudo make install

sudo sed -i "s/#shared_preload_libraries = ''/shared_preload_libraries = 'timescaledb'/g" /data/pgsql/14/data/postgresql.conf
sudo systemctl restart postgresql-14

# Zabbix ##########################################
sudo rpm -Uvh https://repo.zabbix.com/zabbix/6.2/rhel/9/x86_64/zabbix-release-6.2-2.el9.noarch.rpm
sudo yum install -y zabbix-server-pgsql zabbix-web-pgsql zabbix-nginx-conf zabbix-sql-scripts zabbix-selinux-policy zabbix-agent

sudo -u postgres createuser $DBUser
sudo -u postgres psql -c "ALTER USER $DBUser WITH PASSWORD '$DBPassword';"
sudo -u postgres createdb -O $DBUser $DBName
echo "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;" | sudo -u postgres psql $DBUser
echo "\dx;" | sudo -u postgres psql $DBUser

cd /usr/share/doc/zabbix-sql-scripts/postgresql/
zcat server.sql.gz | sudo -u $DBUser psql $DBUser
cat timescaledb.sql | sudo -u $DBUser psql $DBUser

# echo "host    zabbix          zabbix          127.0.0.1/32            md5" >> /data/pgsql/14/data/pg_hba.conf
echo "host    $DBUser          $DBUser          127.0.0.1/32            md5" | sudo tee -a /data/pgsql/14/data/pg_hba.conf
sudo systemctl restart postgresql-14

sudo sed -i "s/# DBHost=localhost/DBHost=$DBHost/g" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/DBName=zabbix/DBName=$DBName/g" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/DBUser=zabbix/DBUser=$DBUser/g" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/# DBPassword=/DBPassword=$DBPassword/g" /etc/zabbix/zabbix_server.conf

sudo sed -i "s/#        listen          8080;/        listen          $Port;/g" /etc/nginx/conf.d/zabbix.conf
sudo sed -i "s/#        server_name     example.com;/        server_name     $FQDN;/g" /etc/nginx/conf.d/zabbix.conf

sudo systemctl restart zabbix-server zabbix-agent nginx php-fpm
sudo systemctl enable --now zabbix-server zabbix-agent nginx php-fpm

# Firewall ##########################################
sudo firewall-cmd --zone=public --add-port=80/tcp --permanent
sudo firewall-cmd --zone=public --add-port=443/tcp --permanent
sudo firewall-cmd --reload
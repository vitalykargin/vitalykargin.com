#!/bin/bash

# Variables ##########################################

DBHost=127.0.0.1
DBName=zabbix
DBUser=zabbix
DBPassword=JX62fh83fBj4*dwk
Port=80
FQDN=zabbix.corp.lan

# PostgreSQL ##########################################

yum -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
yum -y install postgresql14 postgresql14-server

chown -R postgres:postgres /data
chmod 700 /data

UNIT='postgresql-14.service'
DIR="/etc/systemd/system/${UNIT}.d"
mkdir $DIR
echo -e "[Service]\nEnvironment=PGDATA=/data/pgsql/14/data" > ${DIR}/override.conf
systemctl daemon-reload

/usr/pgsql-14/bin/postgresql-14-setup initdb
systemctl enable --now postgresql-14

sudo -u postgres psql -c "show config_file;"
sudo -u postgres psql -c "show data_directory;"

# TimescaleDB ##########################################

yum install -y yum-utils cmake gcc git python-devel postgresql14-devel openssl-devel krb5-devel redhat-rpm-config

find / -name "pg_config"
export PATH=$PATH:/usr/pgsql-14/bin

cd /tmp
git clone https://github.com/timescale/timescaledb.git
cd timescaledb
git checkout 2.6.0
./bootstrap
cd build && make
make install

sed -i "s/#shared_preload_libraries = ''/shared_preload_libraries = 'timescaledb'/g" /data/pgsql/14/data/postgresql.conf
systemctl retart postgresql-14

# Zabbix ##########################################
rpm -Uvh https://repo.zabbix.com/zabbix/6.2/rhel/9/x86_64/zabbix-release-6.2-2.el9.noarch.rpm
yum install -y zabbix-server-pgsql zabbix-web-pgsql zabbix-nginx-conf zabbix-sql-scripts zabbix-selinux-policy zabbix-agent

sudo -u postgres createuser --pwprompt zabbix
sudo -u postgres createdb -O zabbix zabbix
echo "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;" | sudo -u postgres psql zabbix
echo "\dx;" | sudo -u postgres psql zabbix

cd /usr/share/doc/zabbix-sql-scripts/postgresql/
zcat server.sql.gz | sudo -u zabbix psql zabbix
cat timescaledb.sql | sudo -u zabbix psql zabbix

echo "host    zabbix          zabbix          127.0.0.1/32            md5" >> /data/pgsql/14/data/pg_hba.conf
systemctl restart postgresql-14

DBHost=127.0.0.1
DBName=zabbix
DBUser=zabbix
DBPassword=zabbixpasswd
sed -i "s/# DBHost=localhost/DBHost=$DBHost/g" /etc/zabbix/zabbix_server.conf
sed -i "s/DBName=zabbix/DBName=$DBHost/g" /etc/zabbix/zabbix_server.conf
sed -i "s/DBUser=zabbix/DBUser=$DBHost/g" /etc/zabbix/zabbix_server.conf
sed -i "s/# DBPassword=/DBPassword=$DBHost/g" /etc/zabbix/zabbix_server.conf

Port=80
FQDN=zabbix.cloud.kodeks.ru
sed -i "s/#        listen          8080;/        listen          $Port;/g" /etc/nginx/conf.d/zabbix.conf
sed -i "s/#        server_name     example.com;/        server_name     $FQDN;/g" /etc/nginx/conf.d/zabbix.conf

systemctl restart zabbix-server zabbix-agent nginx php-fpm
systemctl enable --now zabbix-server zabbix-agent nginx php-fpm

# Firewall ##########################################
firewall-cmd --zone=public --add-port=80/tcp --permanent
firewall-cmd --zone=public --add-port=443/tcp --permanent
firewall-cmd --reload
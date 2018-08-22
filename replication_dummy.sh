#!/bin/bash
# ========================================================= #
#     Install SERVER1: ./script.sh mysql1
#     Install SERVER2: ./script.sh mysql2
#     Replication    : ./script.sh replication

#DEFINE VARIABLES
DB=classicmodels
BACKUP_DB="/home/backup-$(date +"%Y%m%d%H%M%S").sql"
USER=root
USER2=replicator
PASS=root
SERVER1="10.8.2.34" 
SERVER2="10.8.2.38"
PASSWORD="b57ebE61"

q1="GRANT ALL PRIVILEGES ON *.* TO '$USER'@'$SERVER1' IDENTIFIED BY '$PASS' WITH GRANT OPTION;"
q2="CREATE USER '$USER2';"
q3="GRANT ALL ON *.* TO '$USER2'@'%' IDENTIFIED BY '$PASS' WITH GRANT OPTION;"
q4='FLUSH PRIVILEGES;'


case $1 in

    'mysql1')
#MYSQL1 SERVER INSTALL AND EDIT THE CONF FILE

sed -i "s/.*bind-address.*/#bind-address/" /etc/mysql/my.cnf
sed -i "s/.*#server-id.*/server-id/" /etc/mysql/my.cnf
sed -i 's/.*server-id.*/server-id = 4/' /etc/mysql/my.cnf
sed -i '/log_bin/s/^#//g' /etc/mysql/my.cnf 
sed -i "s/.*#binlog_do_db.*/binlog_do_db/" /etc/mysql/my.cnf
sed -i 's/.*binlog_do_db.*/binlog_do_db = '$DB'/' /etc/mysql/my.cnf
sed -i.backup '112 a\events' /etc/mysql/my.cnf
sed -i.backup '113 a\ignore-table = mysql.events' /etc/mysql/my.cnf
sudo service mysql restart
sudo apt-get install sshpass


#CREATE USER AND GIVE THE PRIVILEGES
mysql "-u$USER" "-p$PASS" -e "
CREATE USER '$USER2'@'%' IDENTIFIED BY '$PASS';
GRANT ALL PRIVILEGES ON *.* TO '$USER2'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;"

     
#GRANT REPLICATION ON MYSQL1 AND LOCK THE DB
mysql "-u$USER" "-p$PASS" -e "
GRANT REPLICATION SLAVE ON *.* TO '$USER2'@'%';
FLUSH TABLES WITH READ LOCK;"


mysqldump "-u$USER" "-p$PASS" $DB > $BACKUP_DB

#READING MASTER STATUS AND TAKING LOG FILE AND POS VARIABLES
STATUS1=$(mysql "-u$USER" "-p$PASS" -ANe "SHOW MASTER STATUS;" | awk '{print $1 " " $2}')
LOG_FILE1=$(echo $STATUS1 | cut -f1 -d ' ')
LOG_POS1=$(echo $STATUS1 | cut -f2 -d ' ')
echo {$LOG_FILE1} {$LOG_POS1}

 ;;
            *)   
      echo "Usage: $0 { mysql1 | mysql2 | replication }"
;;
esac

case $2 in
    
    'mysql2')
    
sshpass "-p$PASSWORD" ssh -o StrictHostKeyChecking=no root@$SERVER2 "sudo apt-get update
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password password root'
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password root'
sudo apt-get -y install mysql-server

    
sed -i 's/.*bind-address.*/#bind-address/' /etc/mysql/my.cnf
sed -i 's/y.*#server-id.*/server-id/' /etc/mysql/my.cnf
sed -i 's/.*server-id.*/server-id = 1/' /etc/mysql/my.cnf
sed -i '/log_bin/s/^#//g' /etc/mysql/my.cnf 
sed -i 's/.*#binlog_do_db.*/binlog_do_db/' /etc/mysql/my.cnf
sed -i 's/.*binlog_do_db.*/binlog_do_db = '$DB'/' /etc/mysql/my.cnf
sed -i.backup '112 a\events' /etc/mysql/my.cnf
sed -i.backup '113 a\ignore-table = mysql.events' /etc/mysql/my.cnf
sudo service mysql restart"

       
sshpass "-p$PASSWORD" ssh -o StrictHostKeyChecking=no root@$SERVER2 mysql "-u$USER" "-p$PASS" <<EOF 
$q1
$q2
$q3
$q4
EOF

mysql -h $SERVER2 "-u$USER" "-p$PASS" -e "DROP DATABASE IF EXISTS $DB;CREATE DATABASE $DB;" #IF DB EXIST EKLE
scp $BACKUP_DB $SERVER2:$BACKUP_DB
mysql -h $SERVER2 "-u$USER" "-p$PASS" $DB < $BACKUP_DB  

mysql "-u$USER" "-p$PASS" "-h$SERVER2" -e "
GRANT REPLICATION SLAVE ON *.* TO '$USER2'@'%';
FLUSH TABLES WITH READ LOCK;"

       

#READING MASTER STATUS AND TAKING LOG FILE AND POS VARIABLES
STATUS2=$(mysql -h $SERVER2 "-u$USER" "-p$PASS" -ANe "SHOW MASTER STATUS;" | awk '{print $1 " " $2}')
LOG_FILE2=$(echo $STATUS2 | cut -f1 -d ' ')
LOG_POS2=$(echo $STATUS2 | cut -f2 -d ' ')
echo {$LOG_FILE2} {$LOG_POS2}

;;
            *)   
      echo "Usage: $0 { mysql1 | mysql2 | replication }"
;;
esac

case $3 in
    'replication')

#SETTING UP SERVER1 REPLICATION
mysql "-u$USER" "-p$PASS" -e "
STOP SLAVE;
CHANGE MASTER TO MASTER_HOST='$SERVER2',MASTER_USER='$USER2',MASTER_PASSWORD='$PASS',MASTER_LOG_FILE='$LOG_FILE2',MASTER_LOG_POS=$LOG_POS2;
START SLAVE;"


 mysql -h $SERVER2 "-u$USER" "-p$PASS" -e "
 STOP SLAVE;
CHANGE MASTER TO MASTER_HOST='$SERVER1',MASTER_USER='$USER2',MASTER_PASSWORD='$PASS',MASTER_LOG_FILE='$LOG_FILE1',MASTER_LOG_POS=$LOG_POS1;
START SLAVE;"

     
              ;;
            *)   
      echo "Usage: $0 { mysql1 | mysql2 | replication }"
;;
esac


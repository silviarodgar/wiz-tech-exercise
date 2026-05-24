#!/bin/bash
set -e
exec > >(tee /var/log/userdata.log) 2>&1

echo "=== Installing dependencies ==="
apt-get update -y
apt-get install -y gnupg curl awscli

echo "=== Installing MongoDB 5.0 (intentionally outdated — EOL Oct 2024) ==="
curl -fsSL https://www.mongodb.org/static/pgp/server-5.0.asc | apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/5.0 multiverse" \
  | tee /etc/apt/sources.list.d/mongodb-org-5.0.list
apt-get update -y
apt-get install -y mongodb-org=5.0.24 mongodb-org-server=5.0.24 \
  mongodb-org-shell=5.0.24 mongodb-org-mongos=5.0.24 mongodb-org-tools=5.0.24

echo "=== Configuring MongoDB ==="
sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf

cat >> /etc/mongod.conf << 'MONGOCNF'
security:
  authorization: enabled
MONGOCNF

systemctl enable mongod
systemctl start mongod
sleep 5

echo "=== Creating MongoDB users ==="
mongo admin --eval 'db.createUser({user:"admin",pwd:"wiz2026",roles:[{role:"userAdminAnyDatabase",db:"admin"},"readWriteAnyDatabase"]})'

mongo -u admin -p wiz2026 --authenticationDatabase admin go-mongodb --eval 'db.createUser({user:"tasky",pwd:"wiz2026",roles:[{role:"readWrite",db:"go-mongodb"}]})'

echo "=== Setting up daily MongoDB backup to S3 ==="
cat > /usr/local/bin/mongodb-backup.sh << 'BACKUP'
#!/bin/bash
set -e
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/mongodb-backup-$TIMESTAMP"
BUCKET="${s3_bucket_name}"

mongodump \
  --username admin \
  --password wiz2026 \
  --authenticationDatabase admin \
  --out "$BACKUP_DIR"

tar -czf "/tmp/mongodb-backup-$TIMESTAMP.tar.gz" -C /tmp "mongodb-backup-$TIMESTAMP"

aws s3 cp "/tmp/mongodb-backup-$TIMESTAMP.tar.gz" \
  "s3://$BUCKET/backups/mongodb-backup-$TIMESTAMP.tar.gz" \
  --region ${aws_region}

rm -rf "$BACKUP_DIR" "/tmp/mongodb-backup-$TIMESTAMP.tar.gz"
echo "Backup completed: mongodb-backup-$TIMESTAMP.tar.gz"
BACKUP

chmod +x /usr/local/bin/mongodb-backup.sh

echo "0 2 * * * root /usr/local/bin/mongodb-backup.sh >> /var/log/mongodb-backup.log 2>&1" \
  > /etc/cron.d/mongodb-backup

echo "=== Setup complete ==="

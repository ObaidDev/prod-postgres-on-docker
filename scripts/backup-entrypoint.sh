#!/bin/bash
set -e

# Use the mounted volume which should be writable
CONFIG_FILE="/var/lib/pgbackrest/pgbackrest.conf"

# Generate pgBackRest config from environment variables
echo "Generating pgBackRest configuration..."
cat > $CONFIG_FILE <<EOF
[global]
repo1-type=s3
repo1-s3-bucket=${S3_BUCKET_NAME}
repo1-s3-region=${AWS_REGION:-us-east-1}
repo1-s3-endpoint=${S3_ENDPOINT:-s3.amazonaws.com}
repo1-path=${S3_BACKUP_PATH:-/pgbackrest}
repo1-retention-full=${BACKUP_RETENTION_FULL:-7}
process-max=${BACKUP_PROCESS_MAX:-4}
log-level-console=info
start-fast=y
delta=y

[${STANZA_NAME}]
pg1-path=/var/lib/postgresql/data
pg1-host=${POSTGRES_HOST}
pg1-host-user=postgres
pg1-port=5432
EOF

# Set config file location for pgbackrest
export PGBACKREST_CONFIG=$CONFIG_FILE

echo "Configuration created at $CONFIG_FILE"

echo "Waiting for PostgreSQL to be ready..."
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
  if timeout 2 bash -c "echo > /dev/tcp/$POSTGRES_HOST/5432" 2>/dev/null; then
    echo "PostgreSQL is ready!"
    break
  fi
  attempt=$((attempt + 1))
  echo "Attempt $attempt/$max_attempts: Waiting for PostgreSQL..."
  sleep 5
done

if [ $attempt -ge $max_attempts ]; then
  echo "PostgreSQL did not become ready in time, but continuing anyway..."
fi

# Archive WAL files from shared directory
echo "Archiving existing WAL files..."
for wal_file in /var/lib/postgresql/wal-archive/*; do
  if [ -f "$wal_file" ]; then
    filename=$(basename "$wal_file")
    echo "Archiving $filename..."
    PGBACKREST_REPO1_S3_KEY=$AWS_ACCESS_KEY_ID \
    PGBACKREST_REPO1_S3_KEY_SECRET=$AWS_SECRET_ACCESS_KEY \
    pgbackrest --stanza=$STANZA_NAME archive-push "$wal_file" && rm -f "$wal_file"
  fi
done

echo "Creating stanza..."
PGBACKREST_REPO1_S3_KEY=$AWS_ACCESS_KEY_ID \
PGBACKREST_REPO1_S3_KEY_SECRET=$AWS_SECRET_ACCESS_KEY \
pgbackrest --stanza=$STANZA_NAME stanza-create || echo "Stanza already exists"

echo "Running initial backup..."
PGBACKREST_REPO1_S3_KEY=$AWS_ACCESS_KEY_ID \
PGBACKREST_REPO1_S3_KEY_SECRET=$AWS_SECRET_ACCESS_KEY \
pgbackrest --stanza=$STANZA_NAME --type=full backup

echo "Starting backup scheduler..."
while true; do
  current_hour=$(date +%H)
  current_day=$(date +%u)
  
  # Archive any pending WAL files every loop
  for wal_file in /var/lib/postgresql/wal-archive/*; do
    if [ -f "$wal_file" ]; then
      filename=$(basename "$wal_file")
      PGBACKREST_REPO1_S3_KEY=$AWS_ACCESS_KEY_ID \
      PGBACKREST_REPO1_S3_KEY_SECRET=$AWS_SECRET_ACCESS_KEY \
      pgbackrest --stanza=$STANZA_NAME archive-push "$wal_file" 2>/dev/null && rm -f "$wal_file"
    fi
  done
  
  # Full backup on Sunday at 2 AM
  if [ "$current_day" = "7" ] && [ "$current_hour" = "02" ]; then
    echo "Running weekly full backup..."
    PGBACKREST_REPO1_S3_KEY=$AWS_ACCESS_KEY_ID \
    PGBACKREST_REPO1_S3_KEY_SECRET=$AWS_SECRET_ACCESS_KEY \
    pgbackrest --stanza=$STANZA_NAME --type=full backup
  # Differential backup daily at 2 AM (except Sunday)
  elif [ "$current_day" != "7" ] && [ "$current_hour" = "02" ]; then
    echo "Running daily differential backup..."
    PGBACKREST_REPO1_S3_KEY=$AWS_ACCESS_KEY_ID \
    PGBACKREST_REPO1_S3_KEY_SECRET=$AWS_SECRET_ACCESS_KEY \
    pgbackrest --stanza=$STANZA_NAME --type=diff backup
  fi
  
  sleep 3600  # Check every hour
done
# Quick Setup Guide

## 1. Create Directory Structure

```bash
mkdir -p postgres/data postgres/wal-archive pgbackrest-repo scripts
chmod 700 postgres/data
chmod 777 postgres/wal-archive pgbackrest-repo
```

## 2. Create Backup Script

Create `scripts/backup-entrypoint.sh` (see artifact) and make it executable:
```bash
chmod +x scripts/backup-entrypoint.sh
```

## 3. Configure Environment

Create `.env` file:
```bash
POSTGRES_DB=appdb
POSTGRES_USER=appuser
POSTGRES_PASSWORD=your_secure_password

AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret
AWS_REGION=us-east-1
S3_BUCKET_NAME=your-bucket-name
S3_ENDPOINT=s3.amazonaws.com
S3_BACKUP_PATH=/pgbackrest

BACKUP_RETENTION_FULL=7
BACKUP_PROCESS_MAX=4
```

**Note:** The pgBackRest configuration is now generated automatically from these environment variables. You don't need to create a separate config file!

## 4. Create S3 Bucket

```bash
aws s3 mb s3://your-postgres-backups --region us-east-1
```

## 5. Start Services

```bash
docker-compose up -d
```

## 6. Verify Backups

```bash
# Check backup status
docker exec pgbackrest pgbackrest --stanza=main info

# Manual backup
docker exec pgbackrest pgbackrest --stanza=main --type=full backup
```

## Restore Example

```bash
# Stop PostgreSQL
docker-compose stop postgres

# Restore from backup
docker exec pgbackrest pgbackrest --stanza=main --delta restore

# Start PostgreSQL
docker-compose start postgres
```

## Backup Schedule
- **Full backup**: Every Sunday at 2 AM
- **Differential backup**: Daily at 2 AM (except Sunday)
- **Retention**: 7 full backups
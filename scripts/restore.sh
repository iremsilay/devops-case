
#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="devops-case"
POD="mongodb-0"

BACKUP_DIR="${1:-}"

if [[ -z "$BACKUP_DIR" || ! -d "$BACKUP_DIR" ]]; then
  echo "Usage: ./scripts/restore.sh backups/<timestamp>"
  exit 1
fi

if [[ ! -f "$BACKUP_DIR/SHA256SUMS" ]]; then
  echo "ERROR: Checksum file not found."
  exit 1
fi

echo "Verifying backup integrity..."

(
  cd "$BACKUP_DIR"
  shasum -a 256 -c SHA256SUMS
)

echo
echo "WARNING: Existing collections in the selected databases"
echo "will be dropped and restored from this backup."
echo
echo "Backup directory: $BACKUP_DIR"

read -r -p "Type RESTORE to continue: " confirmation

if [[ "$confirmation" != "RESTORE" ]]; then
  echo "Restore cancelled."
  exit 1
fi

restore_database() {
  local database="$1"
  local archive="$BACKUP_DIR/$database.archive"

  if [[ ! -s "$archive" ]]; then
    echo "ERROR: Missing or empty archive: $archive" >&2
    exit 1
  fi

  echo "Restoring database: $database"

  kubectl exec -i -n "$NAMESPACE" "$POD" -- \
    sh -c '
      exec mongorestore \
        --username="$MONGO_INITDB_ROOT_USERNAME" \
        --password="$MONGO_INITDB_ROOT_PASSWORD" \
        --authenticationDatabase=admin \
        --archive \
        --drop \
        --nsInclude="$1.*"
    ' sh "$database" < "$archive"

  echo "Restore completed for: $database"
}

restore_database "sample_training"
restore_database "github_etl"

echo "Restore completed successfully."

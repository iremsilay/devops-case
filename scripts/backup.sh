
#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="devops-case"
POD="mongodb-0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="$ROOT_DIR/backups/$TIMESTAMP"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

backup_database() {
  local database="$1"
  local output="$BACKUP_DIR/$database.archive"
  local temporary="$output.partial"

  echo "Backing up database: $database"

  if ! kubectl exec -n "$NAMESPACE" "$POD" -- \
    sh -c '
      exec mongodump \
        --username="$MONGO_INITDB_ROOT_USERNAME" \
        --password="$MONGO_INITDB_ROOT_PASSWORD" \
        --authenticationDatabase=admin \
        --db="$1" \
        --archive
    ' sh "$database" > "$temporary"; then
    rm -f "$temporary"
    echo "ERROR: Backup failed for $database" >&2
    exit 1
  fi

  if [[ ! -s "$temporary" ]]; then
    rm -f "$temporary"
    echo "ERROR: Empty backup for $database" >&2
    exit 1
  fi

  chmod 600 "$temporary"
  mv "$temporary" "$output"

  echo "Backup saved: $output"
}

backup_database "sample_training"
backup_database "github_etl"

(
  cd "$BACKUP_DIR"
  shasum -a 256 sample_training.archive github_etl.archive \
    > SHA256SUMS
)

chmod 600 "$BACKUP_DIR/SHA256SUMS"

echo "Backup completed successfully."
echo "Directory: $BACKUP_DIR"

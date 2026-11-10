
#!/usr/bin/env bash

set -euo pipefail

BACKUP_DIR="${1:-}"

if [[ -z "$BACKUP_DIR" || ! -d "$BACKUP_DIR" ]]; then
  echo "Usage: ./scripts/verify-backup.sh backups/<timestamp>"
  exit 1
fi

BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd)"

for file in SHA256SUMS sample_training.archive github_etl.archive; do
  if [[ ! -s "$BACKUP_DIR/$file" ]]; then
    echo "ERROR: Missing or empty file: $file" >&2
    exit 1
  fi
done

echo "Step 1: Verifying backup checksums..."

(
  cd "$BACKUP_DIR"
  shasum -a 256 -c SHA256SUMS
)

CONTAINER="devops-backup-verify-$$"

cleanup() {
  echo "Cleaning up temporary MongoDB..."
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo "Step 2: Starting isolated MongoDB..."

docker run -d \
  --name "$CONTAINER" \
  --network none \
  mongo:7 >/dev/null

echo "Waiting for MongoDB..."

ready=false

for attempt in $(seq 1 60); do
  if docker exec "$CONTAINER" \
    mongosh --quiet --eval 'db.adminCommand({ping: 1}).ok' \
    2>/dev/null | grep -qx '1'; then
    ready=true
    break
  fi

  sleep 2
done

if [[ "$ready" != "true" ]]; then
  echo "ERROR: Temporary MongoDB did not become ready." >&2
  exit 1
fi

echo "Step 3: Restoring archives into isolated MongoDB..."

for database in sample_training github_etl; do
  echo "Restoring: $database"

  docker exec -i "$CONTAINER" \
    mongorestore \
      --archive \
      --nsInclude="$database.*" \
      --stopOnError \
      < "$BACKUP_DIR/$database.archive"
done

echo "Step 4: Checking restored data..."

docker exec "$CONTAINER" mongosh --quiet --eval '
  const sample = db.getSiblingDB("sample_training");
  const etl = db.getSiblingDB("github_etl");

  const sampleCollections = sample.getCollectionNames();
  const etlCollections = etl.getCollectionNames();

  print("sample_training collections: " + sampleCollections.join(", "));
  print("github_etl collections: " + etlCollections.join(", "));

  if (sampleCollections.length === 0 || etlCollections.length === 0) {
    print("FAIL: One or more databases contain no collections.");
    quit(1);
  }

  for (const name of sampleCollections) {
    const count = sample.getCollection(name).countDocuments({});
    print("sample_training." + name + ": " + count);

    if (count === 0) {
      print("FAIL: Empty collection detected.");
      quit(1);
    }
  }

  for (const name of etlCollections) {
    const count = etl.getCollection(name).countDocuments({});
    print("github_etl." + name + ": " + count);

    if (count === 0) {
      print("FAIL: Empty collection detected.");
      quit(1);
    }
  }

  print("PASS: Backup restored and verified successfully.");
'

echo "Backup verification completed successfully."

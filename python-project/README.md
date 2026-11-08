# Python ETL - GitHub to MongoDB

## Overview

This project implements a Python ETL (Extract, Transform, Load) process that retrieves public repository information from the GitHub REST API and stores it in MongoDB.

The ETL uses the GitHub repository ID as a unique identifier. Existing repositories are updated instead of creating duplicate records.

The script runs once, logs the results, and exits. It is designed to be scheduled hourly using a Kubernetes CronJob.

## Technologies

- Python 3.11
- Requests - GitHub API requests
- PyMongo - MongoDB operations
- MongoDB 7
- Docker

## How It Works

1. Reads configuration from environment variables.
2. Connects to MongoDB and verifies the connection.
3. Creates a unique index on `github_id`.
4. Fetches public repositories from the configured GitHub account, handling pagination.
5. Extracts relevant repository information.
6. Uses MongoDB `update_one()` with `upsert=True` to insert or update records.
7. Logs the number of repositories fetched, inserted, and updated.
8. Exits with code `0` on success or `1` on handled errors.

Repository data is stored in the `github_etl` database and `repositories` collection in the local example.

The ETL data is stored separately from the MERN application's employee records.

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `ATLAS_URI` | Yes | MongoDB connection URI |
| `MONGO_DB` | Yes | MongoDB database name |
| `MONGO_COLLECTION` | Yes | MongoDB collection name |
| `GITHUB_USERNAME` | Yes | GitHub username to retrieve public repositories from |
| `GITHUB_TOKEN` | No | Optional GitHub API token for authenticated requests |

Credentials and tokens must not be committed to Git or embedded in Docker images.

## Local Setup

### 1. Create a virtual environment

```bash
python3 -m venv .venv
source .venv/bin/activate
```

### 2. Install dependencies

```bash
python -m pip install -r requirements.txt
```

### 3. Configure environment variables

The following example assumes MongoDB is accessible locally on port 27017:

```bash
export ATLAS_URI="mongodb://127.0.0.1:27017"
export MONGO_DB="github_etl"
export MONGO_COLLECTION="repositories"
export GITHUB_USERNAME="iremsilay"
```

### 4. Run the ETL

```bash
python ETL.py
```

The script fetches repository data, updates MongoDB, prints execution logs, and exits.

## Docker

### Build the image

Run from the `python-project` directory:

```bash
docker build -t case-etl:1.0 .
```

### Run the container

The following command is intended for Docker Desktop with MongoDB exposed on the host's port 27017:

```bash
docker run --rm \
  --name case-etl \
  -e ATLAS_URI=mongodb://host.docker.internal:27017 \
  -e MONGO_DB=github_etl \
  -e MONGO_COLLECTION=repositories \
  -e GITHUB_USERNAME=iremsilay \
  case-etl:1.0
```

The container performs one ETL execution and exits. The `--rm` option removes the container after execution.

### Verify non-root execution

```bash
docker run --rm --entrypoint id case-etl:1.0
```

Verified output:

```text
uid=10001(appuser) gid=10001(appuser) groups=10001(appuser)
```

The application runs as a non-root user.

## Duplicate Prevention

The ETL uses the GitHub repository ID as a unique key.

```python
collection.create_index(
    [("github_id", ASCENDING)],
    unique=True,
)
```

Records are inserted or updated using:

```python
collection.update_one(
    {"github_id": document["github_id"]},
    {
        "$set": {
            **document,
            "last_synced_at": datetime.now(timezone.utc),
        }
    },
    upsert=True,
)
```

If a repository does not exist, MongoDB inserts a new document. If it already exists, the document is updated.

The unique index also prevents duplicate GitHub repository IDs at the database level.

## Verification Results

The ETL was tested locally and inside a Docker container on November 8, 2026.

| Test | Fetched | Inserted | Updated | MongoDB Count |
|---|---:|---:|---:|---:|
| First local execution | 3 | 3 | 0 | 3 |
| Second local execution | 3 | 0 | 3 | 3 |
| Docker execution | 3 | 0 | 3 | 3 |

The following repositories were processed:

- `iremsilay/calculator-project`
- `iremsilay/devops-case`
- `iremsilay/devops-case-study`

The second execution updated the existing documents without creating duplicates.

The `last_synced_at` field is refreshed during each successful upsert, so an existing record is counted as updated even when its GitHub metadata has not changed.

### Verify MongoDB records

```bash
docker exec devops-mongo mongosh --quiet --eval \
'db.getSiblingDB("github_etl").repositories.countDocuments({})'
```

Verified result:

```text
3
```

### Verify the unique index

```bash
docker exec devops-mongo mongosh --quiet --eval \
'db.getSiblingDB("github_etl").repositories.getIndexes()'
```

Verified index:

```javascript
{
  key: { github_id: 1 },
  name: 'github_id_1',
  unique: true
}
```

## Logging and Error Handling

The ETL prints timestamped logs to standard output, including:

- MongoDB connection status
- Number of repositories retrieved
- Inserted and updated repositories
- Execution summary
- API, database, or configuration errors

HTTP request failures and handled processing errors are logged. The script exits with a non-zero status when an error occurs.

Logs can be collected by Docker or Kubernetes.

## Kubernetes Scheduling

The ETL is designed to run as a Kubernetes CronJob.

The intended schedule is:

```yaml
schedule: "0 * * * *"
```

This runs the ETL once every hour.

The CronJob configuration, environment variables, and MongoDB connectivity will be defined during the Kubernetes deployment stage.

## Current Limitations

- The ETL retrieves public repositories belonging to one configured GitHub user.
- GitHub API rate limits apply, especially without an authentication token.
- Credentials and database configuration must be provided externally.
- Hourly Kubernetes scheduling has not yet been implemented.
- Automated testing and retry policies can be extended for production use.
- Existing documents are resynchronized, but repositories deleted from GitHub are not automatically removed from MongoDB.

The ETL is currently verified for manual local and Docker execution. Kubernetes deployment and scheduled execution are separate implementation steps.
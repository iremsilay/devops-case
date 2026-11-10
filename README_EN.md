# DEVOPS TECHNICAL CASE — MERN APPLICATION AND PYTHON ETL

## 1. ABOUT THE PROJECT

This project is a DevOps technical assessment focused on reviewing the provided MERN application and Python ETL workload for production readiness, improving critical issues and moving the components into a reproducible runtime environment.

The solution offers two execution paths: local validation with Docker Compose and deployment to a local Kubernetes cluster created with k3d on Docker Desktop. Kubernetes is the final orchestration environment. No public cloud infrastructure or publicly accessible production environment has been deployed.

The MERN interface supports creating, listing, updating and deleting employee records. A separate Python ETL application retrieves repository information for a specified GitHub user through the GitHub API and stores it in MongoDB. Subsequent ETL runs update existing repository records instead of creating another record with the same GitHub repository identifier.

The project also includes GitHub Actions CI, container image builds, controlled local deployment and rollback, MongoDB backup and restore, Kubernetes-based monitoring and Slack notifications.

This implementation is not presented as an exact equivalent of a production environment. Its security, availability and disaster recovery limitations are described at the end of this document.

Repository: `https://github.com/iremsilay/devops-case`

## 2. TECHNOLOGIES AND COMPONENTS

**Frontend:** React, JavaScript and Nginx. The React application is compiled during the Docker build. The resulting static content is served by Nginx on port 8080 in the final container.

**Backend:** Node.js 22, Express and the MongoDB driver. The HTTP API runs on port 5050. CRUD operations are available under `/record`, the liveness endpoint under `/healthcheck` and the MongoDB-aware readiness endpoint under `/healthcheck/ready`.

**Database:** MongoDB 7. MERN records are stored in the `records` collection of the `sample_training` database. GitHub ETL records are stored in the `repositories` collection of the `github_etl` database.

**ETL:** Python 3.11, Requests and PyMongo. It retrieves repository information from the GitHub API and performs upserts using a unique index on `github_id`.

**Containers and local environment:** Docker, Docker Compose, Docker Desktop and k3d.

**Orchestration:** Kubernetes Deployment, StatefulSet, Service, ConfigMap, Secret, Job and CronJob. MongoDB uses a PersistentVolumeClaim.

**CI and image distribution:** GitHub Actions, Docker Buildx and GitHub Container Registry (GHCR). Backend, frontend and ETL images are built and published to GHCR on pushes to the `main` branch.

**Monitoring:** Bash, Python, kubectl, Kubernetes CronJob, ConfigMap-based alert state and Slack Incoming Webhook.

**Backup and restore:** mongodump, mongorestore, shell scripts and SHA-256 checksum verification.

## 3. ARCHITECTURE AND TRAFFIC FLOW

Kubernetes namespace: `devops-case`.

**User requests follow this path in Kubernetes:**

User -> Browser -> Frontend NodePort Service (30080) -> Frontend Pod (Nginx, 8080) -> Nginx Reverse Proxy (`/api`) -> `case-backend` ClusterIP Service (5050) -> Backend Pod (Node.js, 5050) -> `mongodb-service` (Headless Service, 27017) -> MongoDB StatefulSet Pod (`mongodb-0`).

The frontend serves the React application's static files to the user's browser. Nginx forwards `/api` requests from the browser to the `case-backend` Service inside the cluster. For MongoDB operations, the backend connects to the MongoDB StatefulSet Pod through the headless `mongodb-service`.

The frontend NodePort Service is the application's entry point from outside the cluster. The backend ClusterIP Service and MongoDB headless Service are configured for internal cluster access only.

This architecture does not include an Ingress Controller or TLS termination (HTTPS). It serves plain HTTP directly through NodePort. Access from the local computer requires a suitable host port mapping in the k3d cluster configuration.

The Python ETL operates independently of user requests: `github-etl` CronJob -> ETL Job -> GitHub REST API -> MongoDB `github_etl.repositories` collection. The CronJob runs at the beginning of every hour in UTC (`0 * * * *`).

Monitoring is also independent: `monitoring-check` CronJob -> inspection of backend and ETL Kubernetes status -> alert state evaluation -> Slack webhook notification if needed. The CronJob runs every minute.

**Kubernetes Services:**

- `frontend`: NodePort, Service port 8080 and nodePort 30080; the only application Service intended for external access.
- `case-backend`: ClusterIP, port 5050; accessible within the cluster.
- `mongodb-service`: headless Service, port 27017; provides stable network identity and internal access for the MongoDB StatefulSet.

An architecture diagram will also be prepared in `docs/architecture.md`.

## 4. REPOSITORY STRUCTURE

`mern-project/client/`: React source code, Cypress tests, frontend Dockerfile and `nginx.conf`.

`mern-project/server/`: Express API, MongoDB connection management, health checks and backend Dockerfile.

`python-project/`: `ETL.py`, `requirements.txt`, ETL Dockerfile and ETL-specific documentation.

`monitoring/`: `check-health.sh`, `evaluate_etl.py` and monitoring Dockerfile.

`kubernetes/`: namespace, shared configuration and resource manifests for backend, frontend, MongoDB, ETL and monitoring.

`.github/workflows/ci.yml`: GitHub Actions validation, E2E testing and image build/publish process.

`scripts/deploy-local.sh`: local Kubernetes deployment using GHCR image tags with rollback on deployment failure.

`scripts/backup.sh`: archive backups of the `sample_training` and `github_etl` databases.

`scripts/restore.sh`: MongoDB restore with checksum verification and explicit confirmation.

`tests/test_etl_recovery.py`: unit tests for ETL failure and recovery analysis.

`docker-compose.yml`: local container environment and optional one-off ETL execution.

`.env.example`: example Docker Compose environment variables.

`docs/findings.md` and `docs/findings_en.md`: initial risks, applied improvements and scope boundaries.

`docs/backup-restore.md`: backup/restore runbook; actual measurements and evidence references will be added before submission.

`docs/screenshots/`: directory for required runtime evidence screenshots.

`TESLIM_KANITLARI.md` and `SUBMISSION_EVIDENCE.md`: descriptions of evidence screenshots.

`CASE_SONU_CEVAPLARI.md` and `CASE_END_ANSWERS.md`: answers to the final technical case questions.

Files excluded by Git, including `node_modules`, build outputs, virtual environments, actual `.env`/Secret files and the `backups/` directory, are not part of the source submission.

## 5. PREREQUISITES

**For local setup:**

- Git
- Docker Desktop and the Docker Compose plugin
- Docker Desktop must be running
- kubectl and k3d for the Kubernetes setup
- Internet access to retrieve GitHub repository information

Node.js 22 and npm are needed for local Node.js development and Cypress testing. Python 3.11 is suitable for running the ETL outside Docker or running unit tests locally.

The project has been validated on macOS with Docker Desktop. Commands use macOS/Linux shell syntax. Some utility commands may differ on other operating systems.

**First step:**

```bash
git clone https://github.com/iremsilay/devops-case.git
cd devops-case
```

## 6. QUICK START — DOCKER COMPOSE

Docker Compose is the simplest way to validate the full application in a local container network. It should not be considered the final deployment approach in place of Kubernetes.

### 6.1 Create the environment file

**From the project root:**

```bash
cp .env.example .env
```

**Values in `.env`:**

```dotenv
COMPOSE_MONGO_URI=mongodb://mongodb:27017
MONGO_DB=github_etl
MONGO_COLLECTION=repositories
GITHUB_USERNAME=your-github-username
GITHUB_TOKEN=
FRONTEND_PORT=8081
```

Replace `GITHUB_USERNAME` with the GitHub account to be tested. Public repository information can be retrieved without a token, subject to GitHub API rate limits. If a real token is required, keep it only in the local `.env` file or a secure secret mechanism. Do not commit it to Git.

### 6.2 Start the application

```bash
docker compose up -d --build
```

This starts MongoDB, the backend and the frontend. Compose evaluates service dependencies by waiting for the MongoDB health check and backend readiness. The ETL service does not start automatically because it is defined under a profile.

### 6.3 Check the services

```bash
docker compose ps
docker compose logs --tail=100 backend
docker compose logs --tail=100 frontend
```

Browser: `http://localhost:8081`

If `FRONTEND_PORT` is changed, use the corresponding browser port. Compose port mapping is bound only to the `127.0.0.1` interface.

**Check the API through the Nginx proxy:**

```bash
curl -i http://localhost:8081/api/healthcheck
curl -i http://localhost:8081/api/healthcheck/ready
```

Both endpoints should return HTTP 200 when healthy. The readiness response includes the value `READY`.

### 6.4 Run the ETL once

```bash
docker compose --profile etl run --rm etl
```

The job retrieves repository information, writes it to MongoDB and exits when complete. When run again, it updates records with the same `github_id` rather than inserting duplicates.

The ETL output reports `fetched`, `inserted`, `updated` and `unchanged` counts. This Compose command does not set up an hourly scheduler. Hourly scheduling is handled by the Kubernetes CronJob.

### 6.5 Cleanup

```bash
docker compose down
```

This stops the containers and networks while preserving the named MongoDB volume. `docker compose down -v` removes the database volume and should be used only when data loss is intentional.

## 7. KUBERNETES ENVIRONMENT AND INITIAL SETUP

The final test environment is the local k3d cluster named `devops-case`, running on Docker Desktop. The kubectl context is `k3d-devops-case` and the Kubernetes namespace is `devops-case`.

The procedure distinguishes initial setup of an empty cluster from updates to an existing running cluster. In particular, Secrets and the ConfigMap holding alert state should not be reapplied indiscriminately.

### 7.1 Check the cluster and context

```bash
k3d cluster list
kubectl config current-context
kubectl get nodes
```

The project's `deploy-local.sh` script is configured to run only with the `k3d-devops-case` context. Use the name `devops-case` when creating a new cluster. k3d host port mapping must be configured during cluster creation. For example, the frontend NodePort 30080 cannot be expected to work in a local browser without a corresponding host port mapping.

**Example for creating a new cluster (do not run against the existing cluster):**

```bash
k3d cluster create devops-case --port '127.0.0.1:8081:30080@loadbalancer'
```

This is an example command. Verify the actual port mapping of the existing cluster from its k3d configuration. Deleting and recreating an existing cluster may result in loss of MongoDB data.

### 7.2 Prepare the images

**The initial Kubernetes manifests in the repository use local Docker image tags:**

- `case-backend:1.0`
- `case-frontend:1.0`
- `case-etl:1.0`
- `case-monitoring:1.1`

**From the project root:**

```bash
docker build -t case-backend:1.0 ./mern-project/server
docker build -t case-frontend:1.0 ./mern-project/client
docker build -t case-etl:1.0 ./python-project
docker build -t case-monitoring:1.1 ./monitoring
```

**Import the images into the k3d cluster:**

```bash
k3d image import case-backend:1.0 case-frontend:1.0 case-etl:1.0 case-monitoring:1.1 -c devops-case
```

Local development and releases use two different image management approaches.

**Local development:** The default Kubernetes manifests in the repository use the `case-backend:1.0`, `case-frontend:1.0` and `case-etl:1.0` tags. Images are built in the local Docker environment and imported into the cluster using `k3d image import`. This speeds up development and initial setup tests.

**Release:** After successful checks, GitHub Actions publishes backend, frontend and ETL images to GHCR with a `sha-<commit-hash>` tag. `scripts/deploy-local.sh` uses the specified SHA-tagged images and updates the image references of running Kubernetes resources with `kubectl set image`.

The deployment script does not modify the manifest files. New image references are applied to existing Deployment and CronJob resources through the Kubernetes API. This means the default YAML files in the repository can retain their local image tags while the running cluster uses GHCR images.

The monitoring image is not managed by this release script and must be handled separately.

Reapplying Kubernetes manifests with `kubectl apply` may reset image references to their default local tags. Reapply manifests carefully after a release.

If images are not available in the cluster or cannot be pulled from GHCR, Pods may enter the `ImagePullBackOff` state.

### 7.3 Namespace and shared ConfigMap

```bash
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/configmap.yaml
```

The shared `app-config` ConfigMap contains the GitHub username and ETL collection settings. Update `GITHUB_USERNAME` if the account used for testing needs to change.

### 7.4 Prepare Kubernetes Secrets

Do not place actual passwords or connection URIs in the repository. The existing manifests depend on the following Secrets:

- `mongodb-auth`: initial username/password environment variables for the MongoDB root account and application users.
- `backend-mongo-uri`: `ATLAS_URI` key containing a connection URI for a backend user authorized to access `sample_training`.
- `etl-mongo-uri`: `ATLAS_URI` key containing a connection URI for an ETL user authorized to access `github_etl`.
- `monitoring-slack-webhook`: `SLACK_WEBHOOK_URL` key.

MongoDB application users are created by `init-mongo.js` during initialization. The script uses these variables:

`MONGO_BACKEND_USERNAME`, `MONGO_BACKEND_PASSWORD`,

`MONGO_ETL_USERNAME`, `MONGO_ETL_PASSWORD`.

The official MongoDB image also requires `MONGO_INITDB_ROOT_USERNAME` and `MONGO_INITDB_ROOT_PASSWORD` for the root account.

**Create a local environment file excluded from Git, then create the Secret using:**

```bash
kubectl create secret generic mongodb-auth -n devops-case --from-env-file=kubernetes/secrets/mongodb.env
```

**Architecture note:** In this project, Secrets are created manually from `.env` files that are not tracked by Git to set up the local Kubernetes environment. This approach was selected for local development and technical assessment.

In a real production environment, a centralized secret management solution such as AWS Secrets Manager, HashiCorp Vault or External Secrets Operator (ESO) should be used. These systems support controlled secret distribution, access management and rotation processes.

Automatic secret rotation has not been implemented. Updates to Secret values and the rollout of Pods that need to consume the new values must be managed separately.

This sample file must not be tracked by Git and must contain the six variables listed above. Use the same approach to securely create `backend-mongo-uri`, `etl-mongo-uri` and `monitoring-slack-webhook` Secrets with their respective keys. Passwords with special characters in MongoDB URIs may require URL encoding. Avoid exposing secrets in terminal output, screenshots or shell history.

**Important:** The existence of Secret objects alone does not guarantee correct authorization. Backend and ETL users are intended to access only their respective databases.

### 7.5 MongoDB initialization ConfigMap, StatefulSet and Service

**Load the ConfigMap that will create application users on the first initialization of an empty database:**

```bash
kubectl create configmap mongodb-init-script -n devops-case --from-file=init-mongo.js=kubernetes/mongodb/init-mongo.js
```

**Then run:**

```bash
kubectl apply -f kubernetes/mongodb/service.yaml
kubectl apply -f kubernetes/mongodb/statefulset.yaml
kubectl rollout status statefulset/mongodb -n devops-case --timeout=180s
```

MongoDB runs in the `mongodb-0` Pod and uses the `mongo-data` PVC. The initialization script runs only when the database storage is first initialized. Deploying again with an existing PVC does not recreate users. Changing a Secret does not necessarily update database user passwords automatically, so password rotation must be planned separately.

### 7.6 Frontend, backend and ETL resources

```bash
kubectl apply -f kubernetes/backend/service.yaml
kubectl apply -f kubernetes/backend/deployment.yaml
kubectl apply -f kubernetes/frontend/service.yaml
kubectl apply -f kubernetes/frontend/deployment.yaml
kubectl apply -f kubernetes/etl/cronjob.yaml
```

```bash
kubectl rollout status deployment/backend -n devops-case --timeout=180s
kubectl rollout status deployment/frontend -n devops-case --timeout=180s
kubectl get deployments,services,cronjobs -n devops-case
```

The Kubernetes manifests define one replica each for the backend and frontend and a single MongoDB StatefulSet replica. This is not a high-availability architecture.

### 7.7 Monitoring resources

Monitoring requires a ServiceAccount, restricted RBAC, a script ConfigMap, a state ConfigMap and a CronJob.

**For initial setup:**

```bash
kubectl apply -f kubernetes/monitoring/serviceaccount.yaml
kubectl apply -f kubernetes/monitoring/role.yaml
kubectl apply -f kubernetes/monitoring/rolebinding.yaml
kubectl apply -f kubernetes/monitoring/configmap.yaml
kubectl apply -f kubernetes/monitoring/state-configmap.yaml
kubectl apply -f kubernetes/monitoring/cronjob.yaml
```

**Warning:** `state-configmap.yaml` contains initial state values. Reapplying it after monitoring has started can reset active alert state. Do not indiscriminately apply the entire monitoring directory to an existing cluster. Changes to the monitoring scripts must also be kept in sync with the scripts embedded in `configmap.yaml`.

Slack notifications cannot be sent without the webhook Secret. Never include the webhook URL in a README or commit it to Git.

### 7.8 Kubernetes access and general health checks

```bash
kubectl get pods -n devops-case
kubectl get deployments -n devops-case
kubectl get services -n devops-case
kubectl get cronjobs -n devops-case
kubectl get pvc -n devops-case
```

Backend readiness can be checked from inside the cluster or through a suitable port-forward. Browser access depends on the k3d host port mapping.

**For example, temporarily forward the frontend Service to local port 8082:**

```bash
kubectl port-forward -n devops-case service/frontend 8082:8080
```

This command keeps the terminal session occupied. Open `http://localhost:8082` from another terminal or browser. If NodePort port mapping is configured, the corresponding host port can be used directly.

## 8. VERIFYING APPLICATION FUNCTIONALITY

Create, list, edit and delete a record in the frontend. Verify that the record changes are reflected correctly in the interface. The backend `/record` API writes these operations to the `sample_training.records` collection.

**Health endpoints:**

GET `/healthcheck`: checks whether the backend process responds to HTTP requests (liveness).

GET `/healthcheck/ready`: verifies MongoDB connectivity (readiness). Returns HTTP 200 `READY` when healthy and HTTP 503 `NOT_READY` when MongoDB is unavailable.

During a MongoDB outage test, the backend process remained running and readiness returned 503. After MongoDB recovered, readiness returned to `READY` without restarting the backend. Readiness informs Kubernetes Service traffic routing decisions during temporary database issues. It does not guarantee immediate or uninterrupted service.

**Check the ETL Job:**

```bash
kubectl get cronjob github-etl -n devops-case
kubectl get jobs -n devops-case
```

**View logs for a specific successful Job:**

```bash
kubectl logs -n devops-case job/<actual-etl-job-name>
```

The ETL runs at the beginning of each hour using the UTC schedule `0 * * * *`. Repository documents are inserted on the first run. Subsequent runs update records using the same `github_id`. The unique index prevents duplicate repository IDs. The `last_synced_at` field is updated with each successful upsert.

In a previous verification, a subsequent run returned `fetched=3`, `inserted=0` and `updated=3` for three repositories. This count reflects the GitHub account at the time of the test and is not a fixed value.

## 9. TESTS AND QUALITY CHECKS

### 9.1 Frontend build

```bash
cd mern-project/client
npm ci
npm run build
```

### 9.2 Backend checks

```bash
cd mern-project/server
npm ci
npm audit --omit=dev --audit-level=high
node --check server.mjs
```

If commands are not being run from the project root, make sure to switch to the appropriate directory.

### 9.3 Cypress E2E

Cypress tests run while the frontend and backend are available. GitHub Actions runs them with MongoDB, backend and frontend containers created in its own Docker network. For a local frontend development server:

```bash
cd mern-project/client
npx cypress run --e2e
```

The default local Cypress `baseUrl` is `http://localhost:3000`. If the application is served on a different port, the test `baseUrl` must be adjusted accordingly. CI uses `http://localhost:8082`.

The original record creation test failed because it looked for the record on the wrong page. After correcting the page selection, both existing Cypress tests passed.

### 9.4 Unit tests for Python ETL analysis

**From the project root:**

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Six tests cover distinguishing older and newer ETL failures, recovery, CronJobs with no successful execution, missing failure timestamps and filtering failures belonging to another CronJob. All six tests passed. This does not mean that 100% code coverage has been measured for the module.

### 9.5 Dependency security checks

The initial `npm audit` reports identified 11 vulnerabilities in the backend and 89 in the frontend. After improvements, a local check reported 0 remaining backend vulnerabilities and 33 frontend vulnerabilities. These are historical measurements. Run the audits again to determine the current state. The production frontend container uses an Nginx image without Node.js build dependencies, but build-time and supply-chain risks are not entirely eliminated.

## 10. CI/CD AND RELEASE MANAGEMENT

`.github/workflows/ci.yml` is triggered by pushes to `main`, pull requests targeting `main` and `workflow_dispatch`.

**Pipeline stages:**

1. Backend: `npm ci`, production dependency audit and Node.js syntax validation.
2. Frontend: `npm ci` and React production build with `CI=true`.
3. Python ETL: install requirements, run `py_compile` and verify imports of `requests` and `pymongo`.
4. Cypress: start MongoDB, backend and frontend with Docker, then run E2E tests. Cypress tests run in a temporary isolated Docker environment on the GitHub Actions runner rather than in the target Kubernetes cluster.

The pipeline creates a separate `case-ci` network using `docker network create`. MongoDB, backend and frontend containers start in this network. Cypress tests run after backend readiness and frontend API access have been verified.

This approach prevents tests from changing data or running services in the target Kubernetes cluster. It also provides an independent test environment for each CI execution.

If the tests fail, relevant container logs and any Cypress screenshots are saved for investigation.

This stage validates the application's E2E behavior in a container environment. It does not test every aspect of Kubernetes deployment or orchestration.

5. Docker: if the previous checks pass, build backend, frontend and ETL images for `linux/amd64` and `linux/arm64`. Publish them to GHCR on pushes to `main`.

**GHCR image names:**

- `ghcr.io/iremsilay/devops-case-backend`
- `ghcr.io/iremsilay/devops-case-frontend`
- `ghcr.io/iremsilay/devops-case-etl`

Image tags: `latest` and `sha-<40-character-commit-hash>`.

The Docker stage depends on the backend, frontend, ETL and Cypress jobs. If any of these four jobs fails, the Docker publication stage does not start. Pull request validation builds images but does not push them to the registry.

Not deploying directly from GitHub Actions is a deliberate decision to isolate the local cluster. Instead of exposing the cluster to a GitHub-hosted runner, image publication and cluster release operations are kept separate. This is not a GitOps implementation and should not be described as fully automated continuous deployment.

**To deploy a published SHA-tagged image release to the local cluster:**

```bash
./scripts/deploy-local.sh sha-<40-character-git-commit-hash>
```

`deploy-local.sh` runs only in the `k3d-devops-case` Kubernetes context and accepts image tags in the `sha-<commit-hash>` format with a 40-character Git commit SHA.

The script first records the current image references of the backend Deployment, frontend Deployment and ETL CronJob.

It then updates backend and frontend images sequentially to the new GHCR releases using `kubectl set image`. It checks each Deployment rollout with `kubectl rollout status --timeout=180s`. If both succeed, it updates the ETL CronJob image.

If any command fails, the Bash `ERR` trap invokes the rollback function. This function reapplies the previously recorded image references to the backend, frontend and ETL resources using `kubectl set image`. It then checks the backend and frontend rollout status again.

If commands fail during rollback, the script issues a warning and manual investigation is required. The mechanism provides a controlled attempt to return to the previous version but cannot guarantee automatic recovery under every condition.

Updating the ETL CronJob image does not by itself prove that the new ETL version works. The result of a subsequent ETL Job must be verified separately.

This script performs a manual release operation. The specified SHA-tagged images must exist in GHCR and be pullable by the cluster. If image pulling requires authentication, an appropriate Kubernetes `imagePullSecret` must also be configured.

## 11. MONITORING, LOGGING AND SLACK ALERTS

The `monitoring-check` Kubernetes CronJob runs every minute. It inspects the number of available backend Deployment replicas and the status of the `github-etl` CronJob and Jobs through the Kubernetes API.

**Alert types:**

`BACKEND_UNAVAILABLE`: the number of available backend replicas is below the expected value.

`ETL_OVERDUE`: the last successful ETL execution is older than the configured threshold, currently 4,500 seconds (75 minutes).

`ETL_JOB_FAILED`: an ETL Job created by the CronJob has failed after the most recent successful ETL execution.

`ETL_NO_SUCCESS`: the ETL has no recorded successful execution.

`ETL_SUSPENDED`: the ETL CronJob is suspended.

Each alert type stores its active state and the last notification timestamp in the `monitoring-state` ConfigMap. The initial alert is sent to Slack. For ongoing issues, an independent 900-second (15-minute) throttling interval is applied. When the problem is resolved, a `RESOLVED` message is sent and the alert state is cleared. A failed webhook delivery is not recorded as a successful notification. ConfigMap updates use a `resourceVersion` precondition to reject updates based on stale state. This does not guarantee the elimination of every concurrent notification race.

`monitoring/evaluate_etl.py` evaluates Job `ownerReferences` and failure timestamps to prevent failures older than the most recent successful ETL run from triggering new alerts. Six unit tests have been implemented for this module.

**Inspection commands:**

```bash
kubectl get cronjob monitoring-check -n devops-case
kubectl get jobs -n devops-case
kubectl logs -n devops-case job/<actual-monitoring-job-name>
```

**Inspect alert state:**

```bash
kubectl get configmap monitoring-state -n devops-case -o yaml
```

**Important:** ConfigMap output contains alert metadata, not Secret values. There is no need to read, log or share the Slack webhook Secret value.

Backend and ETL failure, throttling, repeated notification and `RESOLVED` scenarios have been tested in the local Kubernetes environment. After testing, temporary test CronJobs and Jobs were removed, automatic monitoring was re-enabled and healthy logs were observed.

**Limitation:** If the cluster or Kubernetes API becomes entirely unavailable, the monitoring CronJob running inside the cluster may be unable to send notifications. External cluster availability monitoring has not been implemented. This version also does not include Prometheus/Grafana or centralized log storage.

## 12. MONGODB BACKUP AND RESTORE

`scripts/backup.sh` and `scripts/restore.sh` are used for the MongoDB `sample_training` and `github_etl` databases. The commands operate on the `mongodb-0` Pod in the Kubernetes `devops-case` namespace. These scripts do not target the Docker Compose MongoDB container.

**Run the backup from the project root:**

```bash
./scripts/backup.sh
```

**The script creates a `backups/YYYYMMDDTHHMMSSZ/` directory containing:**

- `sample_training.archive`
- `github_etl.archive`
- `SHA256SUMS`

The `mongodump` output is transferred to the host computer as archive files. The script treats empty archives and failed dump operations as errors. The directory is created with `700` permissions, files with `600` permissions and the checksum list is calculated using SHA-256.

**Restore:**

```bash
./scripts/restore.sh backups/<timestamp>
```

The script first verifies archive checksums using `shasum -a 256 -c SHA256SUMS`. It then asks the user to enter `RESTORE` to confirm the operation. Because `mongorestore --drop` is used, existing data in the target collections is removed before backup data is loaded. Do not apply this procedure casually to production data.

The end-to-end verification scenario is: create a record through the interface, take a backup, drop the relevant collection, confirm that the record disappears from both the interface and MongoDB, restore the archive and verify that the same record returns. This scenario was tested during development. Submission evidence must also be provided under `docs/screenshots/` and in `TESLIM_KANITLARI.md`.

The local backup directory is outside the Kubernetes cluster, but it is not independent off-site protection against physical disk loss on the same computer. This version has no automated backup scheduler, encrypted remote object storage or automatic retention cleanup. The actual measured RTO, chosen RPO/RTO targets and retention policy must be documented separately in `docs/backup-restore.md`. Estimates or targets must not be presented as measured test results.

## 13. ROLLBACK, CLEANUP AND SECURITY

### 13.1 Rollback

During a failed release, `deploy-local.sh` performs a rollback using the backend, frontend and ETL image references recorded before deployment.

Instead of using `kubectl rollout undo`, it reapplies the previous image versions with `kubectl set image`. After rollback, it uses `kubectl rollout status` for the backend and frontend to check whether the previous versions have become available again.

If rollback fails, the script produces a warning and manual intervention is required. This operation does not automatically revert database contents or schemas.

Failures detected after deployment has already completed do not automatically trigger rollback. In that case, the previous working Git commit SHA can be identified and `scripts/deploy-local.sh` can be run again with the older release tag.

Restoring the ETL CronJob image reference alone is not sufficient. The next ETL Job must also be checked for successful execution.

### 13.2 Safe cleanup

Use `docker compose down` to remove Compose containers. The `-v` option deletes the database volume.

In Kubernetes, deleting a namespace may cause loss of MongoDB PVC data and other cluster resources. Do not delete the `devops-case` namespace without taking a backup first. Deleting the entire cluster is not recommended as a routine cleanup step.

After temporary monitoring tests, remove the test Jobs and CronJobs, restore `monitoring-check` to `suspend=false` and verify that test alert states have been cleared. Do not reset the `monitoring-state` ConfigMap during normal operation.

### 13.3 Security approach

- Actual passwords, tokens and Slack webhook URLs are not included in the repository or container images.
- Kubernetes Secrets store sensitive values while ConfigMaps store non-sensitive configuration.
- The backend and ETL use separate MongoDB users with access to their respective databases.
- Backend, frontend and ETL containers avoid unnecessary root privileges. Monitoring uses a read-only root filesystem and a restricted ServiceAccount.
- The backend ClusterIP Service and MongoDB headless Service are not directly exposed externally. The frontend NodePort is the external entry point.
- CI performs a production dependency audit. Remaining frontend dependency warnings are explained in `docs/findings.md`.

**Risks:** CORS is configured broadly, API input validation is incomplete, the cluster runs on a single node with one MongoDB replica and automatic secret rotation and NetworkPolicy have not been implemented. Additional work is required for real production use.

## 14. COMMON ISSUES AND TROUBLESHOOTING

**The frontend opens but API requests fail:**

- Confirm that the frontend sends requests to `/api`.
- Check the backend Deployment and readiness status.
- Inspect the `case-backend` Service name in the Nginx reverse proxy configuration and the corresponding Service in the same namespace.
- Check the cluster port mapping or `kubectl port-forward` configuration.

**The backend is not READY:**

- Check MongoDB Pod/PVC status and MongoDB logs.
- Confirm that the `backend-mongo-uri` Secret exists and that the MongoDB user has the required permissions. Do not disclose Secret values.
- Evaluate `/healthcheck` and `/healthcheck/ready` separately.

**A Pod is in `ImagePullBackOff`:**

- Check whether local `case-*` images have been imported into k3d.
- Confirm that the GHCR image tag exists and registry access is available.
- Inspect image pull events in the Pod description.

**ETL is not running:**

- Confirm that the `github-etl` CronJob has `suspend=false`.
- Inspect recent Job logs and Kubernetes Job status/conditions.
- Check the GitHub username, API rate limits and MongoDB connectivity.

**Slack notifications are not arriving:**

- Check the `monitoring-check` CronJob and latest Job logs.
- Confirm that the `monitoring-slack-webhook` Secret exists.
- Inspect the active alert state and throttling timestamp in `monitoring-state`.
- Compare `WEBHOOK_FAILED` and `WEBHOOK_SENT` logs. Do not print the webhook value.

**Backup or restore fails:**

- Confirm that the `mongodb-0` Pod is ready.
- Verify that authorized MongoDB accounts are configured.
- Inspect `SHA256SUMS` verification and the presence of archive files.
- Remember that the `--drop` option modifies existing data during restore.

## 15. VERIFIED RESULTS AND KNOWN LIMITATIONS

**The following outcomes were verified in earlier tests:**

- Frontend, backend and MongoDB running with Docker Compose.
- Create, read/list, update and delete operations through the frontend.
- Both Cypress E2E tests passing (2/2).
- Backend remaining alive during a MongoDB outage, readiness returning 503 and then returning to 200 after database recovery.
- Frontend and backend Deployments reporting 1/1 ready on Kubernetes.
- Hourly Kubernetes ETL CronJob executions and updates to existing repository records without duplicate inserts.
- Periodic monitoring CronJob execution and evaluation of five alert types.
- Initial Slack alerts, throttling and `RESOLVED` scenarios as well as backend and ETL failure/recovery tests.
- All six ETL analysis module unit tests passing.
- MongoDB backup and restore procedure tested in the local environment.

These results describe earlier tests. The current state of a new installation must be verified independently.

**Intentional scope boundaries:**

- This environment is not a public cloud production service. It has been validated using local k3d.
- MongoDB has one replica. Multi-node operation, a replica set and automatic failover have not been implemented.
- Building container images in CI does not mean that Kubernetes deployment is automatic.
- Helm/Kustomize, Terraform, Argo CD/Flux and HPA/PDB have not been implemented.
- There are no Prometheus/Grafana dashboards or independent monitoring outside the cluster.
- Full API input schema validation, a restricted CORS allowlist and automatic secret rotation have not been implemented.
- MongoDB backup scripts are triggered manually. There is no automatic retention, encrypted remote storage or point-in-time recovery.

Advanced criteria being considered for future work include advanced observability based on existing verified alert scenarios, advanced security through image vulnerability scanning or SBOM generation and advanced disaster recovery through automated or off-site backups. Planned features must not be described as implemented.

## 16. ADDITIONAL DOCUMENTATION AND SUBMISSION EVIDENCE

**Initial findings, applied changes and intentional scope boundaries:**

`docs/findings.md`, `docs/findings_en.md`

**Architecture diagram and detailed data/request flow:**

`docs/architecture.md`

**Backup/restore steps, retention and RPO/RTO values:**

`docs/backup-restore.md`

**Required screenshots of the running system:**

`docs/screenshots/`, `TESLIM_KANITLARI.md`, `SUBMISSION_EVIDENCE.md`

**Answers to final case questions:**

`CASE_SONU_CEVAPLARI.md`, `CASE_END_ANSWERS.md` 

**Original assessment documents:**

`DevOps_Teknik_Case_TR.docx`, `DevOps_Technical_Case_EN.docx`

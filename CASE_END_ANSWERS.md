# CASE END ANSWERS

Answer all questions below by relating them directly to your implementation.

Answers should be concise, specific, and detailed enough to explain your technical decisions. Where appropriate, reference the relevant source file, manifest, pipeline step, or document path.

---

## Candidate Information

- **Full name:** İrem Sıla AY
- **Repository URL:** https://github.com/iremsilay/devops-case  
- **Completion date:** 11 November 2026  
- **Target environment used:** Local Kubernetes — k3d cluster on Docker Desktop (`devops-case`)

---

## 1. Architecture and Request Flow

Explain the architecture you implemented and the path a user request follows from the frontend through the backend to the database.

Also prepare an architecture diagram showing the system components, connections between components, traffic flow, and external access points, and add it to the project repository as one of the following:

- `docs/architecture.md`
- `docs/architecture.pdf`

The diagram may be created with Mermaid, Draw.io, Excalidraw, or a similar tool. Include the editable source file in the repository as well.

**Answer:**

The system runs in the local `k3d-devops-case` Kubernetes cluster on Docker Desktop, under the `devops-case` namespace.

Users access the application through the externally accessible `frontend` NodePort Service. This Service forwards requests to the frontend Pod running Nginx. Nginx serves the static files of the React application.

Requests from the browser to `/api` are forwarded by the Nginx reverse proxy to the `case-backend` ClusterIP Service, which is accessible only from within the cluster. The backend Pod performs MongoDB operations for employee records through the `mongodb-service` headless Service. MongoDB runs in the `mongodb-0` StatefulSet Pod and stores its data on the `mongo-data` PersistentVolumeClaim.

The frontend NodePort Service is the only application component exposed externally. The backend and MongoDB are not directly accessible from outside the cluster. Local access is provided through k3d host port mapping or temporary `kubectl port-forward`. This architecture does not include an Ingress Controller or HTTPS/TLS termination; traffic uses HTTP.

Independently of user requests, the `github-etl` CronJob runs at the beginning of every hour. The ETL Job retrieves repository data from the GitHub REST API and upserts it into the `github_etl.repositories` collection in MongoDB using the `github_id` field.

The `monitoring-check` CronJob checks backend and ETL status through the Kubernetes API every minute. Alert state is stored in the `monitoring-state` ConfigMap; notifications are sent through a Slack Incoming Webhook when a problem is detected.

The architecture description is provided in `docs/architecture.md`, the visual diagram in `docs/architecture.png`, the editable source in `docs/architecture.drawio`, and the PDF export in `docs/architecture.pdf`.

---

## 2. Critical Findings and Prioritization

What were the three most critical issues you identified in the starter projects? Which impact and risk criteria did you use to prioritize them?

**Answer:**

F-08, F-01, and F-04 were selected as priorities during the initial analysis. Prioritization considered the risk of service interruption, security impact, and compliance with the case's mandatory delivery criteria.

| Finding | Priority | Reason for selection and solution approach |
| --- | --- | --- |
| F-08 — MongoDB connection resilience | Critical | When MongoDB was unavailable, an unhandled `MongoServerSelectionError` caused the entire backend Node.js process to crash. This was the first finding addressed because a brief database or network interruption could bring down the entire API. Connection handling and asynchronous error handling were revised, `serverSelectionTimeoutMS: 5000` was added, and the readiness endpoint was configured to return HTTP 503 during a MongoDB outage. Recovery to the `READY` state without restarting the backend was verified once MongoDB became available again. |
| F-01 — Dependency vulnerabilities | Critical | Initially, the backend had 11 vulnerabilities and the frontend had 89, including 1 critical vulnerability in the backend and 6 in the frontend. These were considered critical because known CVEs could be exploited during runtime or the build process. Dependency updates and `npm audit` checks were applied in the first stage. Subsequently, backend vulnerabilities were reduced to 0, critical frontend vulnerabilities were resolved, and dependency auditing, Trivy image scanning, and SBOM generation were added to CI. The remaining frontend `devDependencies` risks were documented in `docs/findings.md`. |
| F-04 — Missing container and deployment files | High | Initially, there were no Dockerfiles, Kubernetes manifests, or CI/CD pipeline for the frontend, backend, and ETL. As a result, the project could not be set up, deployed, or verified reproducibly. This finding was resolved as the work under Core Criteria 2–8 was completed: Dockerfiles and `.dockerignore` files, Docker Compose, Kubernetes Deployment/StatefulSet/Service/CronJob manifests, PVC, Secret and ConfigMap configuration, a CI pipeline, monitoring, backup/restore, and controlled deployment/rollback were added. |

F-08 was addressed first because it directly caused service interruptions. F-01 was the second critical finding because of its security risk; partial improvements were made initially, and the scope was later expanded with CI security checks. F-04 was a structural finding that could not be resolved with a single code fix; it was addressed as the case's containerization, orchestration, CI/CD, ETL, logging, security, and backup/restore criteria were completed.

---

## 3. Items Left Out of Scope

Which issues did you intentionally leave unresolved or out of scope? Explain the reasons for these decisions.

**Answer:**

Core Criteria 1–9 were completed. Advanced observability, advanced security, and advanced disaster recovery were selected under the advanced criteria:

- **Advanced Criterion 4:** Kubernetes-based monitoring, Slack alerts, throttling, and `RESOLVED` notifications
- **Advanced Criterion 5:** Trivy container image scanning and CycloneDX SBOM generation
- **Advanced Criterion 7:** Backup/restore with SHA-256 verification and automated backup validation in an isolated MongoDB container

The following items were intentionally left out of scope:

| Item | Rationale |
| --- | --- |
| Public cloud, multiple nodes, and high availability | The solution was verified in a local k3d environment. A MongoDB replica set, multiple nodes, automatic failover, HPA, and PDB require actual production infrastructure and capacity planning. |
| Helm, Kustomize, and Terraform | The existing Kubernetes manifests are sufficient for the local deployment within the case scope. As the number of environments and cloud resources increases, environment separation with Helm/Kustomize and infrastructure provisioning with Terraform become meaningful. |
| GitOps and fully automated CD | GitHub Actions builds images and publishes them to GHCR. To avoid exposing the local cluster externally, deployment is manually initiated in a controlled manner through `deploy-local.sh`. Argo CD or Flux was not installed. |
| Prometheus, Grafana, and centralized logging | Backend and ETL health are monitored through a Kubernetes CronJob and Slack alerts. Metric storage, dashboards, and centralized logging infrastructure were not implemented because they would add operational overhead to this local case. |
| External cluster availability monitoring | Since the monitoring CronJob runs inside the cluster, it cannot generate notifications if the cluster or Kubernetes API becomes completely unavailable. Independent external uptime monitoring is required in production. |
| Restrictive CORS allowlist and complete API schema validation | API error handling and behavior during MongoDB outages were improved; however, complete request-body schema validation with Joi or Zod and a production origin allowlist were not added. |
| NetworkPolicy and centralized Secret management | Kubernetes Secret and ConfigMap separation was implemented. NetworkPolicy, integration with External Secrets Operator, Vault, or a cloud Secret Manager, and automatic Secret rotation were not implemented. |
| Image signing, policy as code, and publication blocking | Trivy scanning and SBOM generation are used for reporting. Vulnerabilities do not automatically stop CI runs. Image signing and policy-based publication blocking were not added. |
| Automated, remote, and encrypted backups | Backup/restore and isolated restore validation were implemented; however, backups are started manually, retention cleanup is not automated, and backups are stored on the same local computer. Object storage, encryption, and point-in-time recovery were not implemented. |

These decisions were made to complete mandatory criteria first, including service continuity, vulnerability remediation, reproducible deployment, ETL correctness, and backup/restore.

---

## 4. Target Environment Selection

Why did you choose a cloud environment or a virtual machine? Which components or approaches would you use differently in a real production environment?

**Answer:**

A local k3d Kubernetes cluster running on Docker Desktop was selected as the target environment. This choice made it possible to verify the case's Kubernetes, containerization, CI, ETL CronJob, monitoring, backup/restore, and rollback requirements reproducibly without incurring cloud costs.

k3d enabled the use of standard Kubernetes resources: Deployment, StatefulSet, Service, CronJob, PersistentVolumeClaim, ConfigMap, Secret, and RBAC. This allowed the solution to go beyond Docker Compose and its runtime behavior on Kubernetes to be tested locally.

In a real production environment, I would prefer managed Kubernetes and managed MongoDB. For example, I would use a cluster spanning multiple availability zones on AWS EKS, Azure AKS, or Google GKE, and a managed service such as MongoDB Atlas providing a replica set and automatic failover for MongoDB.

In production, I would add the following components to the current solution:

| Area | Production approach |
| --- | --- |
| Networking and external access | VPC/VNet, private subnets, a Load Balancer or Ingress Controller, TLS certificates, HTTPS, and WAF if required |
| High availability | Multiple nodes, multiple backend/frontend replicas, HPA, PDB, and topology spread rules |
| MongoDB | A multi-node replica set, automatic failover, managed disks, and connection-pool and capacity monitoring |
| Infrastructure management | Reproducible provisioning of network, cluster, IAM, and cloud resources with Terraform or OpenTofu |
| Manifest management | Management of development, test, and production environments with separate values through Helm or Kustomize |
| Secret management | Centralized Secret management and automatic rotation through a cloud Secret Manager, HashiCorp Vault, or External Secrets Operator |
| Security | NetworkPolicy, a restrictive CORS allowlist, complete API schema validation, image signing, policy as code, and publication blocking rules |
| CI/CD | Short-lived cloud access through GitHub OIDC, a GitOps approach, controlled production approval, and canary or blue-green deployment |
| Observability | Prometheus, Grafana, centralized logging, dashboards, SLI/SLO definitions, and uptime monitoring from outside the cluster |
| Disaster recovery | Scheduled backups, encrypted object storage, an off-site copy, a retention policy, point-in-time recovery, and periodic restore drills |

The local k3d environment is suitable for validating technical decisions and basic operational workflows. Production requires managed infrastructure with multiple nodes to meet availability, data durability, security, capacity, and disaster recovery requirements.

---

## 5. MongoDB Approach

Why did you choose your MongoDB deployment and service approach? Explain the alternatives you considered, along with their advantages, disadvantages, and operational trade-offs.

**Answer:**

MongoDB was deployed on Kubernetes as a single-replica `StatefulSet`. The database Pod is created with the stable name `mongodb-0`, and its data is stored on the `mongo-data` PersistentVolumeClaim. This approach keeps data independent of the Pod lifecycle, even when the Pod is recreated.

A headless Service named `mongodb-service` was used for MongoDB. The headless Service provides a stable DNS identity for the StatefulSet Pod and allows the backend and ETL to access MongoDB only from within the cluster. MongoDB was not exposed externally.

| Component | Selection | Rationale |
| --- | --- | --- |
| Workload | `StatefulSet` | MongoDB is a stateful component. It requires a stable Pod name and a persistent volume association. |
| Storage | PersistentVolumeClaim | Preserves MongoDB data even if the Pod is deleted or restarted. |
| Service | Headless Service | Provides a stable network identity and internal DNS access for `mongodb-0`. |
| Replica count | 1 | Keeps resource consumption and operational complexity low in the local k3d case environment. |
| External access | None | MongoDB is accessed only by the backend and ETL from within the cluster. |

Alternatives considered:

| Alternative | Advantage | Disadvantage | Suitability |
| --- | --- | --- | --- |
| Deployment and ClusterIP Service | Simpler setup | A weaker model for stable Pod identity and stateful volume management | More suitable for stateless applications |
| StatefulSet and ClusterIP Service | May be sufficient for a single MongoDB Pod | Does not directly provide stable DNS identities for StatefulSet Pods | A headless Service was preferred |
| MongoDB replica set | High availability, data replication, and failover | Requires multiple Pods, multiple volumes, quorum, capacity planning, and operational management | Preferred for production |
| MongoDB Operator or Helm chart | Ready-made setup, lifecycle management, and replica set management | Adds abstraction and complexity to the local case | Suitable for large or long-lived clusters |
| Managed MongoDB service | The service provider handles backups, patching, replication, and failover | Introduces cloud costs and provider dependency | The most suitable option for production |

The main trade-off in this solution is giving up high availability in exchange for simplicity. With a single MongoDB replica, there is no automatic failover in the event of Pod, node, or local disk loss. A backup/restore mechanism was implemented for data recovery; however, it does not replace a replica set, remote backups, or point-in-time recovery.

In a real production environment, I would use MongoDB Atlas or a managed MongoDB replica set spanning multiple availability zones in the cloud. This would provide automatic failover, monitoring, encrypted backups, point-in-time recovery, and safer operational management.

---

## 6. Helm or Manifest Management

If you used Helm, explain why you selected it and what problem it solves in this project.

Describe its advantages and the additional complexity it introduces compared with alternatives such as plain Kubernetes manifests or Kustomize.

If you did not use Helm, explain the method you selected and the reason for your choice.

**Answer:**

Helm was not used in this solution. Kubernetes resources were managed through plain YAML manifests organized by component:

- `kubernetes/backend/`
- `kubernetes/frontend/`
- `kubernetes/mongodb/`
- `kubernetes/etl/`
- `kubernetes/monitoring/`

Namespace, ConfigMap, Secret dependencies, Deployment, StatefulSet, Service, and CronJob resources were kept in separate files. The installation order was clearly documented in the README.

Plain manifests were selected for this case, which has a single local Kubernetes environment. Since all resources are directly visible, it is easy to inspect each component's configuration, its Secret or ConfigMap dependencies, and its Service type during evaluation. This also allowed the work to focus on Kubernetes resources without adding layers such as a Helm chart structure, `values.yaml`, template functions, and release management.

| Approach | Advantage | Disadvantage |
| --- | --- | --- |
| Plain YAML manifests | Simple, visible, easy to review, and sufficient for a single environment | Repeated values and maintenance overhead increase as the number of environments grows |
| Kustomize | Produces development, test, and production overlays from shared manifests | The structure can become complex with many environments and patch rules |
| Helm | Manages repeated values through templates; provides release versioning, rollback, and ready-made charts | Template logic, `values.yaml` files, and chart dependencies add complexity |

In this project, image versions were updated through `scripts/deploy-local.sh` using `kubectl set image` rather than a Helm release. The script saves previous image references and attempts rollback using those references if deployment fails.

In a real production environment, I would use Helm or Kustomize because multiple environments would be involved. Helm would be suitable for a shared application chart, versioned release management, and environment-specific `values` files; Kustomize would be suitable for applying a small number of environment differences to existing manifests. The choice should depend on the number of environments, configuration diversity, and release management needs.

---

## 7. Kubernetes Service Types

Which criteria did you use to select Kubernetes Service types?

For each service, explain why you chose `ClusterIP`, `NodePort`, `LoadBalancer`, `ExternalName`, or a headless Service. State which services should be accessible from outside the cluster and how you prevented unnecessary external exposure.

**Answer:**

I used three criteria to select Service types: whether a component needs to be accessible to users, whether it serves only components inside the cluster, and whether a stateful component requires a stable network identity.

| Service | Type | Port | Rationale |
| --- | --- | --- | --- |
| `frontend` | NodePort | `30080` → `8080` | Users need to access the web interface from outside the cluster. Browser access is provided through host port mapping in the local k3d environment. |
| `case-backend` | ClusterIP | `5050` | The backend is called only by the frontend Nginx reverse proxy. It does not need to be exposed directly to external access. |
| `mongodb-service` | Headless Service | `27017` | Provides a stable DNS identity for the MongoDB StatefulSet Pod. The backend and ETL access MongoDB only from within the cluster. |

`frontend` is the only application Service exposed externally. Nginx serves React static files and forwards browser requests to `/api` to the internal `case-backend` Service. This avoids exposing the backend API through a separate NodePort or LoadBalancer.

`ClusterIP` was selected for `case-backend` because this type provides a virtual IP accessible only to Pods within the namespace. The backend's MongoDB connection is also established only from within the cluster.

A headless Service was selected for `mongodb-service`. Instead of the single virtual IP used by regular Services, a headless Service uses the DNS identity of the StatefulSet Pod. This structure is suitable for providing stable access to stateful Pods such as `mongodb-0`.

`LoadBalancer` was not used because the target environment is not hosted on a public cloud. There is no cloud Load Balancer provider in the local k3d environment; NodePort is sufficient for frontend access.

`ExternalName` was not used because there is no external DNS-based service that needs to be accessed through such a Service from within the cluster. External services such as the GitHub API and Slack webhook are used through direct HTTPS requests from application and monitoring Pods.

No Service was defined for ETL or monitoring components. They are not long-running services that receive user requests; they run as temporary Jobs/Pods created by CronJobs.

Unnecessary external access was prevented by not creating NodePort or LoadBalancer Services for the backend and MongoDB. Although this solution does not include NetworkPolicy, the Service types limit direct external exposure to the frontend. Production should additionally apply NetworkPolicy, Ingress, HTTPS/TLS, WAF, and restrictive network access rules.

---

## 8. Kubernetes Workload Types

Which criteria did you use to select workload types for the application components?

Explain why you used `Deployment`, `StatefulSet`, `Job`, `CronJob`, or another workload type for the frontend, backend, MongoDB, and ETL components.

Describe how you evaluated the following:

- Stateless or stateful behavior
- Persistent-storage requirements
- Pod identity and ordered-execution requirements
- Execution frequency
- Restart behavior
- Scalability requirements

**Answer:**

Workload types were selected by considering whether each component is stateful, its persistent-storage requirements, execution duration, execution frequency, restart behavior, and scalability needs.

| Component | Workload type | Rationale |
| --- | --- | --- |
| Frontend | Deployment | A stateless component that serves the React build through Nginx. If the Pod is lost, a new Pod can be created from the same image. |
| Backend | Deployment | The Express API is stateless; application data is stored in MongoDB. Deployment maintains the desired replica count and creates a new Pod when a Pod fails. |
| MongoDB | StatefulSet | MongoDB is a stateful component. It requires a stable Pod identity, a persistent volume, and predictable startup behavior. |
| ETL | CronJob | ETL is not a continuously running service; it needs to run once per hour. The `github-etl` CronJob creates a separate Job for each hour. |
| Monitoring | CronJob | Monitoring was designed as a check that runs once per minute rather than a continuously running Pod. A separate Job is created for each check. |

Deployment was selected for the frontend and backend because these components do not need to persist data on local disk. Since application state resides in MongoDB, a Pod can run again with the same image and configuration after a restart. Each component currently uses one replica in the local environment; in production, they can scale horizontally based on CPU, memory, request count, and latency metrics.

StatefulSet was used for MongoDB. It has the stable Pod identity `mongodb-0` and stores its data on the `mongo-data` PersistentVolumeClaim. Data remains on the volume even if the Pod is recreated. StatefulSet also provides the stable Pod identity and ordered startup behavior required by stateful components.

Deployment was not used for ETL because it does not need to operate as a continuously running service handling requests. The `github-etl` CronJob runs at the beginning of every hour in the UTC time zone and creates a Job that terminates upon completion. ETL's idempotent upsert using the `github_id` field makes it safe to process the same repository data again in subsequent runs.

Monitoring was also designed as a CronJob. Every minute, `monitoring-check` evaluates backend and ETL status through the Kubernetes API, stores the result in a ConfigMap, and sends a Slack notification if necessary. Using short-lived checks instead of a separate, continuously running monitoring Deployment keeps resource consumption low in the local case environment.

The current single-replica MongoDB configuration does not provide horizontal scaling. Production requires a replica set, multiple nodes, suitable persistent disks, automatic failover, and capacity planning. For the frontend and backend, HPA, PDB, and topology spread rules can provide a more resilient scaling approach.

---

## 9. Configuration and Secret Management

How did you manage application configuration and secrets?

When a secret value is changed or rotated, how would you ensure that the application securely starts using the new value?

**Answer:**

Configuration and sensitive information were separated. Non-sensitive values are passed to containers as environment variables through Kubernetes `ConfigMap` resources, while passwords and connection details are provided through Kubernetes `Secret` resources.

| Resource | Contents | Purpose |
| --- | --- | --- |
| `app-config` ConfigMap | GitHub username, ETL database and collection details | Non-sensitive ETL configuration that may vary by environment |
| `mongodb-auth` Secret | Initial credentials for MongoDB root and application users | User creation during initial MongoDB setup |
| `backend-mongo-uri` Secret | `ATLAS_URI` | Backend connection to MongoDB |
| `etl-mongo-uri` Secret | `ATLAS_URI` | ETL connection to MongoDB |
| `monitoring-slack-webhook` Secret | `SLACK_WEBHOOK_URL` | Slack notifications |

The same separation is supported through `.env.example` in the Docker Compose environment. The actual `.env` file, passwords, tokens, and webhook values are not committed to Git. Kubernetes Secret values are also not stored in the repository or container images.

In the current local solution, Secrets are passed to containers as environment variables. Running Pods therefore do not automatically refresh their values when a Secret changes. The relevant workload must be restarted after the Secret is updated.

For example, when the backend connection URI changes, the safe process is as follows:

1. Create the new MongoDB user or password in MongoDB.
2. Update the `backend-mongo-uri` Secret with the new URI.
3. Restart the backend Deployment through a controlled rollout.
4. Verify the `/healthcheck/ready` endpoint and Pod rollout status.
5. Remove the old MongoDB user or password after verifying that the new connection works.

For ETL and monitoring CronJobs, newly created Jobs use the updated Secret value. If a Job is already running, it is allowed to finish or terminated in a controlled manner. For the MongoDB StatefulSet, changing the `mongodb-auth` Secret alone does not change MongoDB user passwords; the password must first be changed in MongoDB, and the connection Secrets must then be updated.

In production, I would use a cloud Secret Manager, HashiCorp Vault, or External Secrets Operator in addition to Kubernetes Secrets. Secret values would be managed with encryption at rest, strict RBAC, audit records, and automatic rotation. Application components would start using updated Secret values through controlled rollouts or restarts.

---

## 10. MongoDB Availability Failure

If MongoDB becomes unavailable, how will the backend application, readiness/liveness checks, and user requests behave?

What measures did you take, or would you take, to reduce user impact and allow the service to recover in a controlled manner?

**Answer:**

The backend process does not crash when MongoDB becomes unavailable. In the starter application, an unhandled `MongoServerSelectionError` could terminate the entire Node.js application during a brief database outage. This behavior was fixed under F-08.

| Condition | Behavior |
| --- | --- |
| MongoDB is available | `/healthcheck` and `/healthcheck/ready` return HTTP 200. The backend Pod is included in Kubernetes Service traffic. |
| MongoDB is unavailable | The backend process continues running. `/healthcheck` returns HTTP 200; `/healthcheck/ready` returns HTTP 503 and `NOT_READY`. |
| Kubernetes behavior | A Pod that fails readiness is removed from Service endpoints. New user traffic is not routed to the unhealthy backend Pod. |
| API request | Requests requiring MongoDB temporarily fail. Database errors are caught and controlled error responses are returned; the Node.js process does not terminate. |
| When MongoDB becomes available again | The backend reconnects to MongoDB without a restart. Once readiness returns HTTP 200 and `READY` again, the Pod is included in Service traffic again. |

The following measures were implemented:

- Connection handling and asynchronous error handling in `db/conn.mjs` were revised.
- `serverSelectionTimeoutMS: 5000` was added to prevent prolonged waits for a MongoDB connection.
- A controlled HTTP 503 response was added for MongoDB connection errors.
- Liveness and readiness checks were separated. Liveness checks only whether the backend process is running, while readiness also checks the MongoDB connection.
- A readiness probe was defined for the backend Deployment.
- Backend availability is monitored through the monitoring CronJob; a Slack notification is sent when a problem occurs.

This approach prevents users from being routed to an unhealthy Pod, but it does not guarantee that operations requiring data will succeed while MongoDB is completely unavailable. Users may see temporary errors; the goal is to prevent the entire backend service from crashing and enable controlled recovery when MongoDB returns.

In production, I would additionally use a MongoDB replica set, multiple availability zones, connection-pool monitoring, timeout and retry policies, a circuit breaker approach, multiple backend replicas, HPA, and external availability monitoring.

---

## 11. Faulty Deployment and Rollback

How would you detect a faulty deployment?

Which method would you use to roll it back, and how would you verify that the previous working version has been restored safely?

**Answer:**

In the current local solution, `scripts/deploy-local.sh` checks backend and frontend rollout status using `kubectl rollout status --timeout=180s`. If a Pod cannot pull its image, crashes, or fails readiness checks, the Bash `ERR` trap mechanism reapplies the image SHA references saved before deployment using `kubectl set image`.

This method detects infrastructure-level rollout failures; however, a Pod being `1/1 Ready` does not guarantee that the application's business logic works correctly. The API could return HTTP 500 for every request, use an incorrect environment variable, or be incompatible with the database schema. In such cases, the current script, which relies only on Kubernetes probes, does not trigger rollback.

In production, I would use a GitOps approach instead of a manual Bash script. Argo CD or Flux applies the declarative target version from the Git repository to the cluster. Argo Rollouts or Flagger initially exposes the new version as a canary to a small portion of traffic, such as `10%`.

During the canary stage, the following quality signals are evaluated through Prometheus:

- HTTP 5xx error rate
- p95 and p99 API latency
- Request failure rate
- MongoDB connection and query error rate
- Smoke test or synthetic CRUD check results

If the defined SLO thresholds are exceeded, Argo Rollouts or Flagger performs an automatic, declarative rollback without increasing traffic to the new version. After successful analyses, traffic is gradually increased to `25%`, `50%`, and `100%`.

Database schema changes must be managed separately from image rollback. In production, I would use backward-compatible migrations, a separate migration Job, schema version checks, and a backup plan.

---

## 12. Scalability and Bottlenecks

If traffic increases tenfold, where do you expect the first bottleneck to occur?

Which components would you scale, and based on which metrics and thresholds? Explain how you would evaluate database connections, resource usage, and dependent services.

**Answer:**

With a tenfold increase in traffic, MongoDB is expected to be the first sustained bottleneck. In the current configuration, MongoDB runs with a single replica, and all CRUD write operations go to the same instance. The backend could also reach its limit first because it has only one replica; the exact order must be determined through load testing.

Scaling the backend through HPA based only on CPU or memory usage is insufficient. Since Node.js is asynchronous and I/O-intensive, CPU usage may remain low when MongoDB slows down, while pending request count, p95 latency, connection-pool queue length, and memory usage may increase.

| Component | Metrics to monitor | Approach |
| --- | --- | --- |
| Backend | RPS, in-flight request count, p95/p99 latency, 5xx rate, Event Loop lag, memory | HPA with Custom Metrics; CPU as a supporting metric only |
| MongoDB | Active connections, connection-pool wait time, query latency, CPU, memory, disk I/O, disk utilization | Resource and index optimization first; then a replica set and read replicas |
| Frontend | Request rate, p95 latency, 5xx rate, CPU/memory | More Deployment replicas and a CDN |
| ETL | Job duration, GitHub API 403/429 responses, MongoDB write latency | Limit parallelism and optimize API calls and scheduling |

When the backend replica count increases, each Pod may open a separate connection pool to MongoDB. A `maxPoolSize` limit must therefore be defined in the Node.js MongoDB client.

```text
maxPoolSize per Pod
≤ (MongoDB connection capacity - allowance for ETL, monitoring, and administration)
  / maximum backend replica count
```

If this connection budget is exceeded, MongoDB connection exhaustion, query queues, and service latency may occur even if HPA scales the backend. Backend HPA decisions must therefore be evaluated together with MongoDB active connection utilization and connection-pool wait time.

Read replicas can reduce read load; create, update, and delete operations still go to the primary node. If write load continues to grow, the replica set, data model, indexes, and eventually sharding should be evaluated.

---

## 13. Logging, Monitoring, and Alerting

Which logs, metrics, and alerts did you create?

During an incident, which dashboards, logs, metrics, or alert records would you examine first to diagnose the problem?

**Answer:**

The current solution does not include centralized logging or dashboard infrastructure. Monitoring relies on Kubernetes resource status, Pod and Job logs, `monitoring-check` CronJob output, the `monitoring-state` ConfigMap, and Slack notifications.

| Area | Existing log or signal |
| --- | --- |
| Backend | HTTP error records, MongoDB connection errors, readiness and liveness results |
| ETL | `fetched`, `inserted`, `updated`, and `unchanged` counters; GitHub API and MongoDB error records |
| Kubernetes | Pod status, Deployment replica count, restart count, events |
| Monitoring | `BACKEND_UNAVAILABLE`, `ETL_OVERDUE`, `ETL_JOB_FAILED`, `ETL_NO_SUCCESS`, and `ETL_SUSPENDED` alert states |
| Slack | Initial alert, 15-minute throttling, `RESOLVED`, webhook success or failure results |
| Backup | Backup/restore result, SHA-256 verification, and restore script duration |

During an incident, I first examine the component and timestamp in the Slack alert, followed by the active alert and `last_sent` state in the `monitoring-state` ConfigMap. I then check Kubernetes Pod, Deployment, Job, and event status, followed by the relevant backend, ETL, or monitoring logs.

```bash
kubectl get pods,deployments,cronjobs,jobs -n devops-case
kubectl get events -n devops-case --sort-by='.lastTimestamp'
kubectl get configmap monitoring-state -n devops-case -o yaml
```

For a backend problem, I examine backend logs, readiness results, MongoDB Pod/PVC status, and MongoDB logs. For an ETL problem, I check the latest ETL Job logs, the CronJob's `suspend` value, GitHub API access, and the MongoDB connection.

An important limitation of the current logging approach is the absence of a Correlation ID across requests. Under heavy traffic, logs from many concurrent requests can become interleaved, making it difficult to trace a specific user request through frontend, backend, and MongoDB error records.

In production, I would ensure that every request is assigned an `X-Request-ID` or Trace ID. Nginx or the backend generates this identifier, and the same identifier is propagated through the frontend, Nginx, backend, and dependent service calls. Backend logs would include at least the following fields as structured JSON:

```text
timestamp, level, service, pod, request_id, method, path,
status_code, duration_ms, mongo_error
```

For example, the `request_id` included in an error returned to a user could then be filtered with `grep` in `kubectl logs` output, even without a centralized logging system. With centralized logging, the same identifier could be searched across all services in Kibana or Grafana Loki.

In production, I would also collect metrics with Prometheus, set up Grafana dashboards, and use Loki or ELK for centralized logging. Adding traces with OpenTelemetry would enable end-to-end tracking of request latency across frontend, backend, MongoDB, and external API calls.

---

## 14. Security Risks

What are the three most important security risks in your solution?

Explain the controls you implemented, or would implement in production, to reduce these risks.

**Answer:**

One important security risk is container runtime security. In the current solution, the backend, frontend, and ETL containers run as non-root users; `allowPrivilegeEscalation: false`, `capabilities.drop: ALL`, and `seccompProfile: RuntimeDefault` are configured. The monitoring container additionally uses `readOnlyRootFilesystem: true`.

`readOnlyRootFilesystem: true` has not yet been applied to the backend and frontend containers. I would add this setting in production. Even if an RCE vulnerability were exploited, an attacker would then be unable to write persistent tools or payloads to the container filesystem layer.

When applying this setting, the paths that the application actually needs to write to must be defined separately. For example, directories required by Nginx, such as `/var/cache/nginx`, `/var/run`, or `/tmp`, should be made writable through `emptyDir` volumes. Otherwise, the container may fail to start because of the read-only root filesystem. This control does not completely prevent RCE; additional defenses are required against in-memory attacks or attacks involving explicitly writable volumes.

Other important risks and production controls:

| Risk | Production control |
| --- | --- |
| Broad CORS policy and incomplete API schema validation | A restrictive CORS allowlist, Zod/Joi validation, rate limiting, authentication, and HTTPS |
| Manual Secret management | A cloud Secret Manager or Vault, Workload Identity, RBAC, and automatic Secret rotation |
| Missing NetworkPolicy | Default-deny NetworkPolicy with traffic allowed only between necessary Pods |
| Supply-chain risk | Trivy, SBOM, image signing, digest verification, and a policy that blocks image publication when critical vulnerabilities are present |

---

## 15. Python ETL Record Update Behavior

When the Python ETL receives the same repository information again, how does it find and update the existing record?

Which field did you use as the unique record key, and which screenshot or output demonstrates that no duplicate was created?

**Answer:**

For each repository retrieved from the GitHub API, ETL uses the `github_id` field, which contains GitHub's immutable numeric repository identifier. This field has a unique index in MongoDB.

For each repository, MongoDB operations follow this logic:

```python
collection.update_one(
    {"github_id": repository["id"]},
    {"$set": repository_data},
    upsert=True
)
```

On the first run, if no record matches `github_id`, `upsert=True` creates a new document. When the same repository is retrieved again in subsequent runs, the existing document is found using the same `github_id` and updated. The unique index in MongoDB also prevents a second document from being inserted with the same identifier.

During verification, the same three repositories were processed a second time. The second ETL run produced the following result:

```text
fetched=3
inserted=0
updated=3
unchanged=0
```

The total number of documents in the collection remained three.

Evidence:

- `docs/screenshots/11-etl-first-import.png`: Shows that repository data was saved to MongoDB during the first ETL run.
- `docs/screenshots/14-etl-upsert-result.png`: Shows that the same repositories were updated without creating new records when processed again.
- `docs/screenshots/15-etl-unique-index.png`: Shows the `unique: true` index on the `github_id` field and the total record count.

---

## 16. Backup and Restore Approach

Which backup method and storage location did you choose for MongoDB?

What are your backup frequency, retention period, RPO, and RTO targets, and what was the actual restore duration you measured?

How would you verify that a backup is not corrupted or incomplete, and how would you change this approach in a real production environment?

Provide your runbook in `docs/backup-restore.md` and reference the evidence from `SUBMISSION_EVIDENCE.md`.

**Answer:**

In the current solution, backups are taken through `scripts/backup.sh`, which is run from the local computer. The script runs `mongodump` in the `mongodb-0` Pod in Kubernetes, downloads archive files to the `backups/YYYYMMDDTHHMMSSZ/` directory, and generates a SHA-256 checksum. This approach works for the case and has been verified end to end; however, it is not the final architecture suitable for production.

In production, I would design the backup process as a CronJob running inside Kubernetes. The CronJob would run with a ServiceAccount using cloud Workload Identity; for example, on AWS, it would receive permission to write only to the relevant S3 bucket through IRSA.

The backup Job would stream the MongoDB dump to encrypted object storage without writing it to temporary local disk. The conceptual flow is as follows:

```text
mongodump archive stream
→ encryption
→ immutable object storage
```

In the AWS example, archive data would be uploaded to S3 with SSE-KMS encryption. S3 Object Lock would protect it against deletion or modification. A lifecycle policy would automatically manage backups whose retention period has expired. Backups would be stored in independent storage in a different availability zone or region.

The production solution would also include:

- Scheduled daily backups and more frequent incremental or oplog-based backups
- Point-in-time recovery
- Automated checksum and restore validation
- Regular restore drills
- Execution of the restore Job in an isolated environment
- Alerts and SLO monitoring for backup failures

This approach would remove the current manual script model tied to the host machine and make backup, access control, encryption, retention, and disaster recovery manageable within Kubernetes and cloud infrastructure.

---

## Additional Notes

Use this section for any additional decisions, limitations, or future improvement steps that you would like to highlight.

**Answer:**

This work focused on prioritizing and improving issues that directly affect production operation rather than rewriting the provided application.

Key architectural decisions:

- Docker Compose was used for local validation, and k3d was used for Kubernetes deployment.
- CI automates builds, tests, image creation, and publication to GHCR. Deployment to the local Kubernetes cluster is performed in a controlled manner through `scripts/deploy-local.sh` to avoid exposing the cluster to a GitHub-hosted runner.
- MongoDB was not exposed externally; the backend uses `ClusterIP`, MongoDB uses a headless Service, and the frontend uses NodePort.
- Error handling, readiness behavior, and connection timeout settings were improved to prevent the backend from crashing during MongoDB outages.
- ETL was made idempotent through the `github_id` unique index and upsert approach.
- Backup/restore was verified through both MongoDB and the React interface using a real data-loss scenario.

Under the advanced criteria, verified Slack-based backend alerts and throttling, Trivy image scanning and CycloneDX SBOM generation, and backup/restore with SHA-256 verification and restore evidence were implemented.

The solution was tested in a local Kubernetes environment. Priority next steps for production would be multiple nodes and a MongoDB replica set, HTTPS/TLS, NetworkPolicy, centralized Secret management and automatic rotation, Prometheus/Grafana, centralized logging, GitOps, scheduled remote encrypted backups, and point-in-time recovery.

All technical decisions, setup steps, test results, screenshots, and limitations are documented in the README, `docs/findings.md`, `docs/backup-restore.md`, and `TESLIM_KANITLARI.md`.

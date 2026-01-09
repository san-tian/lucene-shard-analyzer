# Lucene Shard Analyzer Service - DevOps Project

This repository contains the implementation for a DevOps Exercise Project, completed in three main tasks.

## ✅ Task 1: Build & Ship
**Goal**: Build a multi-arch container image and push to GitHub Container Registry (GHCR).

### Implementation Details
- **Multi-Arch Build**: Configured GitHub Actions to build for both `linux/amd64` and `linux/arm64` using QEMU and Docker Buildx.
- **Security Hardening**: Modified the `Dockerfile` to create a system user `appuser` (UID 1000) and run the application as a **non-root user**. Verified via integration tests.
- **Versioning**: Implemented semantic tagging:
    - `latest` (main branch)
    - `sha-<commit_hash>` (traceability)
    - `vX.Y.Z` (releases)

## ✅ Task 2: Kubernetes Deployment & Automated Testing
**Goal**: Deploy to Kubernetes and prove functionality and load balancing with automated tests.

### Implementation Details
- **Manifests**: Created robust `production-ready` manifests:
    - `deployment.yaml`: 3 replicas, resource limits, liveness/readiness probes.
    - `service.yaml`: ClusterIP service for internal load balancing.
- **Integration Test (`test/integration-test.sh`)**:
    - **Requirement Mapping**: The script explicitly maps tests to project requirements (e.g., "Req 2.2 - Traffic Distribution").
    - **Real Functional Test**: Integrated a **real Lucene shard** (`test/sample-shard.tar`) to verify the `/analyze` endpoint actually works (parsing 250+ docs), rather than just checking for HTTP 200.
    - **Load Balancing**: Verifies traffic is distributed across multiple pods using `kubectl exec` to bypass `port-forward` stickiness.

## ✅ Task 3: PR Testing Design (Prototype)
**Goal**: Design a safe way to test Pull Requests in a shared staging cluster.

### Solution: Ephemeral Preview Environments
To address the "Staging Bottleneck" where multiple developers block each other, we designed an **"Ephemeral Namespace"** strategy.

| Component | Implementation Logic & Considerations |
| :--- | :--- |
| **Isolation** | **Why**: Prevents config conflicts (e.g., different env vars). <br> **How**: Create a unique namespace `pr-<number>` for each PR. All deployments are scoped here. |
| **Routing** | **Why**: Developers need to access *their* version, not the main staging one. <br> **How**: Dynamic Ingress with a unique Host header: `http://pr-123.staging.example.com`. |
| **Lifecycle** | **Why**: To prevent resource leakage (cost/performance). <br> **How**: GitHub Actions triggers on `closed` to auto-delete the namespace. |

### Prototype Files
1.  **Deploy Workflow** (`.github/workflows/pr-preview.yml`):
    - Builds a Docker image tagged for the specific PR.
    - Uses `sed`/`envsubst` to inject the unique PR Namespace and Hostname into `deployment.yaml` and Ingress templates.
    - Applies resources to the ephemeral namespace.
2.  **Cleanup Workflow** (`.github/workflows/pr-cleanup.yml`):
    - Triggered on `pull_request: closed`.
    - Deletes the standard `pr-<number>` namespace.
3.  **Ingress Template** (`k8s/preview-ingress-template.yaml`):
    - Acts as a blueprint for dynamic routing rules.

### Simulation vs. Reality
This prototype uses **real production logic** for resource manipulation but simulates the environment connection:
*   **Real Logic**: The commands to dynamically create namespaces, generate secrets, replace image tags, and configure Ingress are ensuring functionality.
*   **Simulated Connection**: The CI workflow uses `helm/kind-action` (or assumes a cluster connection step) as a placeholder. In a real production environment, this would be replaced with `azure/k8s-set-context` or `aws-actions/configure-aws-credentials` to connect to the actual Shared Staging Cluster.

### Advanced Considerations: Microservice Dependencies
While this project is a single service, we designed the architecture to scale for complex microservice dependencies (e.g., Service A ↔ Service B).

#### Scenario 1: Forward Dependency (A depends on B)
*   **Context**: PR is for Service A. It needs to call Service B.
*   **Solution**: **Baseline Sharing**.
    *   We do *not* deploy a copy of B in the PR environment (to save resources).
    *   We configure Service A (via `ExternalName` or ConfigMap) to route traffic to `service-b.staging.svc`.

#### Scenario 2: Backward Dependency (B depends on A)
*   **Context**: PR is for Service A. Service B (running in Staging) calls A.
*   **Challenge**: How does the shared Service B know to call `A(PR-1)` for my request, but `A(PR-2)` for my colleague's?
*   **Solution**: **Header Propagation & Smart Routing (Service Mesh)**.
    1.  **Tagging**: Testing requests carry a header: `x-route: pr-1`.
    2.  **Propagation**: Service B must be coded to forward this header when it calls A.
    3.  **Routing**: A Kubernetes Service Mesh (e.g., Istio) intercepts the call from B. If it sees `x-route: pr-1`, it dynamically routes the request to the `A` in the `pr-1` namespace; otherwise, it falls back to `staging`.

---

## 📖 Operational Guide & Manual Verification

### 1. General Tools
**Docker Compose**
> *Note: In this project's context, `docker compose up` would typically start an OpenSearch container and a dependent curl container for data generation.*
```bash
sudo docker compose up
```

### 2. Manual Task 1 Operations (Build & Local Run)

**Packaging a Shard**
To manually create a shard archive from an Elasticsearch/OpenSearch node:
```bash
# Check indices
curl -s "http://localhost:9200/_cat/indices/test?h=index,uuid"
ls -la ./data/nodes/0/indices/<uuid>

# Create archive
tar -cvf shard.tar data/nodes/0/indices/<index_id>/0
```

**Local Build & Run**
```bash
sudo docker build -t lucene-shard-analyzer:local .

sudo docker run --rm -p 8080:8080 \
  -e APP_VERSION=local \
  -e GIT_SHA=local \
  lucene-shard-analyzer:local
```

**Local API Testing**
| Endpoint | Command | Expected Output |
| :--- | :--- | :--- |
| **Health** | `curl -s http://localhost:8080/healthz` | `ok` |
| **Info** | `curl -s http://localhost:8080/info` | `{"hostname":"...","version":"local"...}` |
| **Metrics** | `curl -s http://localhost:8080/metrics` | Prometheus metrics text |
| **Analyze** | `curl -F "file=@shard.tar" http://localhost:8080/analyze` | JSON Analysis Report |

### 3. Manual Task 2 Operations (K8s Deployment)

**Manual Deployment**
```bash
kubectl config use-context kind-test-cluster # Switch context
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# Check Status
kubectl get pods -l app=lucene-shard-analyzer
kubectl get svc lucene-shard-analyzer
```

**Verification**
```bash
# Option 1: Automated Integration Test (Recommended)
# Automatically checks Health, Metadata, Load Balancing, and Shard Analysis
bash test/integration-test.sh

# Option 2: Manual Checks
# Enable port-forwarding
kubectl port-forward svc/lucene-shard-analyzer 8080:80 

# Test endpoints
curl http://localhost:8080/healthz
curl -F "file=@shard.tar" http://localhost:8080/analyze
```

### 4. Troubleshooting

**❌ Issue: Image Pulling Slow/Stuck**
*   **Symptom**: Pods stuck in `ContainerCreating` for a long time.
*   **Cause**: Kind runs in Docker; it cannot see your host's local Docker images by default and tries to pull from GHCR, which might be slow.
*   **Fix**: Manually preload the image into the Kind node:
    ```bash
    docker exec test-cluster-control-plane crictl pull ghcr.io/san-tian/lucene-shard-analyzer:latest
    ```
*   **Optimization**: Ensure `imagePullPolicy: IfNotPresent` is set in `deployment.yaml`.

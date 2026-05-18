#!/usr/bin/env bash
# ============================================================================
# snyk-monitor-release.sh
# ============================================================================
# Reads the version from package.json and pushes a Snyk monitor snapshot
# tagged with that version as the --target-reference.
#
# This is the building block of long-lived release monitoring:
#   - Each release gets its OWN target in the Snyk dashboard.
#   - That target is monitored INDEFINITELY for newly-disclosed CVEs.
#   - Notifications (Slack / email / Jira) fire when a new CVE affects the
#     pinned dependency set of any monitored release.
#
# Usage:
#   ./scripts/snyk-monitor-release.sh                 # uses package.json version
#   VERSION=1.4.0 ./scripts/snyk-monitor-release.sh   # explicit override
#   PROJECT_NAME=foo ./scripts/snyk-monitor-release.sh
# ============================================================================

set -euo pipefail

# ---------- Config (overridable via env) ------------------------------------
PROJECT_NAME="${PROJECT_NAME:-nodejs-goof}"
SNYK_ORG="${SNYK_ORG:-2c2549f7-de55-4c31-aaea-bea685244487}"
SEVERITY_THRESHOLD="${SEVERITY_THRESHOLD:-low}"

# ---------- Resolve version -------------------------------------------------
if [[ -z "${VERSION:-}" ]]; then
  if ! command -v node >/dev/null 2>&1; then
    echo "ERROR: node not on PATH and VERSION not set." >&2
    exit 1
  fi
  VERSION="$(node -p "require('./package.json').version")"
fi

if [[ -z "${VERSION}" || "${VERSION}" == "undefined" ]]; then
  echo "ERROR: could not determine version from package.json" >&2
  exit 1
fi

TARGET_REF="v${VERSION}"

# ---------- Auth sanity check -----------------------------------------------
if [[ -z "${SNYK_TOKEN:-}" ]]; then
  echo "WARN: SNYK_TOKEN env var not set; relying on prior 'snyk auth'." >&2
fi

echo "==> Monitoring ${PROJECT_NAME} @ ${TARGET_REF} in org ${SNYK_ORG}"

# ---------- SCA (Open Source) snapshot --------------------------------------
echo "--> snyk monitor (Open Source / SCA)"
snyk monitor \
  --org="${SNYK_ORG}" \
  --project-name="${PROJECT_NAME}-sca" \
  --target-reference="${TARGET_REF}" \
  --project-tags=release="${TARGET_REF}",lifecycle=released

# ---------- SAST (Snyk Code) snapshot ---------------------------------------
# Snyk Code uses --report on `snyk code test` to push results to the dashboard
# (Snyk Code does not have a separate `monitor` subcommand).
echo "--> snyk code test --report (SAST)"
snyk code test \
  --report \
  --severity-threshold="${SEVERITY_THRESHOLD}" \
  --org="${SNYK_ORG}" \
  --project-name="${PROJECT_NAME}-sast" \
  --target-reference="${TARGET_REF}" \
  --project-tags=release="${TARGET_REF}",lifecycle=released \
  || echo "(snyk code test exited non-zero; results still uploaded with --report)"

echo "==> Done. View at: https://app.snyk.io/org/${SNYK_ORG}/projects"

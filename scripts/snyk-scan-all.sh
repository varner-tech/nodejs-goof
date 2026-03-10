#!/usr/bin/env bash
#
# Run every Snyk scan type (SCA, SAST, IaC, Container) and upload results
# to the Snyk dashboard under a single target using snykCodeNormaliseRemoteUrl.
#
# Prerequisites:
#   - snyk CLI installed and authenticated (snyk auth)
#   - npm install already run
#   - Docker available (for container scanning)
#
# Usage:
#   ./scripts/snyk-scan-all.sh [--org ORG_ID] [--repo-url REPO_URL] [--skip-container]
#
set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
SNYK_ORG="${SNYK_ORG:-2c2549f7-de55-4c31-aaea-bea685244487}"
REPO_URL="${REPO_URL:-https://github.com/Snyk-Integration-App/nodejs-goof}"
SKIP_CONTAINER=false
SEVERITY="high"
DOCKER_IMAGE="nodejs-goof:latest"

# ── Parse args ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)        SNYK_ORG="$2";   shift 2 ;;
    --repo-url)   REPO_URL="$2";   shift 2 ;;
    --skip-container) SKIP_CONTAINER=true; shift ;;
    *)            echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────
PASS=0
FAIL=0
RESULTS=()

run_step() {
  local label="$1"
  shift
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $label"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  CMD: $*"
  echo ""
  local rc=0
  "$@" || rc=$?
  if [[ $rc -eq 0 ]]; then
    RESULTS+=("PASS  $label")
    ((PASS++))
  else
    RESULTS+=("FAIL  $label  (exit $rc)")
    ((FAIL++))
  fi
  return 0
}

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║              Snyk Full Security Scan — All Products                ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║  Org:       $SNYK_ORG"
echo "║  Repo URL:  $REPO_URL"
echo "║  Severity:  $SEVERITY+"
echo "║  Container: $(if $SKIP_CONTAINER; then echo 'skipped'; else echo "$DOCKER_IMAGE"; fi)"
echo "╚══════════════════════════════════════════════════════════════════════╝"

# ── 0. Preflight ─────────────────────────────────────────────────────────────
run_step "Snyk CLI version" \
  snyk --version

# ── 1. SCA — Local Test ─────────────────────────────────────────────────────
run_step "SCA: snyk test (local, severity=$SEVERITY)" \
  snyk test \
    --severity-threshold="$SEVERITY" \
    --org="$SNYK_ORG"

# ── 2. SCA — Monitor (upload to dashboard) ──────────────────────────────────
# Uses --remote-repo-url so the target matches Snyk Code uploads
# when snykCodeNormaliseRemoteUrl is active.
run_step "SCA: snyk monitor (upload to dashboard)" \
  snyk monitor \
    --org="$SNYK_ORG" \
    --remote-repo-url="$REPO_URL" \
    --project-name="nodejs sca"

# ── 3. SAST — Local Test ────────────────────────────────────────────────────
run_step "SAST: snyk code test (local, severity=$SEVERITY)" \
  snyk code test \
    --severity-threshold="$SEVERITY" \
    --org="$SNYK_ORG"

# ── 4. SAST — Report (upload to dashboard) ──────────────────────────────────
# Uses the same --remote-repo-url as SCA so both land under one target.
run_step "SAST: snyk code test --report (upload to dashboard)" \
  snyk code test \
    --report \
    --severity-threshold="$SEVERITY" \
    --org="$SNYK_ORG" \
    --remote-repo-url="$REPO_URL" \
    --project-name="nodejs sast"

# ── 5. IaC — Local Test ─────────────────────────────────────────────────────
run_step "IaC: snyk iac test (local)" \
  snyk iac test vulnerable.tf \
    --org="$SNYK_ORG"

# ── 6. IaC — Report (upload to dashboard) ───────────────────────────────────
# Uses the same --remote-repo-url as SCA and SAST so it lands under the same target.
# IaC does not support --project-name; the project name is auto-derived from
# the target + filename (e.g. "Snyk-Integration-App/nodejs-goof:vulnerable.tf").
run_step "IaC: snyk iac test --report (upload to dashboard)" \
  snyk iac test vulnerable.tf \
    --report \
    --org="$SNYK_ORG" \
    --remote-repo-url="$REPO_URL"

# ── 7–8. Container ──────────────────────────────────────────────────────────
if ! $SKIP_CONTAINER; then
  run_step "Container: docker build" \
    docker build -t "$DOCKER_IMAGE" .

  run_step "Container: snyk container test (local)" \
    snyk container test "$DOCKER_IMAGE" \
      --file=Dockerfile \
      --severity-threshold="$SEVERITY" \
      --org="$SNYK_ORG"

  run_step "Container: snyk container monitor (upload to dashboard)" \
    snyk container monitor "$DOCKER_IMAGE" \
      --file=Dockerfile \
      --org="$SNYK_ORG" \
      --project-name="container/nodejs-goof"
else
  echo ""
  echo "  (Container scanning skipped — use without --skip-container to include)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                          SCAN SUMMARY                             ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
for r in "${RESULTS[@]}"; do
  printf "║  %-66s ║\n" "$r"
done
echo "╠══════════════════════════════════════════════════════════════════════╣"
printf "║  Total: %d passed, %d failed                                       ║\n" "$PASS" "$FAIL"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo "Some scans found vulnerabilities (expected for this demo project)."
fi

echo "Dashboard: https://app.snyk.io"
echo ""
echo "NOTE: For SCA + SAST to appear under one target, ensure the"
echo "snykCodeNormaliseRemoteUrl feature flag is active on your org."

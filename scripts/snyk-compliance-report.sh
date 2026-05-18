#!/usr/bin/env bash
# ============================================================================
# snyk-compliance-report.sh
# ============================================================================
# Generates a per-release compliance report from the Snyk CLI for a specific
# version / branch reference. Produces both:
#   - reports/compliance/<version>.json   (machine-readable, archivable)
#   - reports/compliance/<version>.md     (human-readable summary)
#
# Intended use case: an auditor or customer asks "show me the current known
# vulnerabilities in v1.2.0 which we shipped to customer X 18 months ago."
# Run this against the corresponding release/v1.2 branch and hand them the
# generated file as evidence.
#
# Usage:
#   ./scripts/snyk-compliance-report.sh                   # uses package.json version
#   VERSION=1.0.0 ./scripts/snyk-compliance-report.sh
# ============================================================================

set -euo pipefail

PROJECT_NAME="${PROJECT_NAME:-nodejs-goof}"
SNYK_ORG="${SNYK_ORG:-2c2549f7-de55-4c31-aaea-bea685244487}"
OUT_DIR="${OUT_DIR:-reports/compliance}"

if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(node -p "require('./package.json').version")"
fi
TARGET_REF="v${VERSION}"

mkdir -p "${OUT_DIR}"
JSON_OUT="${OUT_DIR}/${TARGET_REF}.json"
MD_OUT="${OUT_DIR}/${TARGET_REF}.md"

echo "==> Generating compliance report for ${PROJECT_NAME} @ ${TARGET_REF}"

# ---------- SCA test (JSON) -------------------------------------------------
# `snyk test --json` always exits non-zero when vulns exist; capture and continue.
set +e
snyk test \
  --org="${SNYK_ORG}" \
  --project-name="${PROJECT_NAME}-sca" \
  --target-reference="${TARGET_REF}" \
  --json > "${JSON_OUT}"
SCA_EXIT=$?
set -e

if [[ ${SCA_EXIT} -ne 0 && ${SCA_EXIT} -ne 1 ]]; then
  # Exit 1 = vulns found (expected). Anything else is an actual error.
  echo "ERROR: snyk test failed with exit code ${SCA_EXIT}" >&2
  cat "${JSON_OUT}" >&2 || true
  exit "${SCA_EXIT}"
fi

# ---------- Human-readable summary -----------------------------------------
# Use node to read the JSON and emit markdown (avoids a jq dependency).
node - "$JSON_OUT" "$MD_OUT" "$TARGET_REF" "$PROJECT_NAME" <<'EOF'
const fs = require('fs');
const [,, jsonPath, mdPath, targetRef, projectName] = process.argv;

const raw = fs.readFileSync(jsonPath, 'utf8');
let data;
try { data = JSON.parse(raw); } catch (e) {
  fs.writeFileSync(mdPath, `# Compliance report ${targetRef}\n\nFailed to parse Snyk output.\n`);
  process.exit(0);
}

const projects = Array.isArray(data) ? data : [data];
const lines = [];
lines.push(`# Snyk Compliance Report — ${projectName} ${targetRef}`);
lines.push('');
lines.push(`Generated: ${new Date().toISOString()}`);
lines.push('');

let totalVulns = 0;
const sevCounts = { critical: 0, high: 0, medium: 0, low: 0 };

for (const p of projects) {
  const vulns = p.vulnerabilities || [];
  totalVulns += vulns.length;
  for (const v of vulns) {
    const s = (v.severity || 'low').toLowerCase();
    if (sevCounts[s] !== undefined) sevCounts[s]++;
  }
}

lines.push('## Summary');
lines.push('');
lines.push('| Severity | Count |');
lines.push('|----------|------:|');
lines.push(`| Critical | ${sevCounts.critical} |`);
lines.push(`| High     | ${sevCounts.high} |`);
lines.push(`| Medium   | ${sevCounts.medium} |`);
lines.push(`| Low      | ${sevCounts.low} |`);
lines.push(`| **Total**| **${totalVulns}** |`);
lines.push('');

lines.push('## Findings');
lines.push('');
for (const p of projects) {
  const vulns = p.vulnerabilities || [];
  if (vulns.length === 0) continue;
  for (const v of vulns) {
    lines.push(`### ${v.severity?.toUpperCase() || 'UNKNOWN'} — ${v.title || v.id}`);
    lines.push('');
    lines.push(`- **Package:** \`${v.packageName}@${v.version}\``);
    if (v.identifiers?.CVE?.length) lines.push(`- **CVE:** ${v.identifiers.CVE.join(', ')}`);
    if (v.identifiers?.CWE?.length) lines.push(`- **CWE:** ${v.identifiers.CWE.join(', ')}`);
    if (v.cvssScore != null) lines.push(`- **CVSS:** ${v.cvssScore}`);
    if (v.fixedIn?.length) lines.push(`- **Fixed in:** ${v.fixedIn.join(', ')}`);
    if (v.isUpgradable != null) lines.push(`- **Upgradable:** ${v.isUpgradable}`);
    if (v.isPatchable != null) lines.push(`- **Patchable:** ${v.isPatchable}`);
    if (v.url) lines.push(`- **Reference:** ${v.url}`);
    lines.push('');
  }
}

fs.writeFileSync(mdPath, lines.join('\n'));
console.log(`Wrote ${mdPath}`);
EOF

echo "==> Compliance report ready:"
echo "    JSON: ${JSON_OUT}"
echo "    MD:   ${MD_OUT}"

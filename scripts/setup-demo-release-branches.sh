#!/usr/bin/env bash
# ============================================================================
# setup-demo-release-branches.sh
# ============================================================================
# One-shot helper that creates a series of "release" branches off historical
# commits on main, each with its own pinned version in package.json. The
# resulting branches simulate a product that has shipped multiple long-lived
# versions over time -- exactly the Proconex use case.
#
# After running this script you can either:
#   a) Run scripts/snyk-monitor-release.sh from each branch locally to push
#      snapshots to the Snyk dashboard immediately (fastest demo prep), OR
#   b) Push the branches + tags and let the snyk-release-monitor.yml
#      workflow do it from CI (most realistic demo).
#
# SAFETY:
#   - Aborts if working tree is dirty (commit / stash first).
#   - Skips branches that already exist locally.
#   - Stays on whatever branch you started from when done.
# ============================================================================

set -euo pipefail

if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: working tree is dirty. Commit or stash before running." >&2
  git status --short >&2
  exit 1
fi

START_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo "Starting on branch: ${START_BRANCH}"

# ----------------------------------------------------------------------------
# Pick anchor commits from main's history. We use semantic spacing:
#   v1.0.0  -> oldest "shipped" release (deep in history, lots of CVEs by now)
#   v1.1.0  -> a maintenance release
#   v1.2.0  -> last release on the 1.x line (still supported under LTS contract)
#   v2.0.0  -> current released version
#
# Adjust these SHAs if you re-target a different repo.
# ----------------------------------------------------------------------------
declare -a RELEASES=(
  "1.0.0|f8a1f3b"   # Heroku-era commit; old deps -> rich CVE surface
  "1.1.0|346d3b6"   # Merge pull request #1 (early snyk/master sync)
  "1.2.0|d729daf"   # .snyk policy added (more recent maintenance line)
  "2.0.0|c058391"   # Full Snyk pipeline added (modernized release)
)

for entry in "${RELEASES[@]}"; do
  VERSION="${entry%%|*}"
  SHA="${entry##*|}"
  BRANCH="release/v${VERSION%.*}"   # release/v1.0, release/v1.1, etc.
  TAG="v${VERSION}"

  if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    echo "==> Skipping ${BRANCH}: already exists"
    continue
  fi

  echo "==> Creating ${BRANCH} from ${SHA} (will pin package.json to ${VERSION})"
  git checkout -b "${BRANCH}" "${SHA}"

  # Pin the version in package.json. Use node so we don't depend on jq.
  node -e "
    const fs = require('fs');
    const p = JSON.parse(fs.readFileSync('package.json','utf8'));
    p.version = '${VERSION}';
    fs.writeFileSync('package.json', JSON.stringify(p, null, 2) + '\n');
  "

  git add package.json
  git commit -m "chore(release): pin version ${VERSION} for long-lived monitoring"

  if git show-ref --tags --verify --quiet "refs/tags/${TAG}"; then
    echo "    Tag ${TAG} already exists, skipping tag creation"
  else
    git tag -a "${TAG}" -m "Release ${TAG}"
    echo "    Created tag ${TAG}"
  fi
done

git checkout "${START_BRANCH}"
echo ""
echo "==> Done. Created branches:"
git branch --list 'release/*'
echo ""
echo "==> Tags:"
git tag --list 'v*'
echo ""
echo "Next steps:"
echo "  1) Push: git push origin --all && git push origin --tags"
echo "  2) Or populate the dashboard now without pushing:"
echo "       for b in release/v1.0 release/v1.1 release/v1.2 release/v2.0; do"
echo "         git checkout \$b && npm install --ignore-scripts && ./scripts/snyk-monitor-release.sh"
echo "       done"
echo "       git checkout ${START_BRANCH}"

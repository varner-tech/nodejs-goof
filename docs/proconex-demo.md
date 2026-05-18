# Proconex Demo Runbook

A walkthrough plan and supporting assets for the Tuesday demo. The two
customer asks from the Slack thread were:

1. **Proactively notify them for new CVEs** through configurable notifications.
2. **Use the CLI for reporting on specific branches and legacy versions**
   for compliance (long-lived feature/release branch monitoring).

Everything below is wired to deliver those two stories.

---

## 1. The mental model to lead with

Open the meeting by stating the lifecycle in one breath:

> "Every time you ship a release, your pipeline pushes a *snapshot* of that
> exact dependency tree to Snyk under a target reference like `v1.2.0`.
> From that moment on, Snyk continuously re-evaluates that snapshot against
> every newly-disclosed CVE — *forever* — and routes notifications to Slack,
> email, or Jira based on rules you set. You don't have to re-scan; the
> watching is automatic. You can have v1.0, v1.1, v1.2, and main all
> monitored in parallel as independent targets."

That single paragraph answers both their questions.

Then point out the one footgun:

> "There is one knob to know about: orgs can have a stale-project policy
> that deactivates a target after N days without a CLI push. For legacy
> versions you'll never re-deploy, either disable that policy or run a
> weekly heartbeat job — we've built the heartbeat job into the demo so
> you can see it."

---

## 2. Demo prep checklist

Run these once, before the meeting:

### 2a. Create demo release branches & tags

```bash
# from a clean working tree
./scripts/setup-demo-release-branches.sh
```

This creates four branches off historical commits, each with a pinned
version in `package.json`:

| Branch          | Pinned version | Story to tell                                  |
|-----------------|----------------|------------------------------------------------|
| `release/v1.0`  | 1.0.0          | "Oldest shipped release, customer X still on it" |
| `release/v1.1`  | 1.1.0          | "Maintenance line"                              |
| `release/v1.2`  | 1.2.0          | "Last 1.x LTS branch under compliance contract" |
| `release/v2.0`  | 2.0.0          | "Current GA"                                    |

It also creates `v1.0.0 / v1.1.0 / v1.2.0 / v2.0.0` tags so the
release-pipeline workflow has something to fire on.

### 2b. Populate the Snyk dashboard

You have two ways to do this. Either is fine.

**Option A — push & let CI do it (most realistic for the demo):**

```bash
git push origin --all
git push origin --tags
```

Each tag push triggers `monitor-release-tag` in
`.github/workflows/snyk-release-monitor.yml`, which runs
`scripts/snyk-monitor-release.sh` and creates a separate dashboard target
per version.

**Option B — populate locally, faster, no CI dependency:**

```bash
for b in release/v1.0 release/v1.1 release/v1.2 release/v2.0; do
  git checkout "$b"
  npm install --ignore-scripts
  ./scripts/snyk-monitor-release.sh
done
git checkout main
```

### 2c. Verify the dashboard

Open <https://app.snyk.io/org/varner-tech-engineering/projects> and confirm
you see (at minimum):

- `nodejs-goof-sca` with four target references: `v1.0.0`, `v1.1.0`,
  `v1.2.0`, `v2.0.0`
- `nodejs-goof-sast` with the same set of target references

If the dashboard shows them as separate projects rather than as target
references on a single project, run the monitor commands using the same
`--project-name` (the scripts already do this — just don't override
`PROJECT_NAME`).

### 2d. Confirm notification routing

In the Snyk org settings, confirm the three notification surfaces are
wired up. Walk these in the meeting as part of step 4 below.

- **Slack** — already done. Sanity-check by clicking *Send test message*.
- **Email** — Org settings → Notifications → New issues / weekly digest.
  Decide whose inboxes are on it. Capture screenshots if you want to show
  them config without exposing real recipients.
- **Jira** — Integrations → Jira → connect, then in the project settings
  enable *Fix PR* / *Issue creation* against the Proconex demo project.
  Pick a project key (e.g. `PCDEMO`) so you can demo "open the Jira
  ticket Snyk created."

---

## 3. Live demo script (~15 min)

### Scene 1 — "Here's how a release gets monitored" (3 min)

1. Open `package.json`, point at the `version` field.
2. Open `scripts/snyk-monitor-release.sh`, read out the three key flags:

```bash
snyk monitor \
  --project-name="nodejs-goof-sca" \
  --target-reference="v${VERSION}" \
  --project-tags=release="v${VERSION}",lifecycle=released
```

3. Open `.github/workflows/snyk-release-monitor.yml` and show the two
   triggers: `push: tags: ['v*.*.*']` (release pipeline) and the weekly
   `schedule:` cron (heartbeat).

> "So this is what would slot into your existing release pipeline.
> One bash invocation per release."

### Scene 2 — "Here's what that produces in Snyk" (4 min)

1. Open the Snyk dashboard `Projects` view.
2. Filter to `nodejs-goof-sca`.
3. Show the four target references side by side — point out that each one
   has its own issue count and last-seen-CVE timestamp.
4. Click into `v1.0.0`. Show the issues list. Sort by *Introduced*.

> "Notice these CVEs were disclosed *after* v1.0.0 shipped. We didn't
> re-scan v1.0.0 — Snyk noticed for us."

### Scene 3 — "Here's how you find out" (3 min)

Walk the three notification surfaces. For each, do one of:
- Show a real notification that already fired, or
- Show the config UI and explain the rules.

1. **Slack** — show a `#snyk-alerts` channel message (or post a test).
2. **Email** — show org notification settings and the digest cadence.
3. **Jira** — show a ticket Snyk opened for an issue on `v1.0.0` (you can
   pre-create one by clicking *Open Jira issue* from the issue view).

> "All three surfaces are routable per-project, per-severity. So your
> on-call team can get Slack pings for criticals on `main`, your release
> manager can get a weekly email digest for the LTS branches, and your
> compliance team can get Jira tickets for anything on legacy versions."

### Scene 4 — "And here's the CLI compliance report" (3 min)

This is the answer to Sydney's "CLI for reporting on specific branches and
legacy versions for compliance" ask.

```bash
git checkout release/v1.0
./scripts/snyk-compliance-report.sh
```

This writes:
- `reports/compliance/v1.0.0.json` — raw Snyk output, archivable as audit evidence.
- `reports/compliance/v1.0.0.md` — human-readable summary with severity counts and per-CVE detail.

Open the `.md` in the meeting. Point out:

- Severity table at the top (auditor-friendly).
- Per-CVE entries with CVSS, CWE, package, fix-availability.
- Reproducibility: anyone can re-run the script against any branch
  and produce the same evidence.

> "Bake this into your release-archive job. Every time you ship, this
> file goes into your evidence vault alongside the build artifacts."

### Scene 5 — "And the heartbeat" (2 min)

Open `.github/workflows/snyk-release-monitor.yml` and point at the
`monitor-active-releases` job + the `matrix.branch` list.

> "This is the answer to 'what happens to v1.0 ten years from now.'
> Every Monday, this job re-pushes the snapshot for each version still
> under support. Drop a branch from the matrix when you EOL it; it stops
> getting watched, but the historical issue data stays in the dashboard."

---

## 4. FAQ to be ready for

**Q: How long does Snyk monitor a project once we `monitor` it?**
A: Indefinitely. The snapshot is stored on Snyk's side and re-evaluated
against the vuln DB continuously. New CVEs against your pinned deps
generate notifications until you deactivate the project. Beware the
optional org-level stale-project policy (default 90 days of CLI silence)
— the weekly heartbeat job handles that.

**Q: Does each release count as a separate "project" against our quota?**
A: No. Using `--target-reference` keeps them all under one *project*
(`nodejs-goof-sca`) with multiple targets. This is the same model Snyk
uses for monitoring multiple branches of one repo.

**Q: What if v1.0 has a CVE that's fixed in v1.2?**
A: That's exactly what Snyk surfaces — for each issue on a target, the
issue view shows *Fixed in* version(s). Combined with notifications, this
gives you the "you should upgrade your customers on v1.0 to v1.2" signal
automatically.

**Q: Can we notify different teams about different branches?**
A: Yes. Snyk notification rules can filter on project tags
(`release=v1.0.0,lifecycle=released`) — the monitor script already adds
these tags so you can wire per-version routing in the org's notification
rules.

**Q: What about Snyk Code (SAST) for legacy versions?**
A: `snyk code test --report --target-reference=v1.0.0` does the same
thing for SAST. The monitor script runs both `snyk monitor` (SCA) and
`snyk code test --report` (SAST), so each release target has both
surfaces tracked.

---

## 5. Files referenced in this runbook

- `scripts/snyk-monitor-release.sh` — push a Snyk monitor snapshot for the current `package.json` version.
- `scripts/snyk-compliance-report.sh` — generate an auditor-friendly per-version vuln report (JSON + markdown).
- `scripts/setup-demo-release-branches.sh` — one-shot helper to create `release/v1.0…v2.0` branches and tags for the demo.
- `.github/workflows/snyk-release-monitor.yml` — release-tag pipeline + weekly heartbeat for active releases.
- `.github/workflows/snyk-sca-sast-demo.yml` — existing SCA/SAST scan workflow (already wired with `--target-reference`).

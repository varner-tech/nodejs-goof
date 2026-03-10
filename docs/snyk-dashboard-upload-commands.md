# Snyk: Upload Local Scan Results to the Dashboard

**Validation:** Command syntax verified. Use `snyk auth` or set `SNYK_TOKEN` if you get authentication errors.

---

## Group under one target + scan-type project names

Use the same **target** (e.g. `nodejs-goof`) so all scans appear together, and name **projects** by scan type (`sca/`, `sast`, `iac`, `container/`).

- **Target** = the grouping in the dashboard (one per repo or per `--target-name`).
- **Project** = each scan under that target.

Set `REPO_URL` to your repo (HTTPS). Example:  
`REPO_URL=https://github.com/Snyk-Integration-App/nodejs-goof`

**SCA (Open Source)** — same target via repo URL; set project name explicitly so it doesn’t default to `package.json` `"name"` (e.g. `goof`):
```bash
snyk monitor --all-projects --project-name-prefix="sca/" --remote-repo-url="$REPO_URL"
# If the UI still shows "goof", the project name is coming from package.json "name". Either:
# - Change "name" in package.json to "nodejs-goof", or
# - Run without --all-projects and set the name explicitly:
#   snyk monitor --project-name="sca/nodejs-goof" --remote-repo-url="$REPO_URL"
```

**SAST (Snyk Code)** — set target name to `nodejs-goof`, project name `sast`:
```bash
snyk code test --report --target-name="nodejs-goof" --project-name="sast"
```

**IaC** — same target via repo URL; project name includes app name so it shows as e.g. `nodejs-goof/iac` (file name may still be appended by Snyk):
```bash
snyk iac test vulnerable.tf --report --remote-repo-url="$REPO_URL" --target-name="nodejs-goof/iac"
```

**Containers** — no `--remote-repo-url`/`--target-name` in CLI; the dashboard **group** (e.g. “node”) comes from the **image name** (e.g. `node:18-alpine`). Use `--project-name` so the project row is clear; the parent group name cannot be set from the CLI:
```bash
snyk container monitor <image> --project-name="container/nodejs-goof"
```
To see a different group name (e.g. “nodejs-goof”), monitor an image that includes that in its name (e.g. `your-registry/nodejs-goof:latest`) or rename the target in the Snyk UI if supported.

**Result:** SCA and IaC share the same target (from `--remote-repo-url`, often shown as the repo path e.g. `Snyk-Integration-App/nodejs-goof`). SAST uses `--target-name="nodejs-goof"` so that target appears as `nodejs-goof`. You can rename the repo target to `nodejs-goof` in the Snyk UI (project/target settings) so everything reads the same. Container projects don’t support target linking in the CLI and may show in a separate group; their project name still identifies the scan type (`container/nodejs-goof`).

---

## Minimal commands (no target grouping)

**SCA (Open Source):**
```bash
snyk monitor --all-projects --project-name-prefix="sca/"
```

**SAST (Snyk Code):**
```bash
snyk code test --report --project-name="sast/projectname"
```

**IaC:**
```bash
snyk iac test . --report --target-name="nodejs-goof/iac"
```
*Note: In current CLI (1.1300+), use `--target-name` for the project name; some versions use `--project-name`.*

**Containers:**
```bash
snyk container monitor <image-name> --project-name="container/projectname"
```

Run `snyk auth` first if you see authentication errors.

---

## CLI Upload OS/Code Target Merge (`snykCodeNormaliseRemoteUrl`)

`snyk monitor` (SCA) and `snyk code test --report` (SAST) results previously did not merge into the same Snyk target even when they pointed at the same repo. A fix is now live via the **`snykCodeNormaliseRemoteUrl`** feature flag.

### How it works

- When the FF is active and `target-name` / `remote-repo-url` match between the SCA and Code uploads, both projects appear under a **single target** in the Snyk UI.
- If you don't explicitly set either flag, they match by default.

### Setup checklist

1. **Activate the feature flag** `snykCodeNormaliseRemoteUrl` on your org/group before telling the customer it's fixed.
   - New orgs get it automatically; existing orgs need manual activation (Phase 1 rollout).
2. **Remove duplicate targets** — duplicates are *not* auto-cleaned. Customers must delete them via the Snyk UI or API. (Runbook from the Snyk team forthcoming.)
3. Verify both CLI uploads now land under the same target.

### Current limitations

| Limitation | Status |
|---|---|
| SCM Import + CLI Upload merge | **Not available** — no timeline yet |
| Custom `--target-name` for Open Source CLI | **Not supported** — OS CLI doesn't accept this flag; expected with Dragonfly |

### tl;dr

- Activate `snykCodeNormaliseRemoteUrl` to merge CLI OS + Code uploads into one target.
- Duplicates must be removed manually (API or UI).
- SCM/CLI merge and custom `--target-name` for OS are not yet available.

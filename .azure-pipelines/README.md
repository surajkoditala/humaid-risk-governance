# CI pipelines

Pipelines for the application code (repo on GitHub, pipelines in Azure DevOps): PR
validation, then image build/scan/deploy to dev on merge.

## PR validation

Both run on PRs to `release/1.00` and are **required checks** on that branch (GitHub
branch protection), so a red run blocks the merge. Don't merge until both have finished.

| Pipeline | Runs when the PR touches | Gates |
|---|---|---|
| `workbench/pr-review.yml` | `src/1..4`, `tests`, `webapp` | build, unit tests, webapp build, vulnerable dependencies, AI review |
| `mock-api/pr-review.yml` | `src/6-MockExternalSystems` | generated-SQL drift, build, vulnerable dependencies, AI review |

Semgrep runs too but is informational (JSON is published as a build artifact).

## Image build, scan, and deploy to dev

`workbench/workbench.yml` and `mock-api/mock-api.yml` build the Docker image, push it
to the shared dev ACR, and deploy it to the component's dev Container App. They trigger
on push to a `release/*` branch (excluding `release/dev`) that touches the component's
`src/` paths — not on PRs. Each has one `dev` stage today; `environments/<name>.yml` is
where a future `test`/`prod` stage would be added.

Per component, the stage:
1. Builds the image from the repo root with the component's Dockerfile (`--pull --no-cache`) and pushes it to ACR as `<acrLoginServer>/<image>:<version>-<buildId>` — tagged with the pipeline's build ID, not the git commit SHA.
2. Polls ACR until the tag is visible, then runs Trivy (`aquasec/trivy:0.50.2`) against the image; the job **fails on any HIGH/CRITICAL finding** (an optional `.trivyignore` at the repo root would list accepted exceptions — none exists today), and the readable + JSON reports are published as build artifacts either way.
3. Saves the image as a build artifact (skipped on PR builds, which don't reach this stage anyway since `pr: none`).
4. Deploys: resolves the `id-ca-gh-dev` user-assigned identity (granted `AcrPull` on the registry in `iac`), points the Container App's registry at it, and runs `az containerapp update --image ...` — so the new revision pulls with no registry password. `az containerapp update` itself fails the step if the new revision doesn't provision.
5. On any step failure, the partially-tagged image is deleted from ACR so a failed build doesn't leave a dangling tag behind.

Both components share `azure-cloud` (the same Workload Identity Federation service
connection as `iac`'s deploy pipeline) and the `devResourceGroup`/`devUaiName`/`acrName`
variables in each component's `templates/variables.yml`.

## Layout
```
.azure-pipelines/
  workbench/
    pr-review.yml  prompt.md             # PR checks + what the AI reviewer should know
    workbench.yml                        # build/scan/deploy entry point (push, not PR)
    environments/dev.yml                 # the dev stage: build, Trivy scan, deploy
    templates/deploy.yml  templates/variables.yml
  mock-api/                              # same shape as workbench/
    pr-review.yml  prompt.md
    mock-api.yml
    environments/dev.yml
    templates/deploy.yml  templates/variables.yml
  templates/ai-review.yml                # the 2 AI-review steps, shared (PR pipelines only)
  scripts/dotnet-vuln-check.sh           # fails on vulnerable NuGet packages
  scripts/ai-review/
    review.sh    # PR diff -> Claude (read-only, checkout only) -> ai-review.json
    post.sh      # comments on the PR; fails the build on BLOCKING_ISSUES
    rules.md     # shared reviewer instructions (severity, scope, output)
    schema.json  # structured output the model must return
```

## AI review in one paragraph
On PR builds only, `review.sh` diffs the PR merge commit against its base (limited
to the pipeline's paths) and asks Claude to review it. Claude can Read/Grep/Glob
files **inside the checkout only**, so a malicious diff cannot make it read
secrets. Findings are `blocker` / `major` / `minor`; the verdict is derived from
them by the script (any blocker = `BLOCKING_ISSUES`, any major = `NEEDS_ATTENTION`).
`post.sh` comments on the PR and fails the build only on `BLOCKING_ISSUES`. If the
AI is unavailable the review is skipped, never blocking. It needs the
`ai-review-secrets` variable group (`CLAUDE_CODE_OAUTH_TOKEN`, `GITHUB_PAT`).
The two steps are separate so the step running the model never sees the GitHub token.

To change what gets flagged, edit `scripts/ai-review/rules.md` (all components) or
`<component>/prompt.md` (one component).

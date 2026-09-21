# CI pipelines

PR validation for the application code (repo on GitHub, pipelines in Azure DevOps).
Both run on PRs to `release/1.00` and are meant to be **required checks**, so a red
run blocks the merge. Don't merge until both have finished.

| Pipeline | Runs when the PR touches | Gates |
|---|---|---|
| `workbench/pr-review.yml` | `src/1..4`, `tests`, `webapp` | build, unit tests, webapp build, vulnerable dependencies, AI review |
| `mock-api/pr-review.yml` | `src/6-MockExternalSystems` | generated-SQL drift, build, vulnerable dependencies, AI review |

Semgrep runs too but is informational (JSON is published as a build artifact).
`workbench/workbench.yml` and `mock-api/mock-api.yml` are placeholders for the
image build/deploy pipelines.

## Layout
```
.azure-pipelines/
  workbench/  pr-review.yml  prompt.md   # steps + what the AI reviewer should know
  mock-api/   pr-review.yml  prompt.md
  templates/ai-review.yml                # the 2 AI-review steps, shared
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

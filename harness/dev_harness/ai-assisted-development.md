# AI-Assisted Development Policy

This project uses AI coding assistants (GitHub Copilot, Claude Code, and similar tools). That is
permitted and encouraged, but it is governed. Adapted from the same policy used in
`erc-insurity-integration`, tailored to what this repo actually handles.

## Human-in-the-loop is mandatory
- No AI tool merges its own code. Every change — regardless of how it was drafted — is reviewed
  and explicitly approved by a human engineer before merge.
- Automated review findings (including this repo's own [`dev_harness/`](dev_harness/)) inform the
  human reviewer; they never substitute for one.
- The human reviewer is accountable for the change exactly as if they had written it themselves.
- AI-drafted or AI-assisted commits should carry a `Co-Authored-By:` trailer identifying the tool.

## Readability and comments are not optional
- Code must be readable by any engineer on the team, not just the tool that wrote it.
- Any non-obvious algorithm, ordering dependency, or workaround needs a comment explaining *why*.
- Don't let an assistant leave a complex change undocumented because it "seemed obvious" while
  writing it.

## What an assistant should not be given
This repo does not process third-party licensed content the way `erc-insurity-integration`
processes Verisk rulebook data, so that specific guardrail doesn't apply here verbatim. The
equivalent concern in this repo is:

- **Real customer/PII-shaped data.** The database is seeded with synthetic risk-governance data
  for development; nothing here should ever contain real customer, employee, or regulator-supplied
  content. If a bug can only be reproduced with data that looks like it could be real (not
  synthetic seed data), a human inspects it directly and describes the shape of the problem rather
  than pasting the actual values into a prompt.
- **Secrets.** API keys, connection strings, and Auth0 client secrets are never pasted into a
  prompt or committed — they live in `.env` files (git-ignored) or local `appsettings.Development.
  json`. This is enforced by the "Security" section of `review-rules.md` and this repo's
  `.gitignore`.

## Scope note
This policy, and the `harness/` folder generally, governs **how this repo's own code is
developed**. It is independent of the product's own AI-touchpoint governance (Category Mapping,
Document Extraction, Narrative Drafting), which is documented in `ai/README.md` and
`docs/governance/human-in-the-loop-gates.md` and enforced at runtime, not at review time.

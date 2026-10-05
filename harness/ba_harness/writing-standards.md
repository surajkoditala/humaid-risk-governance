# BA Harness — Writing Standards

This is the single source of truth `ba_harness` checks every epic/story against. It mirrors the
conventions already documented in `CLAUDE.md`'s Azure DevOps Boards section and
`docs/requirements/user-stories.md`.

---

## 1. Work item types and titles

- **Epic** — titled as a short capability name (e.g. `Access Control & Authentication`).
- **Story** — titled `US-<epic>.<n>: <short description>`, matching its position in
  `docs/requirements/user-stories.md`.

## 2. Story format

Every story description must read as:

> As a `[role]`, I want `[capability]`, so that `[benefit]`.

## 3. Acceptance criteria

- Every acceptance criterion must be written as **Given/When/Then**, not a vague bullet.
- Each criterion must be independently testable — avoid combining multiple conditions into one.

## 4. The `[AI]` tagging and pairing rule

- Any story describing an AI-assisted capability (a suggestion, extraction, draft, or score
  produced by the system) must be tagged `[AI]`.
- Every `[AI]`-tagged story **must have a paired human-review story** covering a person reviewing
  and being able to override that AI output. A story proposing an AI capability without its
  review counterpart is incomplete and must be flagged.

## 5. Sensitive data & AI usage (vendor, bank, and product data)

This project handles sensitive vendor, bank, and product data as part of its risk-governance
domain. Any epic/story that involves sending data to an AI/LLM must follow this rule:

- **Default: sensitive vendor, bank, or product data must not be sent to any AI/LLM call.**
  This includes real vendor records, real bank account/routing details, real product/policy
  identifiers, or any other data that could identify a real customer, vendor, or financial
  instrument.
- **If an AI touchpoint genuinely needs data of this shape to function** (for example, to
  demonstrate document extraction or category mapping), the story must explicitly state that
  **only mock/synthetic data** is used for that AI call — never real vendor/bank/product data.
- A story is **non-compliant** if it describes sending real vendor, bank, or product data to an
  AI call without an explicit mock-data substitution, or without a stated reason why the data is
  not actually sensitive.
- This rule applies in addition to, not instead of, the `[AI]` tagging/pairing rule above — an
  AI-touchpoint story can fail this check even if it's correctly tagged and paired.
- When in doubt, the story should default to mock/synthetic data and call that out explicitly,
  rather than remaining silent on data provenance.

## 6. Forward-looking language

Stories must describe something that still needs to be built — not something that already
exists. Avoid "the system already does X" phrasing for undelivered work.

## 7. Tags

- Stories carry a category tag and the parent epic's tag (e.g. `access-control; epic-11`).
- Epics carry only their own category tag.

## 8. Doc-sync rule

Every epic/story created or changed in Azure Boards must be reflected in
`docs/requirements/user-stories.md` to keep the two in sync. The harness does not automate this
step — it's a manual follow-up after any `create`.

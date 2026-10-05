# Test Case Harness

Standards for **creating test cases** — automated, unit, and manual — in this repo (one of three
sub-harnesses under `harness/` — see [`../README.md`](../README.md) for the others).

> **Status: planned.** This folder is scaffolded but not yet populated. Add rules/standards docs
> here as they're written, following the pattern established by `../dev_harness/`.

## Intended contents

| File | Purpose |
|---|---|
| `writing-standards.md` *(planned)* | Naming, structure (Arrange/Act/Assert), coverage expectations, and what belongs in unit vs. automated vs. manual test cases |
| `manual-test-case-template.md` *(planned)* | Template for manual QA test cases |
| `prompts/` *(planned)* | Conversational prompts for drafting test cases from a story/bug description |

## Scope

This is a **development-process** harness: it governs how test cases are written, not the
product's runtime behavior. It is unrelated to `ai/` (the product's own AI harness) and to
`dev_harness/` (code review), though all three may eventually share common conventions.

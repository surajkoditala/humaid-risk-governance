# BA Harness

Standards and tooling for **writing, reviewing, and managing epics/stories** in this repo (one
of three sub-harnesses under `harness/` — see [`../README.md`](../README.md) for the others).

| File | Purpose |
|---|---|
| [`writing-standards.md`](writing-standards.md) | What makes a well-formed epic/story for this repo — required Boards fields, Given/When/Then rule, `[AI]` tagging/pairing rule, doc-sync rule |
| `boards_client.py` | Thin wrapper over the `az boards` / `az devops` CLI (read, query, create, link) |
| `standards.py` | Loads `writing-standards.md` once, so every check is grounded in the same text a human BA reads |
| `graph.py` | The LangGraph itself — review and extract-to-structured-fields nodes |
| `__main__.py` | CLI entrypoint |

Unlike `dev_harness/`, this tool doesn't just report — it can also **create** and **link** work
items directly in Azure Boards, because that's the natural unit of work for a BA (an epic/story
is a Boards item, not a local file).

See [`docs/architecture/ba-harness.md`](../../docs/architecture/ba-harness.md) for a high-level,
non-technical explanation of how this harness works.

## What it does

- **`review`** — checks an existing Boards item (by ID) or a rough draft (from a file) against
  `writing-standards.md`: correct title format, Given/When/Then acceptance criteria, the `[AI]`
  tagging + human-review-pairing rule, tag format, forward-looking phrasing.
- **`create`** — takes a rough draft, reviews it first, converts it into the structured fields
  Boards requires (title, description, acceptance criteria, tags), and creates it as an Epic or
  as a Story linked to its parent Epic. Refuses to create if the review found issues, unless
  `--force` is passed.
- **`list-epics`** / **`list-stories`** — quick read-only listing, useful for checking what
  already exists before drafting something new (avoids duplicate epics/stories).

## Running it

Requires an active Azure DevOps CLI session — this tool never stores or prompts for a PAT itself:

```powershell
az devops login   # paste the PAT (Work Items: Read & write) at the hidden prompt
az devops configure --defaults organization=https://dev.azure.com/Myridius-Insurity organization=humaid-risk-governance
```

Then, using the same Python environment as `ai/langgraph/`:

```powershell
cd harness
..\ai\langgraph\.venv\Scripts\python.exe -m ba_harness review --id 78
..\ai\langgraph\.venv\Scripts\python.exe -m ba_harness review --file drafts\new-story.txt
..\ai\langgraph\.venv\Scripts\python.exe -m ba_harness create --file drafts\new-story.txt --epic 77
..\ai\langgraph\.venv\Scripts\python.exe -m ba_harness list-epics
..\ai\langgraph\.venv\Scripts\python.exe -m ba_harness list-stories --epic 77
```

## After creating or changing anything in Boards

Per `writing-standards.md` and `CLAUDE.md`'s "Keep the docs in sync" rule: mirror the change into
`docs/requirements/user-stories.md` by hand. This harness does not write to that file
automatically — Boards and the docs must agree, but the markdown doc stays human-curated prose,
not a generated artifact.

## Provider

Uses `ai/langgraph/.env`'s `LLM_PROVIDER`, same as `dev_harness/` — switching that `.env` switches
this tool too.

## Known v1 limitations

- `create` does not update `docs/requirements/user-stories.md` — that stays a manual step.
- No bulk operations (e.g. reviewing every story under an epic in one pass).
- The `[AI]`-pairing check only looks at whether the *draft text* mentions a paired human-review
  story — it does not yet check Boards itself for a sibling item under the same epic.

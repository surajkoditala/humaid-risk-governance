# QA session 28 Sep 2026 — defect re-verification and Boards filing

Reference copies of the one-off scripts used on 28 Sep 2026. They were run from a scratch folder, so the absolute paths inside them need adjusting before reuse.

| File | What it did |
|---|---|
| `summarize.mjs` | Joined a Playwright JSON run to the defect register (`tc.defect` annotations) and compared it with the 25 Sep run. |
| `file-bugs.mjs` | Filed DEF-001…DEF-033 as Azure Boards Bugs #99–#125: severity, priority, Parent = Epic, Related = stories. |
| `ux-check.mjs` | Exploratory check at 1440×900: long titles overflowing list tables, user switcher truncation. |
| `ado.py`, `file-ux.py` | REST helper (uses the stored `az devops login` credential, no token in code) and filing of Bugs #126 (DEF-034) and #127 (DEF-025) with screenshots. |
| `filed.json` | DEF id → Boards work-item id for the first batch. |

## Outcome
- Re-run (api + ui-desktop; accessibility, performance and responsive excluded by request) against release/1.00 @ 6112122: 62 passed, 39 failed, 26 skipped (DB checks: no DB access). No status change against 25 Sep.
- DEF-019 (CORS reflects any origin) not filed: US-16.12 AC2 specifies open CORS in dev.
- DEF-028 narrowed: the PDF export has before/after values (US-9.3 met), the on-screen Audit tab does not (US-9.1 AC2).

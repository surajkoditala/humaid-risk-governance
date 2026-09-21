# Prompt: Open-Source Reference Research

Logged for provenance, per this project's convention of keeping AI generation prompts in `/ai` rather than just their output. This predates the team's shipped FFIEC-only framework decision (`CLAUDE.md`, `seed/seed_ffiec_framework.sql`) — see [`open-source-reference-catalog.md`](open-source-reference-catalog.md) for how its findings were reframed as supplementary material once that decision was known, rather than a competing recommendation.

---

## The prompt

```
You are researching reference material for a hackathon project: a "Risk Assessment
Workbench" that helps a fictional large U.S. national bank's Financial Crimes Risk
Management (FCRM) function assess financial-crime risk for business changes (new
products, features, process changes, vendor onboarding, new geographies, new
customer segments) before they launch — replacing an email/spreadsheet-driven
process with a governed platform that takes intake through AI-assisted analyst
review to a risk-committee decision, with a full immutable audit trail.

Hard rule you must respect: the PRODUCT itself will only ever use fully synthetic
data (no real customers, employees, vendors, or case records) — but the risk
category taxonomy the product uses MUST be grounded in a real, named, citable
published supervisory/regulatory framework, not invented categories. Your research
supports both halves: finding the real framework(s) to cite, and finding realistic
open-source/public reference material we can use as a STYLE and STRUCTURE guide
for building believable synthetic data — not as source data to copy in verbatim.

Research and produce a catalog covering these categories:

1. REGULATORY / SUPERVISORY FRAMEWORKS (must be real, must be citable to a specific
   section, not just a top-level document name):
   - FFIEC BSA/AML Examination Manual — find the actual risk category structure
     it uses (e.g. product/service, customer, geographic risk categories) and
     cite specific sections.
   - FATF Recommendations / risk-based approach guidance.
   - OCC, FinCEN, and Federal Reserve guidance on financial crime risk assessment
     and change-management/new-product risk review.
   - Wolfsberg Group principles (correspondent banking, vendor/third-party risk).
   - Note publication dates and confirm each is still current/in force.

2. SAMPLE RISK ASSESSMENT / NEW-PRODUCT-APPROVAL TEMPLATES (public, from regulators,
   consultancies, industry bodies like ACAMS/ABA, or open-source GRC tooling) —
   we want structural/format inspiration (what fields a real risk assessment
   captures), not content to copy.

3. VENDOR / THIRD-PARTY RISK ASSESSMENT QUESTIONNAIRES that are open and reusable
   (e.g. Shared Assessments SIG questionnaire, ISO 27001-aligned vendor risk
   templates) — relevant to our "vendor onboarding" change type.

4. OPEN DATASETS related to financial crime / AML / fraud detection that could
   inform realistic *shape* (field names, value distributions, typical red-flag
   patterns) even if we don't use their actual rows — e.g. IBM AML transaction
   dataset (Kaggle), PaySim synthetic fraud dataset, any public FinCEN SAR
   statistics or typology reports. For each, note its license and whether it's
   synthetic itself or derived from real (anonymized) data.

5. OPEN-SOURCE GRC / COMPLIANCE-WORKFLOW SOFTWARE PROJECTS (GitHub or similar)
   that model a similar domain (case management, risk scoring, audit trails,
   approval workflows) — useful for architecture/domain-model inspiration, not
   for copying code wholesale. Note license (MIT/Apache vs. GPL vs. proprietary)
   since that affects whether we can even reference their structure closely.

6. PUBLIC EXAMPLES OF WRITTEN RISK ASSESSMENT NARRATIVES OR REDACTED REGULATORY
   FINDINGS/CONSENT ORDERS — for tone/language calibration only (how a real FCRM
   narrative reads), explicitly NOT to be reproduced or lightly paraphrased in
   our synthetic data. Flag copyright/sensitivity clearly for anything in this
   category.

For EVERY source found, output a row with:
- Title / name
- URL
- Publisher (regulator, nonprofit, company, individual)
- License / usage terms (public domain, CC-BY, MIT, proprietary/restricted, unclear)
- Category (from the 6 above)
- What we'd actually use it for (a specific mapping, e.g. "RiskCategory taxonomy
  citation" or "SupportingDocument style reference" or "domain model inspiration")
- Confidence this source is authoritative/current (high/medium/low) and why
- Any usage caution (e.g. "summarize only, do not quote directly," "verify
  currency before citing," "GPL-licensed, architecture reference only")

Do not fabricate sources or URLs. If you cannot verify a source is real and
accessible, say so explicitly rather than including it. Prioritize primary
sources (the regulator's own site) over secondary summaries where possible.
Flag anything that looks like it requires legal/compliance sign-off before we
rely on it, given this bank's data is fictional but the frameworks we cite are
real and this catalog may inform how we present the project publicly.

Output as a markdown table (or tables grouped by category), plus a short
"recommended starting set" of 5-10 sources you'd prioritize if we could only
use a handful — and a one-paragraph note on which named framework you'd
recommend we adopt as our primary cited taxonomy, and why.
```

Note on that last paragraph: it asked for a framework recommendation, which the team had in fact already made independently (FFIEC-only) by the time this was reconciled against the shipped code — see the catalog's status note.

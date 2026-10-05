# Open-Source Reference Catalog — Supplementary Research

**Status: reference material, not a competing recommendation.** The team already decided and shipped the risk taxonomy — **FFIEC BSA/AML only**, four hardcoded categories (Products & Services, Customers & Entities, Geographic Locations, Delivery Channels), per `CLAUDE.md` and `seed/seed_ffiec_framework.sql`. This catalog predates that decision and originally explored a broader set of frameworks; it's kept here because most of it is still useful for things the FFIEC-only decision doesn't cover — synthetic data realism, vendor-onboarding-specific fields, and audit/case-management design patterns — not as an argument to revisit the taxonomy itself.

Output of running [`open-source-reference-research-prompt.md`](open-source-reference-research-prompt.md). Conducted via live web search and fetch of primary sources — every entry below was checked against the actual live source, not recalled from training data. Anything that couldn't be independently verified is marked as such rather than presented as confirmed fact.

---

## 1. Regulatory / Supervisory Frameworks

The FFIEC citations below are the same ones already shipped. FATF and Wolfsberg were **not** adopted as part of the taxonomy — kept here only in case the team later wants supplementary citations for correspondent-banking/vendor-specific factors the four FFIEC categories don't spell out in detail.

| Title | URL | Publisher | License/Terms | Use | Confidence | Caution |
|---|---|---|---|---|---|---|
| FFIEC BSA/AML Examination Manual — "BSA/AML Risk Assessment" | https://bsaaml.ffiec.gov/manual/BSAAMLRiskAssessment/01 | FFIEC | U.S. Government work — public domain | The two-step risk-assessment methodology (identify risk categories → analyze) this project's `RiskCategory` model is grounded in | High — fetched live, full text read | None |
| FFIEC Manual — "Risks Associated with Money Laundering and Terrorist Financing" | https://bsaaml.ffiec.gov/manual/RisksAssociatedWithMoneyLaunderingAndTerroristFinancing/00 | FFIEC | Public domain | The full taxonomy source — 26+ named sub-categories under Products/Services, Customers, and Geography, a finer grain than the 4 top-level categories currently seeded; useful if the team ever wants to add sub-category detail within the shipped 4 | High — fetched live, full TOC captured | None |
| OCC Bulletin 2017-43 — New, Modified, or Expanded Bank Products and Services | https://www.occ.treas.gov/news-issuances/bulletins/2017/bulletin-2017-43.html | OCC | Public domain | Citable source for the change-management epic — due diligence/approvals, policies/controls, change management, performance monitoring | High — fetched live; still in effect, amended 2025 (OCC Bulletin 2025-4 struck reputation-risk language) | Cite the amended version, not the 2017 original verbatim |
| Interagency Guidance on Third-Party Relationships: Risk Management (2023) | https://www.occ.gov/news-issuances/bulletins/2023/bulletin-2023-17.html / https://www.federalregister.gov/documents/2023/06/09/2023-12340 | OCC, FDIC, Federal Reserve (joint) | Public domain | Not currently cited anywhere in the shipped code — a real gap-filler for the vendor-onboarding change type's full lifecycle (planning, due diligence, contracting, monitoring, termination) if the vendor module gets extended | High — fetched live, confirmed final June 6, 2023 | None |
| FATF — Guidance for a Risk-Based Approach: The Banking Sector (Oct 2014) | https://www.fatf-gafi.org/en/publications/Fatfrecommendations/Risk-based-approach-banking-sector.html | FATF/OECD | **Copyrighted**, not public domain | Not adopted — kept only as background on the "proportionate, not binary" philosophy behind the shipped residual-risk-never-zero rule | High — fetched live; page itself flags it predates the 2025 revisions to Recommendation 1 | Summarize only, don't reproduce text; note it's the 2014 edition |
| Wolfsberg Financial Crime Principles for Correspondent Banking (2022) | https://db.wolfsberg-group.org/assets/d39a5072-7fb6-4e31-9a87-9e54021ce71f/Wolfsberg%20Correspondent%20Banking%20Principles%202022.pdf | The Wolfsberg Group | Copyrighted, freely published | Not adopted — kept in case the "new geography" change type ever needs correspondent-banking-specific factors beyond the FFIEC Geographic Locations category | High — PDF downloaded and text-extracted directly | Summarize, attribute, don't reproduce full principle text |
| Wolfsberg CBDDQ v1.4 | wolfsberg-group.org/resources | The Wolfsberg Group | Copyrighted but designed for industry-wide free use | Real candidate for extending vendor-onboarding intake fields beyond what `vendor_registry`'s current schema captures | Medium — existence confirmed, primary PDF not independently fetched | Fetch and cite the wolfsberg-group.org original, not a third-party mirror |

## 2. Sample Risk Assessment / New-Product-Approval Templates

| Title | URL | Publisher | License/Terms | Use | Confidence | Caution |
|---|---|---|---|---|---|---|
| Eramba GRC Template Library | https://www.eramba.org/grc-templates | Eramba | Stated as "CC license v4.0" | Structural reference for risk-register/questionnaire/control-mapping fields, if the Configuration module's UI ever needs richer field sets | High — fetched live | Confirm the specific CC variant (BY/BY-SA/BY-NC) before treating as freely reusable |
| ACAMS Risk Assessment (product page) | https://www.stg.acams.org/en/business/acams-risk-assessment | ACAMS | Proprietary commercial software, no public template | Directional inspiration only — confirms inherent × controls × residual is the industry-standard framing the shipped `ScoringService` already follows | Medium | This is a commercial product page — do not imply we used ACAMS' actual tool |

**Gap, stated honestly:** no genuinely open, regulator-authored "new product risk assessment form" template exists — only guidance text describing what one should contain. Not a blocker: the shipped intake form was built directly from FFIEC/OCC structural requirements rather than a third-party template, which was the right call.

## 3. Vendor / Third-Party Risk Assessment Questionnaires

Relevant if `vendor_registry`'s intake fields (currently: risk rating, jurisdiction, data access scope, certification status) ever need to grow.

| Title | URL | Publisher | License/Terms | Use | Confidence | Caution |
|---|---|---|---|---|---|---|
| Shared Assessments SIG Questionnaire | https://sharedassessments.org/ | Shared Assessments (nonprofit) | **Membership-gated**, not free (~$7,200/yr reported) | Structural reference only — 855 questions across 19–21 domains | High that it's real; confirmed via multiple independent secondary sources | Do not use or paraphrase actual question text without a license |
| ISO 27001 Annex A (as referenced by vendor questionnaire templates) | ISO standard is paywalled | ISO / various vendors | ISO text copyrighted/paywalled | Confirms Annex A 5.19–5.21 as the standard anchor for vendor security risk, if a future field set wants to cite it | Low-Medium | Don't copy vendor-branded templates |

## 4. Open Datasets — for realism in future synthetic data batches, not the current seed set

The shipped `seed.sql` (6 customer / 5 product / 4 vendor rows) was hand-authored + Claude-generated directly against FFIEC categories, without drawing on any of these — they weren't needed for the current small, curated set, but are worth knowing about if the demo ever needs a larger or more varied batch.

| Title | URL | Publisher | License | Synthetic or Real? | Use | Confidence |
|---|---|---|---|---|---|---|
| SAML-D | https://www.kaggle.com/datasets/berkanoztas/synthetic-transaction-monitoring-dataset-aml | Berkan Oztas et al. (Bournemouth University, IEEE ICEBE 2023) | CC BY-NC-SA 4.0 | Fully synthetic, built on 28 named typologies (11 normal + 17 suspicious) from literature review + AML specialist interviews | Highest-value dataset here if transaction-level detail is ever added — field names and typology names are strong style material | High — fetched live, license/fields/citation confirmed |
| PaySim | https://www.kaggle.com/datasets/ealaxi/paysim1 | Edgar Lopez-Rojas (academic) | CC BY-SA 4.0 | Synthetic simulator, seeded from a real anonymized/aggregated mobile-money log | Field-name/fraud-injection-logic style reference | High — fetched live |
| FinCEN SAR Stats | https://www.fincen.gov/reports/sar-stats | FinCEN (Treasury) | Public domain | Real aggregate statistics only (no PII) | Published typology names/prevalence (e.g. fraud ~52% of 2024 SARs) — useful if future seed batches want realistically-weighted red-flag variety | High — fetched live |

## 5. Open-Source GRC / Compliance-Workflow Projects — architecture inspiration only

The shipped audit design (append-only, DB trigger blocking UPDATE/DELETE, `func_appendAuditEvent`) already independently converged on the same pattern these two use — listed here for anyone wanting a second reference, not because the shipped design needs changing.

| Title | URL | License | Description | Confidence | Caution |
|---|---|---|---|---|---|
| Jube | https://github.com/jube-home/aml-fraud-transaction-monitoring | AGPL-3.0-or-later (confirmed) | Workflow-driven AML/fraud case management: escalation, full audit trails, versioned document upload | High — license line confirmed in repo | Strong copyleft — reference only, don't fork code in |
| Marble | https://github.com/checkmarble/marble | Elastic License 2.0 (confirmed via actual LICENSE file) | Real-time decision engine + case manager; "unalterable audit logs" tied to workflow/case actions | High — LICENSE text read directly | **Source-available, not OSI open source** — don't call it "open source" in our docs |

## 6. Public Risk-Narrative / Consent-Order Examples — tone calibration only

**Names real institutions and real regulators. Not for reproduction or light paraphrase.** Potentially useful for calibrating `NarrativeDraftingAiClient`'s prompt tone (`ai/prompts/narrative-drafting.md`) if that ever needs refinement.

| Title | URL | Publisher | Status | Use | Confidence | Caution |
|---|---|---|---|---|---|---|
| OCC Consent Order AA-ENF-2025-21 — Community Federal Savings Bank | https://www.occ.gov/static/enforcement-actions/eaAA-ENF-2025-21.pdf | OCC | Public domain (public enforcement record) | Tone/structure calibration for a real BSA/AML deficiency finding | High — confirmed via the PDF's own embedded metadata | Summarize structure only; genericize instead of naming the real institution in anything public-facing |

---

## Sign-off flags for the team

- FATF and Wolfsberg materials are **copyrighted** — cite/summarize/attribute, never reproduce substantial verbatim text publicly, and remember neither is part of the shipped taxonomy.
- SIG questionnaire content is **paywalled** — reference its existence/structure only.
- **Marble is Elastic License 2.0, not OSI open source** — don't call it "open source" in our docs even though it's architecturally useful.
- **Section 6 sources name real institutions in real enforcement actions** — genericize any public-facing reference (repo README, deck) rather than naming the real bank.

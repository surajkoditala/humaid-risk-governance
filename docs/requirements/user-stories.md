# Risk Assessment Workbench — User Stories & Acceptance Criteria

**Prepared for:** Financial Crimes Risk Management (FCRM)
**Document type:** User Stories & Acceptance Criteria (Agile/BRD input)
**Actors:** Product Owner (requestor), FCRM Analyst, Risk Committee Member, System (AI)

---

## How to read this document

- Stories are grouped into **10 epics**, mapped to the functional requirements in the problem statement.
- Each story follows: *As a [actor], I want [capability], so that [outcome].*
- Acceptance criteria use **Given / When / Then** so they're directly testable.
- Stories tagged **[AI]** involve an AI-assisted step — these always pair with a human review/override story, since no output is allowed to go live without a human decision.
- Open questions or assumptions worth validating with stakeholders are called out inline as `> Assumption:` or `> Open question:`.

---

## Epic 1 — Change Request Intake

**Goal:** Replace email/SharePoint intake with a structured, trackable entry point.

### US-1.1 — Submit a change request
*As a Product Owner, I want to submit a change request through a structured form that pulls in what the bank's systems already know, so that FCRM has everything needed to start an assessment without back-and-forth email or me re-typing data that already exists elsewhere.*

**Acceptance Criteria**
- Given I am a logged-in Product Owner, when I start a new request, then I must select exactly one change type: Product, Feature, Process, Vendor, Geography, or Customer Segment.
- Given I select a change type with a corresponding system of record (Customer Segment → CRM, Product/Feature/Geography → Core Banking, Vendor → Vendor Management), when I identify the relevant customer, product, or vendor, then the system retrieves that record from the bank's system of record and automatically populates the type-specific risk fields (e.g. vendor jurisdiction, data access scope, and risk rating; customer segment and KYC status; product features and geography) — I don't manually re-key data the bank already has.
- Given the change type is Process, or a Vendor request names a vendor not yet in the system of record, when the form loads, then I provide the relevant details directly, since no existing record applies.
- Given I have not filled all mandatory fields, when I try to submit, then the system blocks submission and lists missing fields.
- Given I submit successfully, when the request is created, then it receives a unique, immutable request ID and timestamp, links to the retrieved system-of-record snapshot (where one was pulled), and enters status "Submitted."
- Given a request is submitted, when I view it later, then I can see its current status (Submitted / In Assessment / Pending Committee / Decisioned) at all times.

> Assumption: a Vendor request naming a vendor not yet in Vendor Management falls back to manual entry rather than blocking submission until the vendor is pre-registered — new-vendor onboarding is a legitimate use of this change type. Confirm this stays the desired fallback.

### US-1.2 — Attach supporting documents
*As a Product Owner, I want to attach supporting documents (product specs, vendor contracts, process diagrams) to my request, so that the analyst has source material without a separate email thread.*

**Acceptance Criteria**
- Given I am completing a request, when I attach a file, then the system accepts common formats (PDF, DOCX, XLSX) and rejects unsupported/unsafe formats with a clear message.
- Given I attach multiple documents, when I submit, then all documents are linked to the request ID and versioned (not overwritten) if replaced later.
- Given a document is attached, when it is stored, then it is retained for the life of the request and available for audit reconstruction later.

### US-1.3 — Track my request status
*As a Product Owner, I want to see where my request stands, so that I don't have to email FCRM for updates.*

**Acceptance Criteria**
- Given I have submitted a request, when I open my dashboard, then I see all my requests with current status and days elapsed since submission.
- Given a request changes status, when the change occurs, then I receive a notification (in-app and/or email).
- Given a request is returned to me for clarification, when I view it, then I see specifically what is being asked and by whom.

> Assumption: Product Owners cannot see internal analyst notes/scoring rationale, only status and any formal clarification requests. Confirm this visibility boundary with FCRM leadership.

---

## Epic 2 — Risk Categorization & Framework Mapping

**Goal:** Ensure every assessment is decomposed against a named, citable supervisory framework — not ad hoc judgment.

### US-2.1 — Auto-map request to risk categories **[AI]**
*As an FCRM Analyst, I want the system to propose which supervisory risk categories apply to a submitted change, so that I don't start from a blank page for every request.*

**Acceptance Criteria**
- Given a request is submitted, when the system processes it, then it proposes applicable risk categories drawn from a configured, named framework (e.g. FFIEC BSA/AML Examination Manual categories, FATF risk categories).
- Given the request has a linked system-of-record snapshot (pulled at intake per US-1.1), when categories are proposed, then the mapping is grounded against that retrieved data (e.g. actual vendor jurisdiction, actual product geography) rather than only the free-text description — reducing the chance of a plausible-sounding but factually wrong proposal.
- Given the system proposes categories, when I view the proposal, then each category shows a citation back to the specific framework section it came from.
- Given no framework mapping is configured for a change type, when the system cannot propose categories, then it flags this explicitly rather than guessing silently.

### US-2.2 — Override the proposed risk categories
*As an FCRM Analyst, I want to add, remove, or adjust the proposed risk categories, so that the assessment reflects my professional judgment, not just the AI's first pass.*

**Acceptance Criteria**
- Given the system has proposed categories, when I remove or add a category, then I am required to enter a reason before the change is saved.
- Given I override a category mapping, when the assessment is finalized, then both the original AI proposal and my final selection (with reason) are retained, not overwritten.

> Assumption: The framework source (FFIEC, FATF, or an internal equivalent) is configurable per jurisdiction/product line, since a bank with international operations may need more than one reference framework. Confirm which framework(s) apply at which entity level.

---

## Epic 3 — AI-Assisted Policy Research

### US-3.1 — Surface relevant internal policy **[AI]**
*As an FCRM Analyst, I want the system to surface internal policies, procedures, and prior related assessments relevant to this request, so that I don't manually search SharePoint.*

**Acceptance Criteria**
- Given a request with mapped risk categories, when I open the assessment workspace, then the system displays a ranked list of relevant policy documents and past assessments, each with a relevance rationale.
- Given a surfaced policy document, when I click it, then I can view the source document and its version/effective date (not a stale cached copy).
- Given the system finds no relevant policy for a category, when I view that category, then it is explicitly marked "no matching policy found" rather than left blank or guessed.

### US-3.2 — Confirm or reject surfaced policy
*As an FCRM Analyst, I want to mark which surfaced policies I actually relied on, so that the audit trail reflects my real reasoning, not everything the system happened to retrieve.*

**Acceptance Criteria**
- Given a list of surfaced policies, when I mark one as "relied upon" or "not relevant," then that decision is recorded against the assessment.
- Given I finalize the assessment, when I have not reviewed at least one surfaced policy per mapped risk category, then the system warns me before allowing finalization.

---

## Epic 4 — AI-Assisted Document Extraction

### US-4.1 — Extract structured data from submitted documents **[AI]**
*As an FCRM Analyst, I want the system to pull key structured facts out of submitted documents (e.g. vendor jurisdiction, data flows, customer types affected), so that I don't manually re-key information from PDFs.*

**Acceptance Criteria**
- Given a request with attached documents, when extraction runs, then the system populates a structured summary (key-value fields relevant to the change type) alongside a pointer to the exact source page/section for each extracted value.
- Given an extraction fails or is low-confidence for a field, when I view the summary, then that field is flagged as "needs manual review" rather than silently left with a guessed value.
- Given extraction completes, when I view results, then original documents remain fully accessible unmodified — extraction never alters source documents.

### US-4.2 — Correct extracted data
*As an FCRM Analyst, I want to correct any extracted field, so that inaccurate extraction doesn't propagate into the risk assessment.*

**Acceptance Criteria**
- Given an extracted field, when I edit its value, then I must provide a reason if the edit materially changes the field's meaning (not required for trivial formatting fixes — see Epic 6 for override rules).
- Given I edit an extracted field, when I save, then both the original AI-extracted value and my corrected value are retained in the audit trail.

---

## Epic 5 — AI-Drafted Risk Assessment

### US-5.1 — Generate a draft risk assessment **[AI]**
*As an FCRM Analyst, I want the system to generate a first-draft risk assessment (narrative + preliminary ratings) from the mapped categories, retrieved policy, and extracted document data, so that I start from a draft instead of a blank document.*

**Acceptance Criteria**
- Given risk categories are mapped and documents are extracted, when I request a draft, then the system produces a narrative assessment per risk category, each narrative citing the specific policy or document facts it drew from.
- Given a draft is generated, when I view it, then it is clearly labeled "AI-drafted — pending analyst review" and cannot be routed to committee in this state.
- Given a draft references a fact not found in the source documents or policy, when this occurs, then the system does not fabricate a citation — it either flags the statement as unsupported or omits it.

> Assumption: The AI draft is generated per risk category (not one monolithic narrative), so an analyst can accept, edit, or fully rewrite one category's narrative independently of others. Confirm this granularity is what analysts expect.

### US-5.2 — Regenerate a section with feedback
*As an FCRM Analyst, I want to ask the system to redraft a specific section with my guidance, so that I can iterate without starting the narrative from scratch.*

**Acceptance Criteria**
- Given a draft narrative section, when I provide feedback and request regeneration, then only that section is regenerated — other finalized sections are untouched.
- Given a section is regenerated, when I view it, then the prior version remains retrievable in the audit history.

---

## Epic 6 — Analyst Review, Edit & Override

**Goal:** Make human override a first-class, always-reasoned action — never a silent overwrite.

### US-6.1 — Edit any AI-generated output
*As an FCRM Analyst, I want to edit any AI-generated content (category mapping, extracted fields, draft narrative, preliminary score), so that my professional judgment is the final word before anything reaches committee.*

**Acceptance Criteria**
- Given any AI-generated field or narrative, when I edit it, then the system prompts me for a reason for the change before the edit is saved.
- Given I decline to provide a reason, when I try to save, then the system blocks the save and re-prompts (reason is mandatory, not optional).
- Given an edit is saved, when I view the field's history, then I can see: original AI output, edited value, who edited it, when, and the stated reason — in full, not truncated.

### US-6.2 — View full edit/override history on any assessment
*As an FCRM Analyst (or auditor/examiner), I want to see the complete history of AI outputs and human overrides for any assessment, so that I can reconstruct exactly how a conclusion was reached.*

**Acceptance Criteria**
- Given a finalized assessment, when I open its history view, then every field shows a chronological chain of versions with actor, timestamp, and reason for each change.
- Given the history view, when I export it, then the export is a faithful, complete copy suitable for handing to an examiner (see Epic 9 for full audit trail requirements).

### US-6.3 — Finalize the assessment
*As an FCRM Analyst, I want to formally mark an assessment as finalized, so that it can move to committee only once I've reviewed everything.*

**Acceptance Criteria**
- Given an assessment has outstanding AI-drafted sections not yet reviewed by me, when I try to finalize, then the system blocks finalization and lists what's outstanding.
- Given all sections are reviewed (accepted as-is or edited), when I finalize, then the assessment locks from further edits by the Product Owner and enters "Pending Committee" status.
- Given I finalize an assessment, when this occurs, then my identity and timestamp are recorded as the finalizing analyst — this cannot be anonymous or attributed to "system."

---

## Epic 7 — Risk Scoring Engine

**Goal:** Score in a way where controls reduce but never zero out inherent risk.

### US-7.1 — View calculated risk score with breakdown
*As an FCRM Analyst, I want to see the calculated risk score along with how it was derived (inherent risk × applicable controls), so that the number is explainable, not a black box.*

**Acceptance Criteria**
- Given an assessment with mapped risk categories, when the score is calculated, then I see an inherent risk rating per category and a separate mitigated/residual rating after controls are applied.
- Given any control is applied, when I inspect the math, then the residual risk score is always greater than zero — the scoring model must not allow a control (or combination of controls) to reduce a category's residual risk to zero or "no risk."
- Given a residual score is displayed, when I view it, then I can trace which specific controls were credited and each control's configured mitigation weight.

### US-7.2 — Override a calculated score
*As an FCRM Analyst, I want to override the system-calculated score for a category, so that my judgment can account for factors the model doesn't capture.*

**Acceptance Criteria**
- Given a calculated score, when I override it, then I must provide a reason, and both the calculated and overridden values are retained.
- Given an overridden score, when the assessment is viewed later, then it is visually distinguishable from a system-calculated score (e.g. labeled "Analyst override").

> Open question: Should overridden scores require a secondary approval (e.g. senior analyst sign-off) before an assessment can be finalized, or is single-analyst override sufficient given the committee reviews it afterward? Recommend confirming with FCRM governance — this affects Epic 8 design too.

---

## Epic 8 — Committee Review & Voting

### US-8.1 — Route a finalized assessment to committee
*As an FCRM Analyst, I want to route a finalized assessment to the risk committee, so that it enters the formal decision queue.*

**Acceptance Criteria**
- Given an assessment is finalized, when I route it, then it appears in the committee's queue with all narrative, scores, and supporting documents attached and read-only.
- Given an assessment is routed, when this occurs, then status changes to "Pending Committee" and the Product Owner is notified their request is under committee review.

### US-8.2 — Cast a committee vote
*As a Risk Committee Member, I want to review a finalized assessment and cast a vote (approve / reject / defer / approve-with-conditions), so that a formal, accountable decision is recorded.*

**Acceptance Criteria**
- Given I open an assessment in my queue, when I review it, then I can see the full narrative, scores, cited policy, and analyst override history before voting.
- Given I select "approve-with-conditions," when I vote, then I must enter the specific conditions as structured text — this cannot be submitted blank.
- Given I select "defer," when I vote, then I must state what additional information or action is needed before re-review.
- Given I select "reject," when I vote, then I must state the reason.
- Given multiple committee members vote, when votes are cast, then each member's individual vote and rationale is recorded separately — votes are never aggregated into a single anonymous outcome without preserving the individual record.

> Open question: Is committee decisioning by majority vote, unanimous consent, or a designated chair's final call after discussion? This materially affects workflow design and should be confirmed with committee governance documentation.

### US-8.3 — Record the final committee decision
*As an FCRM Analyst, I want the committee's final decision automatically reflected on the request, so that the Product Owner and audit trail immediately show the outcome.*

**Acceptance Criteria**
- Given all required committee votes are cast, when the decision resolution rule (per configuration) is met, then the request status updates to Approved / Rejected / Deferred / Approved-with-Conditions.
- Given a decision is recorded, when this occurs, then the Product Owner is notified with the decision and, if applicable, the stated conditions.
- Given an assessment is approved-with-conditions, when I view the request later, then the conditions remain visibly attached to the request record (not just in a vote comment) for future reference.

---

## Epic 9 — Immutable Audit Trail

### US-9.1 — Reconstruct the full history of any request
*As an Auditor/Examiner (or FCRM Analyst preparing for exam), I want to pull a complete, chronological history of any request, so that I can answer "why was this rated this way" months or years later without hunting through email.*

**Acceptance Criteria**
- Given any request ID, when I request its full history, then I receive every event in order: submission, document uploads, AI outputs generated, every human edit/override with reason, policy citations relied upon, score calculations, routing, individual committee votes, and final decision.
- Given a history record, when I view any entry, then it shows actor (human name or "system/AI"), exact timestamp, and the before/after state of whatever changed.
- Given the audit trail is exported, when I generate the export, then it is provided in a durable, human-readable format (e.g. PDF or equivalent) suitable for handing directly to an examiner without additional formatting work.

### US-9.2 — Guarantee immutability
*As FCRM Leadership, I want the audit trail to be tamper-evident and non-editable after the fact, so that the record itself is defensible under examination.*

**Acceptance Criteria**
- Given an audit record is written, when any user (including administrators) attempts to alter or delete it, then the system prevents this — corrections happen only via new, additive entries, never in-place edits.
- Given a system or configuration change affects scoring or workflow rules, when the change is made, then it is itself logged with who made it, when, and why (see Epic 10), so historical assessments remain interpretable against the rules that applied at the time.

> Assumption: "Immutable" means write-once/append-only at the data layer, not merely restricted by application-level permissions. This is a technical/architecture implication worth flagging to the engineering team explicitly, since it affects the data store choice.

---

## Epic 10 — Platform Configuration (Analyst-Owned)

### US-10.1 — Configure scoring parameters
*As an FCRM Analyst (with configuration privileges), I want to adjust scoring parameters (category weights, control mitigation values, rating thresholds) without a code change, so that the model can be tuned as regulatory expectations evolve.*

**Acceptance Criteria**
- Given I have configuration access, when I adjust a scoring parameter, then the change requires a stated reason and takes effect only for assessments started after the change (existing in-flight assessments are unaffected unless explicitly re-run).
- Given I attempt to set a control mitigation value that would allow residual risk to reach zero, when I save, then the system rejects the configuration with an explanit error (enforces the "never fully eliminate" constraint at the configuration layer, not just at calculation time).
- Given a scoring parameter is changed, when this occurs, then the change is itself an audit event (who, when, old value, new value, reason).

### US-10.2 — Configure workflow rules
*As an FCRM Analyst (with configuration privileges), I want to adjust workflow rules (e.g. which change types require committee vs. senior-analyst-only sign-off, escalation thresholds, required committee quorum), so that the platform adapts to policy changes without engineering involvement.*

**Acceptance Criteria**
- Given I have configuration access, when I view workflow rules, then I see current rules in plain, structured form (not buried in code or a database table only engineers can read).
- Given I change a workflow rule, when I save, then the system requires a reason and logs the change as an audit event.
- Given a workflow rule change is saved, when it takes effect, then in-flight requests follow the rules that were active when they were submitted (unless the change is explicitly marked retroactive) — so no request's process silently changes mid-flight.

> Open question: Who has authority to approve configuration changes to scoring/workflow — is analyst self-service sufficient, or does this need a second-analyst/manager approval step given it affects every future assessment? Worth confirming given how consequential these parameters are.

---

## Summary: Requirements Traceability

| Functional Requirement (from problem statement) | Epic(s) |
|---|---|
| Intake change request with defined types | Epic 1 |
| Decompose into risk categories from supervisory framework | Epic 2 |
| Retrieve/surface relevant policy | Epic 3 |
| Extract structure from submitted documents | Epic 4 |
| Draft risk assessment for analyst review | Epic 5 |
| Analyst edit/override with reason (first-class) | Epic 6 |
| Score: controls mitigate, never eliminate | Epic 7 |
| Route to committee, recorded vote | Epic 8 |
| Full immutable audit trail | Epic 9 |
| Tunable scoring/workflow configuration | Epic 10 |

## Open Questions Requiring Stakeholder Input (consolidated)

1. What visibility do Product Owners have into analyst reasoning/scoring (Epic 1)?
2. Which named framework(s) apply, and does this vary by jurisdiction or business line (Epic 2)?
3. Does a scoring override require secondary sign-off before finalization (Epic 7)?
4. Is committee decisioning majority vote, unanimous, or chair-decided (Epic 8)?
5. Who has authority to approve scoring/workflow configuration changes (Epic 10)?

---

*Next suggested steps: non-functional requirements (performance, security, data retention, access control), a data model / entity relationship diagram, and role-based permission matrix.*

# Risk Assessment Workbench — User Stories & Acceptance Criteria

**Prepared for:** Financial Crimes Risk Management (FCRM)
**Document type:** User Stories & Acceptance Criteria (Agile/BRD input)
**Actors:** Product Owner (requestor), FCRM Analyst, Risk Committee Member, System (AI), Platform Engineer (mock systems)

---

## How to read this document

- Stories are grouped into epics. Epics 1–10 map to the functional requirements in the problem statement; Epic 14 (mock external systems and data ingestion) was added from the Platform Ecosystem Diagram (`docs/architecture/ecosystem-diagram.md`) and is deterministic integration, not an AI touchpoint.
- Numbering note: Epics 11–13 (Access Control, Deployment and Operations, Non-Functional Requirements) and US-9.3 (examiner-ready audit export) are tracked in Azure Boards but are not yet written up in this document, which is why Epic 14 follows Epic 10 here.
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
- Given I select a change type with a corresponding system of record (Customer Segment → CRM, Product/Feature/Geography → Core Banking, Vendor → Vendor Management), when I identify the relevant customer, product, or vendor, then the system retrieves that record from the bank's system of record and automatically populates the type-specific risk fields (e.g. vendor jurisdiction, data access scope, and risk rating; customer segment and KYC status; product features and geography) — I don't manually re-key data the bank already has (the mock systems, lookup, and snapshot behind this are specified in Epic 14).
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

## Epic 14 — Mock External Systems & Data Ingestion

**Goal:** Stand in for the bank's existing CRM, Core Banking, and Vendor Management systems with synthetic, separately-deployed mock systems, and give the Workbench one controlled path to them — so a change request is built from what the bank's systems already hold, and the committee's decision flows back to them, instead of people re-keying data in both directions.

> Origin: added from the Platform Ecosystem Diagram, not the original brief. The brief's constraint — "Synthetic data only. No connection to any real system" — is what makes the mocks necessary. No story in this epic makes a runtime AI call; it is deterministic integration, which is why none is tagged **[AI]**.

### US-14.1 — Stand up the mock CRM, Core Banking, and Vendor Management systems
*As a Platform Engineer, I want the CRM, Core Banking, and Vendor Management systems stood up as one separately-deployed mock service with its own data store, so that the Workbench integrates with external systems the way it would in production, without any connection to a real one.*

**Acceptance Criteria**
- Given the mock service is running, when a client requests customers, products, or vendors, then each is served through its own API (list, and get by ID) from a data store separate from the Workbench's own schema.
- Given any Workbench component other than the Data Ingestion Layer, when it needs mock-system data, then it cannot read the mock schema or call the mock service directly — the Data Ingestion Layer is the only permitted path, and only over the service's API.
- Given any record in the mock systems, when I inspect it, then it is 100% synthetic — no real customer, product, vendor, or company data.
- Given the mock service's schema and seed data, when they are (re)applied, then one documented command reproduces the same state.

### US-14.2 — Give each mock record the fields the risk framework scores against
*As an FCRM Analyst, I want each customer, product, and vendor record to carry the risk-relevant fields the assessment needs, so that a request built from them has real risk context instead of a bare name.*

**Acceptance Criteria**
- Given a customer record, when I view it, then it carries customer type, geography, segment classification, and KYC/onboarding status.
- Given a product record, when I view it, then it carries product type, features/limits, geography, and launch/change type.
- Given a vendor record, when I view it, then it carries vendor risk rating, jurisdiction, data access scope, and certification status.
- Given a field with a constrained set of allowed values (e.g. KYC status, vendor risk rating, certification status), when a record is written with a value outside that set, then the store rejects it rather than coercing or silently accepting it.

### US-14.3 — Look up an existing customer, product, or vendor when starting a request
*As a Product Owner, I want to search for and select the relevant existing customer, product, or vendor when I start a change request, so that I identify a real record instead of describing it from memory.*

**Acceptance Criteria**
- Given I select Customer Segment, Product, Feature, Geography, or Vendor as the change type, when the intake form loads, then I am offered a list of matching records from the relevant mock system (customers for Customer Segment; products for Product, Feature, and Geography; vendors for Vendor).
- Given I select a record, when I view the form, then I can see the details retrieved for it before I submit, so I can confirm it is the right one.
- Given I select Process as the change type, when the form loads, then no lookup is offered (there is no system of record for a process) and I provide the details directly.
- Given I am submitting a Vendor request for a vendor that is not in the list, when I proceed, then I can enter the vendor's details directly rather than being blocked — new-vendor onboarding is a legitimate use of this change type.

> Open question: Geography changes have no natural system of record — the current design approximates them by linking to an affected product. Confirm that is acceptable, or decide whether Geography should be entered directly like Process.

### US-14.4 — Ingest and snapshot the linked record at intake
*As an FCRM Analyst, I want the linked record's data captured as an immutable snapshot when the request is submitted, so that the assessment reflects what the bank's systems said at that moment even if the source record changes later.*

**Acceptance Criteria**
- Given a request is submitted with a linked record, when the Data Ingestion Layer runs, then it retrieves the record from the relevant mock system and stores a snapshot against the change request, with the time it was ingested.
- Given a snapshot has been stored, when the source record in the mock system later changes, then the request's snapshot is unchanged — a request has no snapshot or exactly one, and it is never updated.
- Given any Workbench component needs the external data (AI category mapping, scoring, analyst UI), when it reads it, then it reads the stored snapshot only, never the mock system directly.
- Given a request has no linked record (e.g. a Process change), when it is submitted, then no snapshot is created and this is not treated as an error.
- Given the mock systems are unreachable at intake, when a request is submitted, then the request is still created (intake does not depend on the mock systems being up), the failure is logged, and category mapping falls back to the change type and description alone.
- Given linked IDs were supplied but none resolve to a record (e.g. stale IDs), when the request is submitted, then no snapshot is stored.

> Open question: with mock-system data now the primary intake path, should an unreachable mock system still let intake proceed with no external context (current behavior), or block submission until it is back? Also: the stored snapshot is currently its own record — retrieval is not written to the Epic 9 audit trail as a separate event. Decide whether it should be.

### US-14.5 — Push the committee decision back to the source system
*As a Risk Committee Member, I want the committee's final decision reflected back in the system the request originated from, so that nobody has to re-key an outcome that has already been decided.*

**Acceptance Criteria**
- Given a request was linked to a product, when the committee decision is recorded, then a go-live flag (true for Approved and Approved-with-Conditions, false otherwise) and a risk-rating summary are sent to that product record in Core Banking.
- Given a request was linked to a vendor, when the decision is recorded, then an updated risk-rating summary is sent to that vendor record in Vendor Management; given it was linked to a customer, then a customer/segment risk flag is sent to that customer record in CRM.
- Given a request has no linked record, when the decision is recorded, then nothing is pushed and this is not treated as an error.
- Given no committee decision has been recorded, when the system is running, then nothing is ever pushed — the push-back originates only from a recorded human decision, never from the system's own initiative.
- Given a push succeeds, when it completes, then it is written to the audit trail as an event by "system", including what was sent.
- Given the mock systems are unreachable when the decision is recorded, when the push fails, then the decision itself still stands — a decision that is already final is never undone or blocked by a failed push-back — and the failure is logged.

> Open question: today only a successful push is written to the audit trail; a failed one is logged operationally but not audited or retried, so the source system can silently end up out of sync with a final decision. Decide whether failures should be audited and retried, or flagged for manual reconciliation.

### US-14.6 — Generate the mock data synthetically and reproducibly
*As a Platform Engineer, I want the mock systems' data produced by a documented, repeatable process, so that the demo has one reliable golden path plus realistic variety, and reviewers can see how it was made.*

**Acceptance Criteria**
- Given the seed dataset, when I review it, then it includes one hand-authored golden-path set (a coherent customer, product, and vendor that walk the full lifecycle end to end) plus additional AI-assisted rows spanning a risk spectrum, not all high-risk or all low-risk.
- Given the AI-assisted rows, when I look in `/ai/data-generation`, then the brief that produced them is logged alongside the approach.
- Given the dataset, when I review it, then it includes deliberate edge cases: a customer/product pairing that maps cleanly onto no framework category, and a vendor with no certification.
- Given a seed row, when it is applied, then it must satisfy the schema's constraints — an invalid row fails the insert instead of being silently corrected.

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
| Source intake data from, and return decisions to, the bank's existing systems (mock CRM / Core Banking / Vendor Management) — *from the Platform Ecosystem Diagram, not the original brief; the brief's "synthetic data only, no real system" constraint is what requires them to be mocks* | Epic 14 |

## Open Questions Requiring Stakeholder Input (consolidated)

1. What visibility do Product Owners have into analyst reasoning/scoring (Epic 1)?
2. Which named framework(s) apply, and does this vary by jurisdiction or business line (Epic 2)?
3. Does a scoring override require secondary sign-off before finalization (Epic 7)?
4. Is committee decisioning majority vote, unanimous, or chair-decided (Epic 8)?
5. Who has authority to approve scoring/workflow configuration changes (Epic 10)?
6. Geography changes have no natural system of record — approximate via an affected product (current), or enter directly like Process (Epic 14, US-14.3)?
7. With mock-system data now the primary intake path, should an unreachable mock system still let intake proceed with no external context, or block submission? And should snapshot retrieval be its own Epic 9 audit event (Epic 14, US-14.4)?
8. Should a failed decision push-back be audited and retried or flagged for manual reconciliation, rather than only logged (Epic 14, US-14.5)?

---

*Next suggested steps: non-functional requirements (performance, security, data retention, access control), a data model / entity relationship diagram, and role-based permission matrix.*

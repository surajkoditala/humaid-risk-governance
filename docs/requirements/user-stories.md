# Risk Assessment Workbench — User Stories & Acceptance Criteria

**Prepared for:** Financial Crimes Risk Management (FCRM)
**Document type:** User Stories & Acceptance Criteria (Agile/BRD input)
**Actors:** Product Owner (requestor), FCRM Analyst, Risk Committee Member, System (AI), Platform Engineer (mock systems), DevOps Engineer (deployment, infrastructure, pipelines, and operations)

---

## How to read this document

- Stories are grouped into epics. Epics 1–10 map to the functional requirements in the problem statement. Epics 11–13 (Access Control, Deployment and Operations, Non-Functional Requirements) and US-9.3 (examiner-ready audit export) were raised by QA on 17 Sep 2026 after reviewing the built increment, and are cross-cutting rather than feature epics. Epic 14 (mock external systems and data ingestion) was added from the Platform Ecosystem Diagram (`docs/architecture/ecosystem-diagram.md`) and is deterministic integration, not an AI touchpoint.
- Epics 15–18 (Terraform modules, dev environment infrastructure, CI/CD pipelines, and observability) were added from the infrastructure-as-code and pipeline work in `iac/` and `.azure-pipelines/`. They are engineering-delivery epics written for the DevOps Engineer, and none of them changes what the product does for its users. US-17.4 and US-17.8 are tagged **[AI]** because AI reviews pull requests in the delivery pipeline (not in the product); a human still decides whether a pull request merges. Epic 18 is a placeholder: its scope is still to be refined.
- Numbering note: Epic 14 follows Epic 13 because 11–13 were already taken in Azure Boards when the mock-systems epic was written up. The IDs here match the Boards work items one-to-one, and Epics 15–18 continue the same numbering.
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

### US-9.3 — Export an examiner-ready audit trail
*As an Auditor or FCRM Analyst preparing for examination, I want to export a request's complete history in a durable format, so that I can hand it to an examiner without reformatting it first.*

**Acceptance Criteria**
- Given any request ID, when I export its history, then the export contains every event in order: submission, uploads, AI outputs, human overrides with reasons, policy citations relied upon, score calculations, routing, individual votes, and the final decision.
- Given an export, when I open it, then each entry shows actor, exact timestamp, and the before and after state.
- Given an export, when it is produced, then it is a durable, human-readable document requiring no further formatting.
- Given an assessment with AI-generated content, when it is exported, then both the original AI output and any human override appear, never the override alone.

> Origin: raised by QA on 17 Sep 2026 — the third criterion of US-9.1 states the export requirement, but no story owned the export itself. US-9.1 covers reconstructing the history; this story covers producing it as a document.

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

## Epic 11 — Access Control

**Goal:** Make the three-role model real at the API, not just in the UI.

> Origin: raised by QA on 17 Sep 2026 from DEF-001 and DEF-002. The user directory is currently readable with no credential at all, and the UI hides screens by role while the API enforces nothing. The role model exists and is honoured only in the frontend, which is worse than having none, because the product looks access-controlled.

### US-11.1 — Enforce role-based permissions on every action
*As FCRM Leadership, I want every action to be permitted only to the role that owns it, so that the accountability the audit trail records is real rather than assumed.*

**Acceptance Criteria**
- Given any request to a protected endpoint, when no valid credential is presented, then the request is rejected and no data of any kind is returned.
- Given an authenticated user, when they attempt an action their role does not permit, then it is refused on authorization grounds before any record is read or written.
- Given any write action, when the acting user is determined, then it comes from the authenticated session and never from a field in the request payload.
- Given the permission model, when it is reviewed, then a documented matrix maps each of the three roles (Product Owner, FCRM Analyst, Risk Committee Member) to every action, and each endpoint behaviour matches it.

---

## Epic 12 — Deployment & Operations

**Goal:** Get the product into a running Azure environment and keep it observable. Deployment and Operations are two of the six graded SDLC stages.

> Origin: raised by QA on 17 Sep 2026 after reviewing the 12–17 Sep deployment increment. Covers schema deployment (DEF-007, a first-deploy blocker), container build and scanning (DEF-009, DEF-011), and observability (DEF-010).

### US-12.1 — Apply the database schema to a deployed environment
*As the DevOps Engineer, I want the schema, stored functions, and reference data applied automatically to a target environment, so that a deployed application can actually serve a request.*

**Acceptance Criteria**
- Given a newly provisioned database, when the release runs, then schema, all `func_` routines, and reference seed data are applied before the application containers start accepting traffic.
- Given the schema deployment runs twice, when it completes, then the second run is a safe no-op and destroys no data.
- Given schema deployment fails, when it does, then the release halts and reports which statement failed, and never proceeds to start an application against an incomplete schema.
- Given a deployed environment, when I verify it, then a documented post-deploy check confirms the expected function and seed-row counts.

> Origin: DEF-007 — **first-deploy blocker.** The DB folder is not copied into either container image, `Program.cs` performs no bootstrap, and no pipeline applies it. On first deploy the containers would start cleanly and fail on every request.

### US-12.2 — Build and publish container images automatically
*As the DevOps Engineer, I want images built, scanned, and published by the pipeline, so that what reaches Azure is reproducible and has been checked.*

**Acceptance Criteria**
- Given a merge to the main branch, when the pipeline runs, then both service images build from the repository root and are pushed to the registry tagged with the commit.
- Given an image is built, when it is scanned, then no HIGH or CRITICAL operating-system vulnerability is present, and the build fails if one is.
- Given a running container, when its user is inspected, then it is not root.
- Given any image, when its layers are inspected, then no local configuration file or secret is present.

> Origin: DEF-009 and DEF-011.

### US-12.3 — Observe a running environment
*As the DevOps Engineer, I want logs, traces, and metrics from a deployed environment, so that a failure can be diagnosed without redeploying to reproduce it.*

**Acceptance Criteria**
- Given a deployed environment, when a request is served, then its trace is queryable within minutes, including outbound calls to the database, Mock Systems, and the AI provider.
- Given an unhandled error, when it occurs, then it is recorded with enough context to identify the request, without recording assessment content or personal data.
- Given cost constraints, when telemetry is configured, then a sampling rate is set deliberately and documented.

> Origin: DEF-010 — both services register OpenTelemetry and activate on a connection string, but the Log Analytics workspace is commented out in Terraform.

---

## Epic 13 — Non-Functional Requirements

**Goal:** Define the non-functional requirements this document previously named as its own next step and left undefined: data retention, data residency, access control, observability, performance, and availability. Access control is covered by Epic 11 and observability by US-12.3; the stories below cover retention and data residency.

> Origin: raised by QA on 17 Sep 2026. With Azure infrastructure now provisioned, several of these became decidable rather than abstract. Performance and availability targets are still undefined and have no story yet.

### US-13.1 — Retain assessment records for the supervisory period
*As FCRM Leadership, I want assessment records and their audit trail retained for the full supervisory retention period, so that an examiner can review a decision years after it was taken.*

**Acceptance Criteria**
- Given a finalized assessment, when the retention period is defined, then it is at least five years and is stated in documentation rather than assumed.
- Given the database, when backup is configured, then point-in-time restore is enabled and the retention window is documented.
- Given an attached document, when the request is decisioned, then the document remains retrievable for the same period as its assessment.

> Origin: currently undefined — no backup or retention policy exists on the database.

### US-13.2 — Keep model calls inside the tenant
*As FCRM Leadership, I want AI calls to stay within our own Azure tenant, so that assessment content never leaves our control boundary.*

**Acceptance Criteria**
- Given a deployed environment, when an AI call is made, then it goes to the in-tenant Azure AI Foundry deployment and not a third-party endpoint.
- Given configuration, when the environment starts, then a non-production provider cannot be selected by default in a deployed environment.
- Given any AI call, when it is logged, then the prompt and response content are not written to general application logs.

> Origin: with Azure AI Foundry now provisioned this became decidable; the provider is currently selected by a configuration value with a non-Azure default.

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

## Epic 15 — Terraform Modules for Azure Infrastructure

**Goal:** Build reusable, versioned Terraform modules for the Azure resources the Workbench and Mock API platform will run on, so that every environment can be provisioned from the same reviewed building blocks instead of hand-built or copy-pasted resources.

This epic delivers ten modules, each in its own folder under `iac/modules`: Resource Group, Virtual Network, Private DNS Zone, Key Vault, Storage Account, PostgreSQL Flexible Server, Log Analytics Workspace, Container Registry, Container Apps Environment, and Container Apps. Each module must be self-contained and documented (README, Intro, CHANGELOG), take its configuration through variables, and expose the outputs that other modules and environments need.

### US-15.1 — Create a terraform module for Azure Resource Group
*As a DevOps Engineer, I want to create a reusable Terraform module for the Azure Resource Group, so that every environment can get a consistently named, tagged, and optionally lock-protected resource group from one reviewed definition.*

**Acceptance Criteria**
- Given the required tags (`business_unit`, `customer`, `environment`, `product`, `owner`, `region`), when the module is applied, then a resource group named `rg-<product>-<environment>` is created in the requested location (default eastus2) and tagged with those tags plus `managed-by = terraform`.
- Given a required tag is missing, when `terraform plan` runs, then validation fails with a message naming the missing tag, before any resource is created.
- Given a name is supplied, when the module is applied, then it overrides the default naming convention.
- Given the lock is enabled, when the module is applied, then a management lock at the configured lock level is placed on the resource group; given it is disabled, then no lock is created.
- Given the module is consumed by an environment, when it is applied, then the resource group ID, name, and location are available as outputs for other modules to reference.
- Given the module is delivered, when I review `iac/modules/terraform-azure-resourcegroup`, then it contains a README, an Intro, and a CHANGELOG recording the v1.0.0 release, and pins the supported Terraform and azurerm provider versions.

### US-15.2 — Create a terraform module for Azure Virtual Network
*As a DevOps Engineer, I want to create a reusable Terraform module for the Azure Virtual Network, its subnets, network security groups, and route tables, so that every environment can get its network layout from one reviewed definition, with subnet isolation and traffic rules declared as configuration instead of hand-built in the portal.*

**Acceptance Criteria**
- Given an address space and a list of subnets, when the module is applied, then a virtual network named `vnet-<product>-<environment>` (or the supplied name) is created with every listed subnet, each with its address prefixes and optional service endpoints and service delegation.
- Given network security group definitions with security rules and a subnet-to-NSG map, when the module is applied, then each NSG is created with its rules and associated with the mapped subnet.
- Given route table definitions and a subnet-to-route-table map, when the module is applied, then each route table is created with its optional routes and associated with the mapped subnet; given none are supplied, then none are created.
- Given custom DNS servers, a DDoS protection plan, or VNet peerings are supplied, when the module is applied, then they are configured on the virtual network; given they are omitted, then none are configured.
- Given the module is consumed by an environment, when it is applied, then the VNet ID and name, the subnet IDs, the NSG IDs, and the route table IDs are available as outputs for other modules to reference.
- Given the module is delivered, when I review `iac/modules/terraform-azure-virtualnetwork`, then it contains a README, an Intro, and a CHANGELOG recording the v1.0.0 release, and pins the supported Terraform and azurerm provider versions.

### US-15.3 — Create a terraform module for Azure Private DNS Zone
*As a DevOps Engineer, I want to create a reusable Terraform module for the Azure Private DNS Zone with virtual network links, so that private endpoints resolve to private IP addresses inside the linked networks, and one definition can serve every service zone such as `privatelink.vaultcore.azure.net`.*

**Acceptance Criteria**
- Given a domain name (for example `privatelink.postgres.database.azure.com`), when the module is applied, then a private DNS zone with that name is created in the resource group and tagged.
- Given one or more virtual networks to link, when the module is applied, then each is linked to the zone so resources in those networks can resolve its records.
- Given a lock is requested, when the module is applied, then a management lock of kind CanNotDelete or ReadOnly is placed on the zone; given any other kind, then validation fails with a message stating the allowed kinds.
- Given role assignments are supplied, when the module is applied, then they are created on the zone; given none are supplied, then none are created.
- Given the module is consumed by an environment, when it is applied, then the private DNS zone resource ID is available as an output, so private endpoints in other modules can reference it.
- Given the module is delivered, when I review `iac/modules/terraform-azure-privatednszone`, then it contains a README, an Intro, and a CHANGELOG recording the v1.0.0 release, and pins the supported Terraform and azurerm provider versions.

### US-15.4 — Create a terraform module for Azure Key Vault
*As a DevOps Engineer, I want to create a reusable Terraform module for the Azure Key Vault with private endpoint, network rules, and monitoring options, so that applications can keep secrets and certificates in a vault that is reachable only over approved networks, with the same hardened defaults in every environment.*

**Acceptance Criteria**
- Given a tenant ID, location, resource group, and tags, when the module is applied, then a key vault is created with configurable SKU, soft-delete retention, purge protection, and public network access.
- Given network ACLs with a default action, a bypass setting, IP rules, and virtual network subnet IDs, when the module is applied, then the vault only accepts traffic from those sources.
- Given a private endpoint definition with a subnet and private DNS zone IDs, when the module is applied, then a private endpoint is created for the vault and registered in the DNS zone; the DNS zone group can be managed by the module or left to the environment.
- Given diagnostic settings, when the module is applied, then logs and metrics are routed to the chosen Log Analytics workspace, storage account, or event hub; given no destination is set, then validation fails with a message naming the accepted destinations.
- Given monitoring is enabled, when the module is applied, then the configured metric alerts and a vault-deletion activity log alert are created and notify the supplied action group.
- Given a lock or role assignments are supplied, when the module is applied, then they are created on the vault; given none are supplied, then none are created.
- Given the module is consumed by an environment, when it is applied, then the vault name, resource ID, URI, private FQDN, and private endpoint details are available as outputs for other modules to reference.
- Given the module is delivered, when I review `iac/modules/terraform-azure-keyvault`, then it contains a README, an Intro, and a CHANGELOG recording the v1.0.0 release, and pins the supported Terraform and azurerm provider versions.

### US-15.5 — Create a terraform module for Azure Storage Account
*As a DevOps Engineer, I want to create a reusable Terraform module for the Azure Storage Account with private endpoints, network rules, and monitoring options, so that applications can store blobs, files, queues, and tables in an account that is reachable only over approved networks, with the same secure defaults in every environment.*

**Acceptance Criteria**
- Given a location, resource group, and tags, when the module is applied, then a storage account is created with configurable tier, replication type, kind, access tier, minimum TLS version, HTTPS-only traffic, shared key access, and public network access.
- Given blob properties such as CORS rules, when the module is applied, then they are set on the blob service.
- Given network rules with a default action, a bypass setting, IP rules, and virtual network subnet IDs, when the module is applied, then the account only accepts traffic from those sources.
- Given private endpoint definitions for the blob, file, queue, and table sub-resources, each with its subnet and private DNS zone IDs, when the module is applied, then a private endpoint is created for each sub-resource and registered in its DNS zone.
- Given a customer-managed key, when the account kind is not StorageV2 (or the tier is not Premium) or no user-assigned identity is set, then validation fails with a message explaining the requirement; otherwise the key is applied to the account.
- Given diagnostic settings for the account and the blob service, when the module is applied, then logs and metrics are routed to the chosen destination; given monitoring is enabled, then availability and used-capacity metric alerts are created.
- Given a lock or role assignments are supplied, when the module is applied, then they are created on the account; given none are supplied, then none are created.
- Given the module is consumed by an environment, when it is applied, then the account name, resource ID, the public and private FQDNs of the blob, file, queue, and table endpoints, and the private endpoint details are available as outputs.
- Given the module is delivered, when I review `iac/modules/terraform-azure-storageaccount`, then it contains a README, an Intro, and a CHANGELOG recording the v1.0.0 release, and pins the supported Terraform and azurerm provider versions.

### US-15.6 — Create a terraform module for Azure PostgreSQL Flexible Server
*As a DevOps Engineer, I want to create a reusable Terraform module for the Azure PostgreSQL Flexible Server with databases, Microsoft Entra administrators, firewall rules, and a private endpoint, so that applications can get a managed relational database, with the same security and availability options declared as configuration in every environment.*

**Acceptance Criteria**
- Given a location, resource group, administrator login, and password, when the module is applied, then a PostgreSQL Flexible Server is created with configurable SKU, server version, storage size, storage tier, backup retention, and geo-redundant backup setting; given a storage tier outside the allowed list, then validation fails with a message listing the allowed tiers.
- Given high availability is configured as ZoneRedundant or SameZone, when the module is applied, then a standby is provisioned; given it is null, then the server runs without high availability.
- Given an authentication block that enables password authentication, Microsoft Entra authentication, or both, and a list of Entra administrators (users or service principals), when the module is applied, then each administrator is assigned on the server.
- Given a map of databases, when the module is applied, then each database is created on the server.
- Given firewall rules with start and end IP addresses, when the module is applied, then each rule is created; given none are supplied, then none are created.
- Given a private endpoint definition with a subnet and private DNS zone IDs, when the module is applied, then a private endpoint is created for the server and registered in the DNS zone.
- Given optional settings such as server configuration parameters, a maintenance window, a customer-managed key, managed identities, diagnostic settings, a lock, or role assignments, when they are supplied, then they are applied; given they are omitted, then none are created.
- Given the module is consumed by an environment, when it is applied, then the server name, FQDN, resource ID, database names and IDs, and private endpoint details are available as outputs for other modules to reference.
- Given the module is delivered, when I review `iac/modules/terraform-azure-postgresql`, then it contains a README, an Intro, and a CHANGELOG recording the v1.0.0 release, and pins the supported Terraform and azurerm provider versions.

### US-15.7 — Create a terraform module for Azure Log Analytics Workspace
*As a DevOps Engineer, I want to create a reusable Terraform module for the Azure Log Analytics Workspace with an optional Application Insights instance, so that logs, metrics, and application telemetry can be collected in one workspace, configured the same way in every environment.*

**Acceptance Criteria**
- Given a location, resource group, and tags, when the module is applied, then a Log Analytics workspace is created with configurable SKU, retention period, daily quota, internet ingestion and query access, and local authentication setting.
- Given Application Insights is enabled, when the module is applied, then a workspace-based Application Insights instance is created and linked to the workspace, with configurable application type, sampling percentage, daily data cap, and IP masking; given an application type outside the allowed list, then validation fails with a message listing the allowed values.
- Given managed identities, diagnostic settings, a lock, or role assignments are supplied, when the module is applied, then they are created; given none are supplied, then none are created.
- Given the tags are missing a required key (`business_unit`, `customer`, `environment`, `product`, `owner`, `region`), when `terraform plan` runs, then validation fails with a message naming the missing tag.
- Given the module is consumed by an environment, when it is applied, then the workspace resource ID and the Application Insights resource ID, app ID, name, connection string, and instrumentation key are available as outputs for other modules to reference.
- Given the module is delivered, when I review `iac/modules/terraform-azure-loganalytics-workspace`, then it contains a README, an Intro, and a CHANGELOG recording the v1.0.0 release, and pins the supported Terraform and azurerm provider versions.

### US-15.8 — Create a terraform module for Azure Container Registry
*As a DevOps Engineer, I want to create a reusable Terraform module for the Azure Container Registry with private networking, identity, and access controls, so that container images can be stored in a private registry that applications pull from using managed identities, with the same policies in every environment.*

**Acceptance Criteria**
- Given a location, resource group, and SKU (Basic, Standard, or Premium), when the module is applied, then a container registry is created with configurable admin access, anonymous pull, public network access, export policy, quarantine policy, and trust policy; given a name that is not 5-50 lowercase alphanumeric characters, then validation fails with a message stating the rule.
- Given a Premium-only feature (zone redundancy, a network rule set, or a customer-managed key) is requested on a non-Premium SKU, when `terraform plan` runs, then validation fails with a message stating that Premium is required.
- Given geo-replication locations on a Premium registry, when the module is applied, then the registry is replicated to each region.
- Given a private endpoint definition with a subnet and private DNS zone IDs, when the module is applied, then a private endpoint is created for the registry and registered in the DNS zone.
- Given system-assigned or user-assigned managed identities and role assignments (for example AcrPull), when they are supplied, then they are created on the registry.
- Given diagnostic settings or a lock are supplied, when the module is applied, then they are created; given none are supplied, then none are created.
- Given the module is consumed by an environment, when it is applied, then the registry name, resource ID, login server, system-assigned identity principal ID, and private endpoint details are available as outputs for other modules to reference.
- Given the module is delivered, when I review `iac/modules/terraform-azure-containerregistry`, then it contains a README, an Intro, and a CHANGELOG recording the v1.0.0 release, and pins the supported Terraform and azurerm provider versions.

### US-15.9 — Create a terraform module for Azure Container Apps Environment
*As a DevOps Engineer, I want to create a reusable Terraform module for the Azure Container Apps Environment with workload profiles, virtual network integration, and logging, so that container apps can share one managed hosting environment that is integrated with the virtual network and configured the same way in every environment.*

**Acceptance Criteria**
- Given a location, resource group, and tags, when the module is applied, then a container apps environment is created with the supplied workload profiles (for example Consumption); given none are supplied, then a pure Consumption plan is used.
- Given an infrastructure subnet ID, when the module is applied, then the environment is integrated with that subnet; internal load balancer and zone redundancy are configurable.
- Given virtual networks to link, when the module is applied, then a private DNS zone for the environment default domain, with a wildcard record, is created and linked to each virtual network, so apps in the environment can call each other by internal name.
- Given a Log Analytics workspace ID, when the module is applied, then the environment sends its logs there; given the module is asked to create a workspace, then it creates one; Dapr Application Insights and mutual TLS are optional.
- Given managed identities, a lock, or role assignments are supplied, when the module is applied, then they are created; given none are supplied, then none are created.
- Given the module is consumed by an environment, when it is applied, then the environment ID, name, default domain, static IP address, and Log Analytics workspace ID are available as outputs for other modules to reference.
- Given the module is delivered, when I review `iac/modules/terraform-azure-containerappsenvironment`, then it contains a README, an Intro, and a CHANGELOG recording the v1.0.0 release, and pins the supported Terraform and azurerm provider versions.

### US-15.10 — Create a terraform module for Azure Container Apps
*As a DevOps Engineer, I want to create a reusable Terraform module for the Azure Container App with ingress, identities, registry access, and secrets, so that each application can be deployed into a container apps environment from one reviewed definition, with its scaling, networking, and access declared as configuration.*

**Acceptance Criteria**
- Given a container app environment ID, a service name, and a container template (name, image, CPU, memory, environment variables, minimum and maximum replicas), when the module is applied, then a container app is created in that environment on the chosen workload profile and revision mode.
- Given a service name that does not start with a lowercase letter, contains characters other than lowercase letters, digits, and hyphens, contains consecutive hyphens, or is longer than 32 characters, when `terraform plan` runs, then validation fails with a message stating the rule.
- Given an ingress definition, when the module is applied, then the app is exposed with the requested target port, external or internal visibility, HTTPS enforcement, and traffic weights.
- Given system-assigned and user-assigned managed identities and a registry definition that uses an identity, when the module is applied, then the app pulls its image from the private registry without a password.
- Given secrets supplied inline or as Key Vault references, when the module is applied, then they are available to the container as secrets.
- Given role assignments for the app's system-assigned identity (for example on a Key Vault or Storage Account), when they are supplied, then they are created; given none are supplied, then none are created.
- Given optional probes, scale rules, volumes, init containers, or a lock, when they are supplied, then they are applied.
- Given the module is consumed by an environment, when it is applied, then the container app ID, name, FQDN, registry, and system-assigned identity principal ID are available as outputs for other modules to reference.
- Given the module is delivered, when I review `iac/modules/terraform-azure-containerapps`, then it contains a README, an Intro, and a CHANGELOG recording the v1.0.0 release, and pins the supported Terraform and azurerm provider versions.

---

## Epic 16 — Dev Environment Infrastructure Set Up

**Goal:** To support the Workbench and the Mock API in Azure, provision the platform for the dev environment with Terraform, using the reusable modules delivered in Epic 15: a private network, private DNS, a key vault and file storage, a PostgreSQL database, monitoring, a container registry, and the container apps that host the Workbench UI and the Mock API.

The dev environment is one Terraform configuration (`iac/environments/dev`) with remote state, standard resource tagging, and private endpoints for the data and secret services, so it can be created and changed from code by the deployment pipeline. Stories are ordered by dependency: state and resource group, network, private DNS, secret and data services, then the container platform.

Done when the infrastructure platform for the dev environment is available and the Workbench and Mock API container apps can start on it.

### US-16.1 — Dev - Configure the Terraform remote state and providers
*As a DevOps Engineer, I want the dev Terraform configuration set up with remote state and pinned tool versions, so that every engineer and the pipeline plan and apply against the same shared state, and runs are repeatable.*

**Acceptance Criteria**
- Given the state resource group, storage account, and `tfstate` container are created ahead of the first run (one-off bootstrap), when `terraform init` runs in `iac/environments/dev`, then state is stored in the azurerm backend under the key `dev/terraform.tfstate` and not on the local machine.
- Given two runs start at the same time, when both try to change state, then the second waits or fails on the state lock instead of overwriting the first.
- Given a Terraform CLI outside ~> 1.8 or an azurerm provider outside >= 4.0 and < 5.0, when `terraform init` runs, then it fails with a version constraint message.
- Given the common variables, when the environment is planned, then every resource carries the standard tags (`business_unit`, `customer`, `environment`, `product`, `owner`, `region`), and the default region is eastus2 with centralus available for services that must be placed there.
- Given the environment is applied, when I review the outputs, then the resource group ID, name, and location are exposed.

### US-16.2 — Dev - Set up the resource group
*As a DevOps Engineer, I want the dev resource group created from the Resource Group module, so that all dev resources live in one tagged container that can be governed and cleaned up as a unit.*

**Acceptance Criteria**
- Given the standard tags, when the environment is applied, then a resource group named `rg-<product>-<environment>` is created in eastus2 with those tags plus `managed-by = terraform`.
- Given the dev environment, when the resource group is created, then the management lock is disabled so the group can be torn down and rebuilt; the lock setting is documented as the switch to enable for higher environments.
- Given other dev resources are defined, when they are applied, then each is created in this resource group by referencing its name from the module output.
- Given the change is merged, when the dev Terraform deployment runs, then the resources are created without errors and a follow-up plan reports no changes.

### US-16.3 — Dev - Set up the virtual network, subnets, and network security groups
*As a DevOps Engineer, I want the dev virtual network with its subnets and network security groups created from the Virtual Network module, so that the private endpoints and the container apps environment have an isolated network to run in, and access rules are declared as code.*

**Acceptance Criteria**
- Given the dev network parameters, when the environment is applied, then a virtual network named `vnet-<product>-<environment>` is created in eastus2 with the address space `10.12.0.0/16`.
- Given the subnet parameters, when the environment is applied, then a private endpoint subnet (`snet-pep-dev-01`, `10.12.50.0/24`) is created with service endpoints for Key Vault, Storage, SQL, and Web.
- Given the subnet parameters, when the environment is applied, then a container apps subnet (`snet-cae-dev-01`, `10.12.240.0/20`) is created with service endpoints for Key Vault, Storage, and SQL, delegated to Microsoft.App/environments.
- Given the NSG parameters, when the environment is applied, then one NSG per subnet (`nsg-pep-dev-01` and `nsg-cae-dev-01`) is created with inbound and outbound rules that allow Azure DNS (`168.63.129.16`), and each is associated with its subnet.
- Given no route tables are defined for dev, when the environment is applied, then none are created.
- Given other resources need the network, when the environment is applied, then the VNet ID and name and the subnet IDs are available for private endpoints, network rules, DNS links, and the container apps environment to reference.
- Given the change is merged, when the dev Terraform deployment runs, then the resources are created without errors and a follow-up plan reports no changes.

### US-16.4 — Dev - Provision the private DNS zones
*As a DevOps Engineer, I want the private DNS zones for the dev private endpoints created from the Private DNS Zone module, so that Key Vault, Storage, and PostgreSQL names resolve to private IP addresses from inside the virtual network.*

**Acceptance Criteria**
- Given the dev environment, when it is applied, then private DNS zones are created for PostgreSQL (`privatelink.postgres.database.azure.com`), Blob (`privatelink.blob.core.windows.net`), File (`privatelink.file.core.windows.net`), Table (`privatelink.table.core.windows.net`), Queue (`privatelink.queue.core.windows.net`), and Key Vault (`privatelink.vaultcore.azure.net`).
- Given each zone, when it is applied, then it is linked to the dev virtual network.
- Given the private endpoints for Key Vault, Storage, and PostgreSQL, when they are created, then each registers in its matching zone by referencing the zone's resource ID.
- Given the change is merged, when the dev Terraform deployment runs, then the resources are created without errors and a follow-up plan reports no changes.

### US-16.5 — Dev - Set up the key vault
*As a DevOps Engineer, I want the dev key vault created from the Key Vault module with a private endpoint and network rules, so that the container apps can read secrets and certificates from a vault that is reachable only from approved networks.*

**Acceptance Criteria**
- Given the dev environment, when it is applied, then a key vault is created in the resource group, using the tenant of the deploying identity and the standard tags.
- Given the network rules, when the environment is applied, then the default action is Deny with Azure services allowed to bypass, and only the approved VPN IP addresses, the private endpoint subnet, and the container apps subnet can reach the vault.
- Given the private endpoint parameters, when the environment is applied, then a private endpoint is created in the private endpoint subnet and registered in the Key Vault private DNS zone, so the vault name resolves to a private IP inside the virtual network.
- Given the container apps need the vault, when the environment is applied, then the vault resource ID and URI are available for role assignments and for the apps' configuration.
- Given the change is merged, when the dev Terraform deployment runs, then the resources are created without errors and a follow-up plan reports no changes.

### US-16.6 — Dev - Set up the storage account
*As a DevOps Engineer, I want the dev storage account created from the Storage Account module with private endpoints and network rules, so that the applications can store and read blobs, files, queues, and tables in an account that is reachable only from approved networks.*

**Acceptance Criteria**
- Given the dev environment, when it is applied, then a storage account is created in the resource group with the standard tags.
- Given the network rules, when the environment is applied, then the default action is Deny with Azure services allowed to bypass, and only the approved IP addresses, the private endpoint subnet, and the container apps subnet can reach the account.
- Given the blob CORS parameters, when the environment is applied, then the blob service allows GET and OPTIONS from the configured origins (default `http://localhost:4200`) with the configured preflight cache time.
- Given the private endpoint parameters, when the environment is applied, then private endpoints are created for Blob, File, Queue, and Table in the private endpoint subnet, each registered in its own private DNS zone.
- Given the container apps need the account, when the environment is applied, then the account resource ID and blob service address are available for role assignments and for the apps' configuration; the blob address resolves to the private IP through the private DNS zone while keeping the name that matches the certificate.
- Given the change is merged, when the dev Terraform deployment runs, then the resources are created without errors and a follow-up plan reports no changes.

### US-16.7 — Dev - Set up the PostgreSQL Flexible Server and database
*As a DevOps Engineer, I want the dev PostgreSQL Flexible Server and the risk governance database created from the PostgreSQL module, so that the Workbench and the Mock API have a managed relational database that they can reach without a stored password.*

**Acceptance Criteria**
- Given the dev database parameters, when the environment is applied, then a PostgreSQL Flexible Server is created in centralus with server version 17, SKU `B_Standard_B2ms`, 64 GB storage on the P15 tier, no high availability, and geo-redundant backup off.
- Given the administrator login, when the environment is applied, then its password is generated by Terraform at apply time and is never written to code, tfvars, or the repository.
- Given the database parameters, when the environment is applied, then a database named `risk_governance_db` is created on the server.
- Given the authentication settings, when the environment is applied, then password and Microsoft Entra authentication are both enabled, and the named team members are set as Entra administrators.
- Given the two container apps exist, when the environment is applied, then each app's system-assigned identity is also set as an Entra administrator, so the apps connect with their identity and no password.
- Given the firewall parameters, when the environment is applied, then a firewall rule is created for each approved VPN and engineer IP address, and public network access follows the dev setting.
- Given the private endpoint parameters, when the environment is applied, then a private endpoint is created in the private endpoint subnet, in the virtual network's region (eastus2) even though the server is in centralus, and registered in the PostgreSQL private DNS zone.
- Given the container apps need the server, when the environment is applied, then the server FQDN is available for building each app's connection string.
- Given the change is merged, when the dev Terraform deployment runs, then the resources are created without errors and a follow-up plan reports no changes.

### US-16.8 — Dev - Create the Log Analytics workspace and Application Insights
*As a DevOps Engineer, I want the dev Log Analytics workspace with Application Insights created from the Log Analytics Workspace module, so that logs and application telemetry have a central place to land, ready to be connected when needed.*

**Acceptance Criteria**
- Given the dev environment, when it is applied, then a Log Analytics workspace and a linked workspace-based Application Insights instance are created in the resource group with the standard tags.
- Given other resources need the workspace, when the environment is applied, then the workspace resource ID is available as an output.
- Given the dev cost controls, when the environment is applied, then diagnostic settings that send Key Vault, Storage, and PostgreSQL logs, and the container apps environment logs, to the workspace are left disabled; each can be turned on later by adding its settings.
- Given the change is merged, when the dev Terraform deployment runs, then the resources are created without errors and a follow-up plan reports no changes.

### US-16.9 — Dev - Create the container registry
*As a DevOps Engineer, I want the dev container registry created from the Container Registry module, so that the pipeline has a private place to publish the application images, and the container apps have one to pull them from.*

**Acceptance Criteria**
- Given the dev environment, when it is applied, then a Standard SKU container registry is created in the resource group with admin access disabled and zone redundancy off.
- Given the dev setting for public network access, when the environment is applied, then the registry follows that setting; geo-replication is not configured in dev and remains a documented option for production.
- Given the container apps need the registry, when the environment is applied, then the registry resource ID and login server are available for role assignments and for the apps' image references.
- Given the first deployment, when the container apps are created, then a placeholder image is present in the registry so the apps can start; the real application images are published later by the pipeline.
- Given the change is merged, when the dev Terraform deployment runs, then the resources are created without errors and a follow-up plan reports no changes.

### US-16.10 — Dev - Set up the managed identity for pulling container images
*As a DevOps Engineer, I want a user-assigned managed identity for the container apps, with permission to pull images from the registry, so that the container apps can pull images without a registry password, and the permission is created before the apps start.*

**Acceptance Criteria**
- Given the dev environment, when it is applied, then a user-assigned managed identity named `id-ca-<product>-<environment>` is created in the resource group.
- Given the identity and the registry exist, when the environment is applied, then the identity is granted the AcrPull role scoped to the registry only.
- Given a container app is created, when it is configured, then it uses this identity to authenticate to the registry.
- Given the change is merged, when the dev Terraform deployment runs, then the resources are created without errors and a follow-up plan reports no changes.

### US-16.11 — Dev - Set up the container apps environment
*As a DevOps Engineer, I want the dev container apps environment created from the Container Apps Environment module and integrated with the virtual network, so that the Workbench and the Mock API share one managed hosting environment, where internal app-to-app calls stay inside the virtual network.*

**Acceptance Criteria**
- Given the dev environment, when it is applied, then a container apps environment is created in the resource group with a Consumption workload profile only, and no dedicated compute.
- Given the container apps subnet, when the environment is applied, then the container apps environment is integrated with it while keeping a public IP, so an app with external ingress stays reachable.
- Given the virtual network, when the environment is applied, then the environment's private DNS zone is linked to it, so an app with internal-only ingress resolves and is reachable by other apps in the environment and not from the internet.
- Given the environment, when it is applied, then a system-assigned managed identity is enabled.
- Given the dev cost controls, when the environment is applied, then it is not attached to the Log Analytics workspace; the workspace reference is left as an option to enable later.
- Given the container apps are defined, when they are applied, then each references the environment ID from the module output.
- Given the change is merged, when the dev Terraform deployment runs, then the resources are created without errors and a follow-up plan reports no changes.

### US-16.12 — Dev - Set up the Workbench container app
*As a DevOps Engineer, I want the Workbench UI container app (`gh-hrg-workbench`) created from the Container Apps module, so that the Workbench runs in the dev environment, reachable by users, with secure access to the key vault, storage, and database.*

**Acceptance Criteria**
- Given the dev environment, when it is applied, then a container app named `gh-hrg-workbench` is created in the container apps environment on the Consumption profile, with 1 CPU, 2 Gi memory, and one replica minimum and maximum.
- Given the ingress parameters, when the environment is applied, then the app is exposed externally on target port 8080 with insecure connections disallowed, all traffic on the latest revision, and CORS open in dev (all origins, methods, and headers).
- Given the first deployment, when the app is created, then it starts from a placeholder image in the registry; the real image is deployed later by the pipeline.
- Given the app's configuration, when it is applied, then the environment variables `PEP_KEY_VAULT` (key vault URI), `ENV`, `BLOB_STORAGE_SERVICE_URI`, and `AZURE_POSTGRESQL_ENDPOINT` (server FQDN, database, and the app's Entra identity, with no password) are set.
- Given the identities, when the app is created, then it has a system-assigned identity and the user-assigned image pull identity, and pulls its image from the registry with that identity.
- Given the system-assigned identity, when the environment is applied, then it is granted Key Vault Secrets User and Key Vault Certificate User on the key vault, and Storage Blob Data Contributor and Storage Queue Data Contributor on the storage account.
- Given the change is merged, when the dev Terraform deployment runs, then the resources are created without errors and a follow-up plan reports no changes.

### US-16.13 — Dev - Set up the Mock API container app
*As a DevOps Engineer, I want the Mock API container app (`gh-hrg-mockapi`) created from the Container Apps module, so that the mock CRM, Core Banking, and Vendor Management systems run in the dev environment, reachable only from the Workbench inside the environment.*

**Acceptance Criteria**
- Given the dev environment, when it is applied, then a container app named `gh-hrg-mockapi` is created in the container apps environment on the Consumption profile, with 1 CPU, 2 Gi memory, and one replica minimum and maximum.
- Given the ingress parameters, when the environment is applied, then the app accepts traffic on target port 8080 from inside the container apps environment only, with external access disabled, insecure connections disallowed, and all traffic on the latest revision.
- Given the first deployment, when the app is created, then it starts from a placeholder image in the registry; the real image is deployed later by the pipeline.
- Given the app's configuration, when it is applied, then the environment variables `PEP_KEY_VAULT`, `ENV`, `BLOB_STORAGE_SERVICE_URI`, and `AZURE_POSTGRESQL_ENDPOINT` (server FQDN, database, and this app's own Entra identity, with no password) are set.
- Given the identities, when the app is created, then it has a system-assigned identity and the user-assigned image pull identity, and pulls its image from the registry with that identity.
- Given the system-assigned identity, when the environment is applied, then it is granted Key Vault Secrets User and Key Vault Certificate User on the key vault, and Storage Blob Data Contributor and Storage Queue Data Contributor on the storage account.
- Given the Workbench app is in the same environment, when it calls the Mock API by its internal name, then the call succeeds; given a request from the internet, then it is refused.
- Given the change is merged, when the dev Terraform deployment runs, then the resources are created without errors and a follow-up plan reports no changes.

---

## Epic 17 — Set Up DevOps CI/CD Pipelines

**Goal:** Set up the automated check, build, and deploy pipelines in Azure DevOps for the code in the GitHub repository, so every change is validated before it merges and approved changes reach the dev environment the same way every time: infrastructure changes under `iac/environments/dev`, Workbench changes, and Mock API changes.

Infrastructure pull requests get formatting, validation, lint, and security checks, a Terraform plan, and an AI review, and a merge to main applies to dev automatically.

Application pull requests get build, test, dependency, and static-analysis checks and an AI code review, and merged code is built into a container image, published to the registry, and deployed to its container app.

A failed gate blocks the merge, and the right person is notified when a review needs attention or a deployment fails.

All pipelines reach Azure through federated, keyless authentication, so no long-lived Azure secret is stored. Depends on the dev environment delivered in Epic 16.

### US-17.1 — Set up the Azure DevOps prerequisites for the pipelines
*As a DevOps Engineer, I want the Azure DevOps connections, identities, and secret variable groups that every pipeline relies on set up once, so that each pipeline can read the GitHub repository, report its result back to the pull request, and reach Azure without a stored secret.*

**Acceptance Criteria**
- Given the GitHub repository, when the pipelines are registered, then Azure DevOps reads the code through a GitHub service connection and reports each pipeline result back to the pull request as a status check.
- Given an Azure Resource Manager service connection named `azure-cloud` that uses Workload Identity Federation, when a pipeline authenticates, then it receives a short-lived token and no client secret or storage account key is stored anywhere.
- Given the identity behind `azure-cloud`, when a pipeline runs Terraform against dev, then the identity can deploy the dev resources and holds Storage Blob Data Contributor on the Terraform state storage account, because state is read and written with Microsoft Entra rather than account keys.
- Given the variable groups `ai-review-secrets` (`CLAUDE_CODE_OAUTH_TOKEN` and `GITHUB_PAT`) and `checkov-secrets`, when a pipeline uses them, then the values are stored as secrets, are masked in logs, and the pipelines are authorized to use the groups, so a first run does not wait for a manual permit.
- Given a secret is rotated, when the variable group is updated, then no pipeline file needs to change.
- Given any pipeline, when it runs, then it runs on the Microsoft-hosted `ubuntu-latest` pool.

### US-17.2 — Set up the infrastructure PR pipeline: formatting, validation, linting, and security scans
*As a DevOps Engineer, I want a pull request pipeline that checks the dev Terraform code for formatting, validity, lint errors, and security findings before it can merge, so that broken or insecure infrastructure code is rejected in seconds, before anyone reviews it or a plan is run.*

**Acceptance Criteria**
- Given a pull request to main that changes files under `iac/environments/dev`, when it is opened or updated, then the pipeline runs; given a pull request that does not touch that path, or targets another branch, or a push to any branch, then it does not run.
- Given the checks are ordered cheapest first, when one hard gate fails, then the build fails and the later steps are skipped, so the required check turns red and the pipeline log shows the error.
- Given unformatted Terraform files, when `terraform fmt -check` runs, then the build fails.
- Given the configuration, when `terraform init` runs without the remote backend (so it needs no cloud credentials) and `terraform validate` runs, then invalid configuration fails the build.
- Given TFLint runs across the configuration, when it reports an issue of error severity, then the build fails; given warnings or notices, then they appear in the log and do not fail the build.
- Given a Trivy configuration scan, when it finds a HIGH or CRITICAL issue, then the build fails; given MEDIUM issues, then they are reported as a warning and do not fail the build. Findings are also written to a JSON file for the AI review.
- Given a Checkov scan configured with a written justification for every skipped check, when it finds issues, then they are reported and do not fail the build (soft-fail); results are written to a JSON file for the AI review.
- Given the tools are installed, when the pipeline runs, then the Terraform, TFLint, Trivy, and Checkov versions are pinned, and the TFLint download is checksum-verified.
- Given the build fails or succeeds, when it ends, then the scan results are published as build artifacts.

### US-17.3 — Set up the infrastructure PR pipeline: Terraform plan without stored credentials
*As a DevOps Engineer, I want the pull request pipeline to produce a Terraform plan against the real dev state, authenticated through the `azure-cloud` service connection, so that reviewers can see exactly what a change would create, modify, or destroy before it merges, and a change that cannot be planned cannot merge.*

**Acceptance Criteria**
- Given a pull request that passed the static checks, when the plan step runs, then it authenticates through the `azure-cloud` service connection with a federated token and uses Microsoft Entra to read the remote state.
- Given the plan step, when it starts, then it re-initializes Terraform with the real remote backend, since the earlier steps ran without it.
- Given `terraform init` or `terraform plan` fails, when the step ends, then the build fails with an error message naming the failed command and its exit code.
- Given the plan succeeds, when the step ends, then the plan is saved as readable text and as JSON and published as build artifacts.
- Given the pull request pipeline runs, when it ends, then no infrastructure has been created, changed, or destroyed; the plan is never applied here.

### US-17.4 — Set up the AI review for infrastructure PRs with a PR comment and a verdict gate **[AI]**
*As a DevOps Engineer, I want an AI review of the scan findings and the Terraform plan that posts a verdict on the pull request and blocks the merge on blocking issues, so that reviewers get a short, prioritized summary of what actually needs attention, and the author is told when it does.*

**Acceptance Criteria**
- Given the scan results and the plan, when the AI review runs, then it produces a short review whose first line is exactly `VERDICT: LOOKS_GOOD`, `VERDICT: NEEDS_ATTENTION`, or `VERDICT: BLOCKING_ISSUES`, followed by a summary of what the plan adds, changes, and destroys.
- Given scanners check the whole configuration and not just the pull request, when the verdict is decided, then only findings on resources the plan creates or modifies can drive it; findings on untouched resources are reported as a single count with a pointer to the artifacts, and are not itemized.
- Given the reviewer is told about the deliberate dev trade-offs (cost-conscious SKUs, disabled diagnostics, PostgreSQL in a different region), when it reviews, then it does not flag them as risks by themselves.
- Given no plan could be produced, an unexpected destroy or replacement of a stateful resource, a HIGH or CRITICAL finding on a resource the plan touches, or anything that would break the deployment or expose data, when the verdict is decided, then it is BLOCKING_ISSUES.
- Given the verdict is BLOCKING_ISSUES, when the pipeline reaches its last step, then the build fails, and only after the pull request comment and the artifacts have been published.
- Given the verdict line is missing or cannot be parsed, when the pipeline reads it, then it is treated as NEEDS_ATTENTION and never as LOOKS_GOOD; given the AI service is unavailable, then the review is skipped and never blocks the pull request.
- Given a pull request build, when the review is ready, then it is posted as a comment on the GitHub pull request; given the verdict is NEEDS_ATTENTION or BLOCKING_ISSUES, then the comment @mentions the pull request author, and if the author cannot be looked up, then the comment is still posted without the mention.

### US-17.5 — Set up the infrastructure deploy pipeline: apply to dev on merge
*As a DevOps Engineer, I want a deploy pipeline that plans and applies the dev Terraform configuration when a change merges to main, so that approved infrastructure changes reach dev automatically and the same way every time, with a record of what was applied.*

**Acceptance Criteria**
- Given a push to main that changes files under `iac/environments/dev`, when the push lands, then the pipeline runs; given a merge that changes only application code, or a pull request, then it does not run.
- Given the pipeline runs, when it deploys, then it authenticates through the `azure-cloud` service connection with a federated token, initializes the remote backend, saves a plan, and applies that saved plan, with no manual approval step because the pull request pipeline is a required check on main.
- Given the pull request pipeline and this pipeline, when they install Terraform, then both use the same pinned version.
- Given the run ends, when it succeeds or fails, then the plan and the apply output are published as build artifacts for the audit trail.
- Given any earlier step fails, when the pipeline ends, then it comments on the merged pull request (or on the commit, for a direct push) and @mentions the author, saying the apply may have partly completed and pointing to the run and the Terraform state.
- Given the notification cannot be posted, when the step ends, then it logs a warning and does not add a second failure to an already failed build.

### US-17.6 — Set up the Workbench PR pipeline: build, tests, dependency audit, and static analysis
*As a DevOps Engineer, I want a pull request pipeline for the Workbench API and web app that builds it, runs its tests, and checks its dependencies, so that a Workbench change that does not build, fails a test, or brings in a vulnerable package cannot merge.*

**Acceptance Criteria**
- Given a pull request to `release/1.00` that changes the Workbench source (`src/1-API`, `src/2-Infrastructure`, `src/3-Service`, `src/4-Persistence`), the tests, the web app, or the Workbench pipeline files, when it is opened or updated, then the pipeline runs; given a change to none of those paths, then it does not run.
- Given the .NET 10 SDK is installed, when the API builds in Release configuration, then a build error fails the build.
- Given the unit test project, when the tests run, then a failing test fails the build, and the results are published to the pipeline's test report even when they fail.
- Given Node.js 22, when the web app installs with `npm ci` and builds, then a build error fails the build.
- Given the dependency audit, when it finds a vulnerable NuGet package (direct or transitive) or an npm package of high severity or above, then the build fails.
- Given Semgrep scans the repository, when it finds issues, then they are written to a JSON file and do not fail the build.
- Given the shared AI code review, when the pipeline reaches it, then it reviews the Workbench paths only, with the Workbench-specific context.
- Given the pipeline ends, when it succeeds or fails, then the test results, Semgrep results, and AI review are published as build artifacts.

### US-17.7 — Set up the Mock API PR pipeline: SQL drift check, build, dependency audit, and static analysis
*As a DevOps Engineer, I want a pull request pipeline for the Mock API that checks its generated database script, builds it, and checks its dependencies, so that a Mock API change cannot merge with a stale deployment script, a build error, or a vulnerable package.*

**Acceptance Criteria**
- Given a pull request to `release/1.00` that changes the Mock API source (`src/6-MockExternalSystems`) or its pipeline files, when it is opened or updated, then the pipeline runs; given a change to other paths only, then it does not run.
- Given `deploy_all.sql` is generated from the schema, functions, and seed data, when the pipeline regenerates it and it differs from the committed copy, then the build fails with a message telling the author to run `generate_deploy_all.sh` and commit the result.
- Given the .NET 10 SDK, when the Mock API builds in Release configuration, then a build error fails the build.
- Given the dependency audit, when it finds a vulnerable NuGet package (direct or transitive), then the build fails.
- Given Semgrep scans the Mock API source, when it finds issues, then they are written to a JSON file and do not fail the build.
- Given the shared AI code review, when the pipeline reaches it, then it reviews the Mock API paths only, with the Mock API-specific context.
- Given the pipeline ends, when it succeeds or fails, then the Semgrep results and the AI review are published as build artifacts.

### US-17.8 — Set up the shared AI code review for application PRs **[AI]**
*As a DevOps Engineer, I want one reusable AI code review, built as a shared pipeline template and scripts, that the Workbench and Mock API pipelines both use, so that every application pull request gets the same safe, focused review, and what the reviewer looks for is changed in one place.*

**Acceptance Criteria**
- Given a pull request build, when the review step runs, then it compares the pull request merge commit with its base branch, limited to the paths the calling pipeline passes in, and asks Claude to review that diff; given a build that is not a pull request, then the review steps are skipped.
- Given the reviewer runs, when it looks at code, then it can only read, search, and list files inside the checkout, so a malicious change cannot make it read secrets, and the step that runs the model never sees the GitHub token because posting the comment is a separate step.
- Given the diff and file contents are untrusted, when they contain instructions such as approving the pull request, then the reviewer ignores them.
- Given the review scope, when findings are produced, then each has a severity (blocker, major, or minor), a file, a line, a short title, and a body, in a fixed JSON format, and only lines the pull request adds or changes are reported; existing problems in untouched code are out of scope.
- Given the findings, when the verdict is derived by the script and not by the model, then any blocker gives BLOCKING_ISSUES, any major gives NEEDS_ATTENTION, and otherwise LOOKS_GOOD.
- Given the verdict, when the comment step runs, then it posts the review as a comment on the pull request and fails the build only on BLOCKING_ISSUES.
- Given the AI service is unavailable or times out (20 minutes at most), when the step ends, then the review is skipped and never blocks the pull request.
- Given a team wants to change what is flagged, when it edits the shared rules file or a component's prompt file, then the next review reflects it with no change to the pipeline steps.

### US-17.9 — Set up the Workbench pipeline: build, publish, and deploy the container image to dev
*As a DevOps Engineer, I want a pipeline that builds the Workbench container image, publishes it to the container registry, and deploys it to the dev container app, so that the Workbench running in dev is always an image built from a known commit by the pipeline, and the placeholder image is replaced.*

**Acceptance Criteria**
- Given a merge to `release/1.00` that changes the Workbench source, when the pipeline runs, then it builds the image from the repository root with the Workbench Dockerfile and pushes it to the dev container registry tagged with the commit ID.
- Given the image is built, when it is scanned, then the build fails on any HIGH or CRITICAL operating system vulnerability, the container does not run as root, and no local configuration file or secret is in the image.
- Given the registry has admin access disabled, when the pipeline pushes, then it authenticates through the `azure-cloud` service connection, whose identity holds push permission on that registry and not on others.
- Given the image is pushed, when the pipeline deploys, then the `gh-hrg-workbench` container app gets a new revision that uses the new image in place of the placeholder image.
- Given the new revision does not start healthy, when the deploy step ends, then it fails and reports the revision status.
- Given the deployment fails, when the pipeline ends, then the merged pull request author is @mentioned with a link to the run, the same way as the infrastructure deploy.
- Given the run ends, when it succeeds or fails, then the image tag, the deployed revision name, and the scan results are published as build artifacts.

### US-17.10 — Set up the Mock API pipeline: build, publish, and deploy the container image to dev
*As a DevOps Engineer, I want a pipeline that builds the Mock API container image, publishes it to the container registry, and deploys it to the dev container app, so that the Mock API running in dev is always an image built from a known commit by the pipeline, and the placeholder image is replaced.*

**Acceptance Criteria**
- Given a merge to `release/1.00` that changes the Mock API source, when the pipeline runs, then it builds the image with the Mock API Dockerfile and pushes it to the dev container registry tagged with the commit ID.
- Given the image is built, when it is scanned, then the build fails on any HIGH or CRITICAL operating system vulnerability, the container does not run as root, and no local configuration file or secret is in the image.
- Given the registry has admin access disabled, when the pipeline pushes, then it authenticates through the `azure-cloud` service connection, whose identity holds push permission on that registry and not on others.
- Given the image is pushed, when the pipeline deploys, then the `gh-hrg-mockapi` container app gets a new revision that uses the new image in place of the placeholder image; the deployment goes through Azure and not through the app's internal-only ingress.
- Given the new revision does not start healthy, when the deploy step ends, then it fails and reports the revision status.
- Given the deployment fails, when the pipeline ends, then the merged pull request author is @mentioned with a link to the run, the same way as the infrastructure deploy.
- Given the run ends, when it succeeds or fails, then the image tag, the deployed revision name, and the scan results are published as build artifacts.

### US-17.11 — Enforce the pipelines as required checks and document them
*As a DevOps Engineer, I want the pull request pipelines made required checks on the protected branches, and the whole pipeline setup documented, so that a red pipeline actually blocks the merge, and a new engineer can understand and change the pipelines without asking.*

**Acceptance Criteria**
- Given branch protection on main, when a pull request changes `iac/environments/dev`, then the infrastructure PR pipeline must pass before it can merge, which is what lets the deploy pipeline apply without a manual approval.
- Given branch protection on `release/1.00`, when a pull request changes the Workbench or the Mock API, then that component's PR pipeline must pass before it can merge; given a failed or unfinished run, then the merge is blocked.
- Given the pipelines only run for certain paths, when a pull request touches only one component or no pipeline path at all, then it is not left waiting for a check that will never run.
- Given the pipeline folder, when a new engineer opens its README, then it lists each pipeline with what triggers it, which gates fail the build and which are informational, the variable groups and service connection it needs, and where to edit what the AI reviewer flags.
- Given a pipeline, gate, or trigger changes, when the change is merged, then the README is updated in the same pull request.

---

## Epic 18 — Observability

**Goal:** Make the running dev environment observable and watched: collect logs, metrics, and application telemetry from the resources in Application Insights and Log Analytics, and add an SRE agent that watches that telemetry and notifies the team of critical issues.

Builds on the dev environment (Epic 16) and the pipelines (Epic 17).

> Placeholder epic: the scope, the conditions that count as critical, and the notification channel are to be refined before work starts.

### US-18.1 — Send logs and metrics from the resources to Application Insights and Log Analytics
*As a DevOps Engineer, I want the logs, metrics, and application telemetry from the dev resources sent to Application Insights and the Log Analytics workspace, so that a failure can be diagnosed from the collected data without redeploying to reproduce it.*

**Acceptance Criteria**
- Given the dev resources (container apps, container apps environment, Key Vault, Storage Account, and PostgreSQL server), when diagnostic settings are enabled, then each sends its logs and metrics to the Log Analytics workspace.
- Given the Workbench and Mock API container apps, when they serve requests, then their application telemetry (requests, dependency calls, and errors) is sent to Application Insights.
- Given the telemetry is flowing, when I query the workspace or Application Insights, then I can find the data from each resource.
- Given cost constraints and the sensitivity of the data, when the log categories, retention, and sampling are chosen, then the choices are documented and no assessment content or personal data is recorded.

### US-18.2 — Set up an SRE agent that watches Application Insights and notifies of critical issues
*As a DevOps Engineer, I want an SRE agent that acts as a watchdog over Application Insights and notifies the team of critical issues, so that the team hears about a serious problem in a running environment without someone having to look for it.*

**Acceptance Criteria**
- Given the telemetry in Application Insights, when the agent runs, then it checks it for the agreed critical conditions (for example a burst of failed requests, unhandled exceptions, or an app that stops responding).
- Given a critical condition is found, when the agent notifies, then the responsible team receives a message through the agreed channel that says what happened, which app and environment, since when, and links to the evidence.
- Given the same issue is still open, when the agent checks again, then it does not send the same notification repeatedly.
- Given the agent's access, when it is set up, then it has read-only access to the telemetry and no permission to change any resource.

> Open question: which conditions count as critical for the SRE agent, and which channel should it notify (for example Teams or email)? Both are left open on purpose until the epic is refined.

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
| Actions permitted only to the role that owns them (three roles) — *raised by QA, 17 Sep 2026* | Epic 11 |
| Production deployment and operations (two of the six SDLC stages the brief requires demonstrated) — *raised by QA, 17 Sep 2026* | Epic 12 |
| Examiner-ready reconstruction of any past rating — *US-9.3 makes the export a story of its own* | Epic 9 (US-9.1, US-9.3) |
| Retention, data residency, and other non-functional requirements — *raised by QA, 17 Sep 2026* | Epic 13 (with Epics 11 and 12) |
| Source intake data from, and return decisions to, the bank's existing systems (mock CRM / Core Banking / Vendor Management) — *from the Platform Ecosystem Diagram, not the original brief; the brief's "synthetic data only, no real system" constraint is what requires them to be mocks* | Epic 14 |
| Reusable, versioned Terraform modules for every Azure resource the platform runs on — *from the `iac/modules` code, not the original brief* | Epic 15 |
| The dev environment provisioned from code with remote state, private networking, and the container apps — *from the `iac/environments/dev` code, not the original brief* | Epic 16 (builds on Epic 15) |
| Automated check, build, and deploy pipelines for infrastructure and both services — *from the `.azure-pipelines/` code, not the original brief* | Epic 17 (deploys to the Epic 16 environment) |
| Logs, metrics, and telemetry collected from the resources, and an SRE agent that watches them and notifies of critical issues — *placeholder* | Epic 18 |

## Open Questions Requiring Stakeholder Input (consolidated)

1. What visibility do Product Owners have into analyst reasoning/scoring (Epic 1)?
2. Which named framework(s) apply, and does this vary by jurisdiction or business line (Epic 2)?
3. Does a scoring override require secondary sign-off before finalization (Epic 7)?
4. Is committee decisioning majority vote, unanimous, or chair-decided (Epic 8)?
5. Who has authority to approve scoring/workflow configuration changes (Epic 10)?
6. Geography changes have no natural system of record — approximate via an affected product (current), or enter directly like Process (Epic 14, US-14.3)?
7. With mock-system data now the primary intake path, should an unreachable mock system still let intake proceed with no external context, or block submission? And should snapshot retrieval be its own Epic 9 audit event (Epic 14, US-14.4)?
8. Should a failed decision push-back be audited and retried or flagged for manual reconciliation, rather than only logged (Epic 14, US-14.5)?
9. Which conditions count as critical for the SRE agent, and which channel should it notify (Epic 18, US-18.2)?

---

*Next suggested steps: performance and availability targets (the remaining Epic 13 gaps), a data model / entity relationship diagram, and the role-based permission matrix that US-11.1 calls for.*

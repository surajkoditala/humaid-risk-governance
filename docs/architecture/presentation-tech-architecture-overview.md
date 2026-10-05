# Architecture & Flow Overview — Risk Assessment Workbench

---

## Tech Stack at a Glance

```mermaid
flowchart LR
    classDef container fill:#dbeafe,stroke:#1d4ed8,color:#1e3a8a,stroke-width:2px
    classDef data fill:#fef3c7,stroke:#b45309,color:#78350f,stroke-width:2px
    classDef external fill:#ede4fc,stroke:#7c3aed,color:#3b0764,stroke-width:2px

    CLIENT["React SPA<br/>built with Vite"]:::container
    API["ASP.NET Core Web API<br/>.NET 10 · Dapper, no ORM"]:::container
    DB[("PostgreSQL")]:::data
    BLOB[("Blob Storage<br/>documents")]:::data
    AUTH0[["Auth0<br/>identity & login"]]:::external
    CLAUDE[["Anthropic<br/>Claude API"]]:::external

    CLIENT -->|HTTPS| API
    API -->|Dapper / TCP| DB
    API -->|upload / read| BLOB
    API -->|validate login| AUTH0
    API -->|AI-assisted steps| CLAUDE
```

- **Frontend:** React SPA, built with Vite
- **Backend:** ASP.NET Core, .NET 10 — Dapper, no ORM
- **Database:** PostgreSQL
- **Documents:** Blob Storage
- **Identity:** Auth0
- **AI:** Anthropic Claude API
- **Deployment:** same image runs as Docker Compose locally and Azure Container Apps in the cloud

---

## 1. System Context

```mermaid
flowchart TB
    classDef person fill:#dcfce7,stroke:#15803d,color:#14532d,stroke-width:2px
    classDef system fill:#dbeafe,stroke:#1d4ed8,color:#1e3a8a,stroke-width:3px
    classDef external fill:#ede4fc,stroke:#7c3aed,color:#3b0764,stroke-width:2px

    PO["Product Owner<br/>raises a change"]:::person
    AN["FCRM Analyst<br/>assesses, configures"]:::person
    RC["Risk Committee<br/>votes on decisions"]:::person
    ADM["Admin<br/>manages users & roles"]:::person
    EXAM["Examiner / Regulator<br/>reads the audit trail"]:::person

    WB["Risk Assessment Workbench<br/>(this system)<br/><br/>Carries a change request from<br/>intake → assessment → committee<br/>decision. Workflow, scoring, and<br/>record-keeping are automated;<br/>nothing is auto-approved."]:::system

    AUTH0[["Auth0<br/>identity provider<br/>(login, JWT issuance)"]]:::external
    CLAUDE[["Anthropic Claude API<br/>category mapping, document<br/>extraction, narrative drafting"]]:::external
    MOCK[["Mock External Systems<br/>stands in for the bank's real<br/>CRM / Core Banking / Vendor Mgmt<br/>(own service, own deploy)"]]:::external

    PO --> WB
    AN --> WB
    RC --> WB
    ADM --> WB
    WB -->|examiner-ready<br/>audit export| EXAM

    WB <-->|login / token validation| AUTH0
    WB -->|AI-assisted drafting only —<br/>never a decision| CLAUDE
    WB <-->|read lookups, snapshot at intake;<br/>decision feedback pushed back| MOCK
```

- **4 user roles:** Product Owner, FCRM Analyst, Risk Committee, Admin
- **Auth0** validates every login — no role is ever trusted from a request itself
- **Anthropic** is used only for AI-assisted drafting — never makes a decision
- **Mock External Systems** stands in for the bank's real CRM / Core Banking / Vendor Mgmt
- **Examiner/Regulator** consumes the audit trail, not the live system

---

## 2. Intake → Audit Workflow

```mermaid
flowchart TB
    classDef ai fill:#ede4fc,stroke:#7c3aed,color:#3b0764,stroke-width:2px
    classDef deterministic fill:#dbeafe,stroke:#1d4ed8,color:#1e3a8a,stroke-width:2px
    classDef human fill:#dcfce7,stroke:#15803d,color:#14532d,stroke-width:2px
    classDef infra fill:#f1f5f9,stroke:#64748b,color:#334155,stroke-width:1px

    subgraph LEGEND["Legend"]
        direction LR
        LG1["AI output"]:::ai
        LG2["Deterministic"]:::deterministic
        LG3["Human decision"]:::human
    end

    PO["Product Owner"] -->|submits form + documents<br/>Epic 1| CR

    subgraph EXT["Mock External Systems service"]
        CRM[(Customers)]
        CBS[(Products)]
        VMS[(Vendors)]
    end

    subgraph INTSRC["Internal to FCRM"]
        POLICYLIB[(Policy & Prior-Assessment Library)]
    end

    subgraph REFDATA["Real reference data — not synthetic"]
        FRAMEWORK[["FFIEC BSA/AML Examination Manual<br/>Products/Services, Customers/Entities,<br/>Geographic Locations, Delivery Channels<br/>(hardcoded, not invented)"]]
    end

    CRM --> INGEST
    CBS --> INGEST
    VMS --> INGEST

    INGEST[Data Ingestion Layer] -->|links + persists an<br/>immutable snapshot| CR[(Change Request<br/>+ external data snapshot)]

    subgraph WORKBENCH["Risk Assessment Workbench"]
        direction TB
        CR --> MAP["AI: Risk Category Mapping<br/>CategoryMappingAiClient<br/>(cites framework section)"]
        FRAMEWORK -. grounds .-> MAP
        CR --> EXTRACT["AI: Document Extraction<br/>DocumentExtractionAiClient<br/>(low-confidence fields flagged)"]
        MAP --> POLICY["Policy Research — DETERMINISTIC<br/>Postgres full-text search<br/>(not an LLM call)"]
        POLICYLIB -.-> POLICY
        MAP --> DRAFT["AI: Draft Narrative<br/>NarrativeDraftingAiClient<br/>(per category; flags unsupported claims,<br/>never fabricates a citation)"]
        EXTRACT --> DRAFT
        POLICY --> DRAFT
        DRAFT --> SCORE["Risk Scoring Engine — DETERMINISTIC<br/>ScoringService.Calculate<br/>inherent x controls = residual<br/>(residual > 0, DB CHECK + C# guard)"]
        SCORE --> REVIEW["FCRM Analyst<br/>Review / Edit / Override<br/>(reason required)"]
        REVIEW --> COMMITTEE["Risk Committee<br/>Vote: approve / reject / defer / conditional"]
        COMMITTEE --> DECISION["Final Decision<br/>(quorum-based resolution rule)"]
    end

    CONFIG["Platform Configuration<br/>(FCRM Analyst, manual, reasoned)<br/>workflow_rule table"] -.->|governs, not tunes automatically| SCORE

    AUDIT[("Immutable Audit Trail<br/>append-only, DB trigger blocks UPDATE/DELETE")]
    MAP -.-> AUDIT
    EXTRACT -.-> AUDIT
    POLICY -.-> AUDIT
    DRAFT -.-> AUDIT
    SCORE -.-> AUDIT
    REVIEW -.-> AUDIT
    COMMITTEE -.-> AUDIT
    DECISION -.-> AUDIT
    CONFIG -.-> AUDIT

    DECISION -->|go-live flag, risk rating| CBS
    DECISION -->|updated vendor risk rating| VMS
    DECISION -->|customer/segment risk flag| CRM
    AUDIT -->|examiner-ready export| EXAM[Examiner / Regulator]

    class PO,REVIEW,COMMITTEE,DECISION human
    class MAP,EXTRACT,DRAFT ai
    class POLICY,SCORE deterministic
    class CR,INGEST,AUDIT,CONFIG,FRAMEWORK,CRM,CBS,VMS,POLICYLIB infra
```

- **Only 3 steps are AI:** category mapping, document extraction, narrative drafting — purple
- **Policy research & scoring are deterministic** — no LLM call, shown in blue
- **Category mapping is grounded** in the real FFIEC BSA/AML framework, not invented
- **Residual risk can never reach zero** — enforced by a DB check and a code guard
- **FCRM Analyst reviews before committee** — every edit/override needs a reason
- **Committee votes individually**; quorum-based rule decides the outcome
- **Every step is logged** to an append-only audit trail — nothing can be edited or deleted

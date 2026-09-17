# Humaid.RiskGovernance.AdminUI.UnitTests

**Owner:** Shanthi Subramanian (QA / Test Automation)

xUnit + Moq. No real database, no real HTTP call, no `docker compose` needed to run this — every
dependency is mocked via its own existing interface (`IChangeRequestRepo`, `IMockSystemsClient`,
`IChatCompletionClient`, `IAuditService`, ...).

```powershell
dotnet test tests/Humaid.RiskGovernance.AdminUI.UnitTests
```

## Scope

Curated to the invariants this project's own narrative rests on, not a coverage-percentage
exercise — each file tests a rule that's actually load-bearing:

| File | What it guards |
|---|---|
| `Scoring/ScoringServiceTests.cs` | Residual risk can never reach zero (`ScoringService`'s three C# checks, defense-in-depth on top of the DB's own `CHECK` constraints) |
| `Committee/CommitteeServiceTests.cs` | The quorum resolution rule (Reject > Defer > ApproveWithConditions > Approved) and Phase 3's feedback-loop push to Mock Systems, including that a Mock Systems outage never fails a vote |
| `ChangeRequests/ChangeRequestServiceTests.cs` | Content-type validation on both attach paths; `SubmitAsync` actually triggers Data Ingestion |
| `DataIngestion/DataIngestionServiceTests.cs` | No-op with no linked entity; partial resolution still saves; a Mock Systems outage doesn't fail intake |
| `Ai/*Tests.cs` | The citation-fabrication guard (never proposes/passes through something outside what it was given); empty-input short-circuits that skip the model entirely; malformed-response fallbacks |
| `DocumentProcessing/BlobStorageClientTests.cs` | A specific regression - config must be validated at call time, not constructor time (see the file's own comment for what broke and how) |

## Adding a test

New test classes follow the existing per-module folder layout, `Mock<TInterface>` per
dependency, and (for the AI clients) `FakeChatCompletionClient` rather than mocking `HttpClient`
directly - see `Ai/FakeChatCompletionClient.cs`'s own comment for why.

## Project context
The PR targets release/1.00 of the "Risk Assessment Workbench": an ASP.NET Core (.NET 10) API using Dapper over PostgreSQL, in a layered solution (src/1-API, 2-Infrastructure, 3-Service, 4-Persistence) plus a React/Vite webapp in webapp/. It is a hackathon project for a bank's financial-crime risk assessments, using synthetic data only.

Read CLAUDE.md at the repo root first -- it lists the non-negotiable rules. The ones most likely to be violated in a diff:
- The system prepares, humans decide: nothing may auto-approve or auto-reject.
- Any AI output (category mapping, extraction, narrative, score) must be stored alongside a human override AND the stated reason -- never overwritten in place.
- Audit records are append-only: flag any update/delete path for them.
- Residual risk must never be able to reach zero, in the calculation and in the configuration-save path.
- No secrets, keys or connection strings in code; configuration comes from environment variables.
DevBypassAuthHandler is intentional local-dev tooling -- only flag it if it can become active outside the Development environment.

## Focus, in priority order
Correctness bugs and unhandled edge cases; security (injection -- especially string-built SQL, authn/authz gaps, secret leakage, unsafe deserialization, sensitive data in logs); violations of the rules above; data-integrity/concurrency/async problems; error handling; then missing tests for new logic.

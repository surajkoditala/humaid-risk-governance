# Prompt/brief used to generate `db/seed.sql`'s bulk synthetic rows

Reproduced verbatim in spirit (the actual instruction was implicit in the Phase 3 Step 2 task
brief, not a separately-issued standalone prompt to a model) - logged here per the architect's
doc's requirement that generation prompts land in `/ai`.

```
Generate additional synthetic rows for three tables representing mock external banking systems:
mock_systems.crm_customer, mock_systems.core_banking_product, mock_systems.vendor_registry.

Constraints:
- 100% synthetic. No real customer, product, vendor, or company names - invent plausible-sounding
  ones (real-world entity-naming conventions are fine; the entities themselves must not exist).
- Every row must satisfy schema.sql's own CHECK constraints (customer_type, segment_classification,
  kyc_status, launch_change_type, vendor_risk_rating, certification_status enums) - an invalid
  value should fail the INSERT, not be silently coerced.
- Ground field values in the FFIEC BSA/AML risk categories this project already cites (Products &
  Services, Customers & Entities, Geographic Locations, Delivery Channels) - each row should read
  as a plausible instance of at least one of those categories, not generic filler.
- Include real-world-plausible jurisdictions across a risk spectrum (not every row high-risk, not
  every row low-risk) so downstream category-mapping/scoring has genuine variety to work with.
- Produce at least one row per table that deliberately does NOT map cleanly onto any FFIEC
  category (tests the "don't guess when nothing applies" path), and one vendor row with a missing
  or pending certification status (tests the human-review path for an under-documented third
  party).
- Keep the total set small (5-6 rows per table) - enough for real variety in a demo/eval, not a
  bulk-volume synthetic dataset generation exercise.
```

## What this produced

See `db/seed.sql` for the actual rows. Six `crm_customer` rows, five `core_banking_product` rows,
four `vendor_registry` rows, plus the one hand-authored golden-path row already counted in each of
those totals (see `ai/data-generation/README.md`'s "Approach" section for why that one row wasn't
generated the same way).

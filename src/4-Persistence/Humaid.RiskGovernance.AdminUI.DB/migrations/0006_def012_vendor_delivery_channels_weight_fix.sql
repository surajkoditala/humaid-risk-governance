-- DEF-012: CLAUDE.md lists both categories for Vendor with no "(heaviest)" qualifier, unlike the
-- Geography/CustomerSegment rows, which do call one out - so Delivery Channels should be Primary
-- too, not Secondary. seed_ffiec_framework.sql's own ON CONFLICT DO NOTHING will never touch an
-- existing row with the old value, so an already-seeded database needs this explicit correction.
UPDATE change_request_type_category_map
SET weight = 'Primary'
WHERE change_type = 'Vendor'
  AND risk_category_id = '22222222-2222-2222-2222-222222222224'
  AND weight = 'Secondary';

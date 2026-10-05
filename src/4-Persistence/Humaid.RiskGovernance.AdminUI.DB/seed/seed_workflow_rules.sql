-- Default workflow rules (Epic 10, US-10.2). Run after seed_dev_users.sql.
--
-- CommitteeQuorum: how many committee votes CommitteeService.cs waits for before resolving a
-- decision (Epic 8). This is the MVP's answer to CLAUDE.md's open question ("majority vote,
-- unanimous consent, or chair's call?") - see docs/architecture/architecture-mapping.md for the
-- documented resolution rule this quorum feeds into.
INSERT INTO workflow_rule (rule_key, rule_value, created_by_user_id, reason)
SELECT 'CommitteeQuorum', '{"quorum": 2}'::jsonb, u.id, 'Initial MVP default - see docs/architecture/architecture-mapping.md'
FROM app_user u
WHERE u.auth0_subject = 'seed|admin-1'
  AND NOT EXISTS (SELECT 1 FROM workflow_rule WHERE rule_key = 'CommitteeQuorum');

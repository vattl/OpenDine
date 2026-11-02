-- ============================================================================
-- DEPRECATED MANUAL MIGRATION NOTICE — superseded by Flyway V038.
--
-- Historical versions used t_access_approval.token_value for a directly usable
-- approval token. That behavior is insecure and must not be restored.
--
-- V038__approval_token_envelope.sql now:
--   1) creates/normalizes token_value as an AES-256-GCM envelope column;
--   2) expires active historical rows whose value lacks the authenticated aet:v1 prefix;
--   3) clears those historical plaintext values.
--
-- Do not execute the former ADD COLUMN varchar(128) plaintext migration.
-- Configure the same >=32-byte APPROVAL_TOKEN_ENVELOPE_KEY on every backend
-- instance before starting the upgraded application.
-- ============================================================================

SELECT 'Use Flyway V038__approval_token_envelope.sql; plaintext migration is retired' AS migration_notice;

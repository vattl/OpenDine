# WI-080 observed execution notes

## Remediation evidence source preservation

The deployment contract gained two additional assertions during review remediation. The original four-test source actually used for RED/GREEN/REFACTOR is preserved byte-for-byte at `execution-sources/T01-deployment-test-v1.py` with its original SHA-256. The final REGRESSION event points to the six-test production source. Journal event hashes were resealed after changing only the first three source paths and their dependent hash chain; commands, outputs, timestamps and classifications were not rewritten.

## Scope and provider
User authorized implementation after deployment-gap review and selected built-in independent audit. No production database, payment transaction, message, push or client UI change is authorized by this task.

## Workspace setup
The Git root is the monorepo parent of server. Workflow scripts assume `.ai` at the Git root, so an ignored local junction maps root `.ai` to `server/.ai`. No workflow validator was modified. Runtime registry lives in ignored `.ai-runtime`; server-local runtime initialization was needed for the existing workflow fixture that copies `server`.

Initial baseline: 159 tests passed and one existing workflow fixture failed because the fresh checkout had no ignored `server/.ai-runtime` directory. Initialized that runtime directory, then reran the same 160 tests: PASS. Initial output/readiness are archived in `preflight-attempts/`; final readiness generated from live Git by the original preflight script. Ready gate subsequently PASS before production edits.

## Test evidence line endings
The first actual assertion RED was valid as a behavioral failure but its raw-byte snapshot differed from Git because Windows checkout used CRLF. The implementer archived it under `execution-attempts/`, restored the original Compose bytes from Git for the same real test, observed RED again, then restored implementation. The canonical RED records equal production baseline/current hashes. No historical event was rewritten to claim success.

## Runtime isolation and diagnostics
Portable Temurin 8 was obtained from the official Adoptium API and its download SHA256 verified, under ignored `.local/tools`; system Java was not replaced. Official standalone Compose was downloaded with checksum validation. Compose config parsing passed with generated test environment and failed when JWT was omitted; no Docker engine is available, so container execution is not claimed.

A new MySQL 8.0.42 datadir was initialized under `.local/mysql-smoke/data`, bound to 127.0.0.1:33380. Generated local test credentials are ignored and never part of evidence. Resets verify `@@datadir` equals that exact test directory before dropping only `wi080_fresh`. No existing service/database is used.

First native bootstrap revealed an orphan `ALTER TABLE t_user_last_shop` in the shipped fresh-install baseline, immediately before `CREATE TABLE t_payment_ledger`; removed the incomplete fragment without inventing FK semantics. Second run reached V036 and MySQL rejected its leading UTF-8 BOM (SQLState 42000/code 1064). Execution strips the leading encoding marker; immutable migration bytes/checksums are preserved. A focused regression test covers BOM-prefixed SQL. These are actual implementation fixes, not suppressed SQL errors.

Final verification and acceptance results belong to TEST_REPORT.md and independent review artifacts; this note does not claim acceptance.

# WI-080 remediation: non-empty bootstrap refusal

- Git head: `afe877d104b6450d6d2e1c5d4ca71b714b2ffe65`
- Observed at: `2026-11-02 06:35 +08:00`
- Isolated listener: `127.0.0.1:33380`
- Database: `wi080_fresh`
- Safety check: listener executable was MySQL 8 and its command line selected this Work Item's `.local/mysql-smoke/data` directory.
- Runtime check: `@@port = 33380` and resolved `@@datadir` matched the isolated task directory.
- Before `(admins, shops, schema versions)`: `(1, 1, 49)`
- Command: `python .local/mysql-smoke/run_bootstrap.py`
- Exit code: `1` (expected)
- Refusal: `Target database is not empty; initialization refused before writing anything.`
- After `(admins, shops, schema versions)`: `(1, 1, 49)`
- Result: `PASS` — the empty-database guard refused the run and the checked durable counts were unchanged.

Credentials, generated secrets and connection strings are intentionally omitted.

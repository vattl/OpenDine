# Session Checkpoint

Date: 2026-09-09
Task: C009/T15 bounded SQLite outbox selection
State: COMMITTED admin_panel_flutter:fed3c86; C009 progress 17/24, T16 next.
Evidence: outbox/database/performance suites 40 passed; targeted analysis 0 issue; 10k outbox selection benchmark passed.
Design: SQL selects at most four due aggregate heads, then retrieves at most 50 consecutive events per selected aggregate. Inactive aggregate sequence index supports the head query; blocked heads retain ordering.
Residual: Validate file-backed SQLite recovery and much larger real-world backlogs in T22.
Next: T16.
Evidence: 18 selected tests passed, 0 failures/errors: ZSQ HTTP config2, coalesced auth1, remote client2, scheduler3, tracking6, redispatch3, cancellation1. Log .local/c011-t08-final-tests.log.
Build: mvn -o clean package -DskipTests -q succeeded; .local/c011-t08-package.log and JAR rebuilt.
Design: ZSQ now has a finite Apache connection pool (4 total/per-route, 1s lease, 2s connect, 5s read). Expired-token callers share one refresh when their failed credential remains current; the existing one retry remains.
Residual: real DNS/TLS interruption, connection exhaustion and peak capacity require T22. General WeChat, Feieyun and Amap HTTP clients were not altered by this ZSQ delivery task. No DDL/deploy. Preserve unrelated .ai/OpenAPI work and S01/S04/S10 exclusions.
Next: T09.

# Database Rules

Before schema changes determine:

- Existing rows
- NULL behavior
- Defaults
- Indexes
- Foreign keys
- Constraints
- Migration
- Rollback
- Production compatibility

Never assume an empty database.

Treat destructive changes as high risk.

Prefer staged evolution: Add → Backfill → Support transition → Verify → Remove legacy later.

Do not rewrite already-applied production migrations casually; prefer corrective migrations.

Meaningful schema changes require DATABASE.md update.

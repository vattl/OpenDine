# Requirement Traceability Rules

For STANDARD/STRUCTURAL/CRITICAL work, preserve a trace from original requirement to implementation and evidence.

Recommended chain:

REQ → TASK → DIFF/CHANGE → FILE/SYMBOL → TEST/EVIDENCE → COMMIT

At verification time, each material requirement must be one of:

- VERIFIED
- PARTIAL
- BLOCKED
- OUT_OF_SCOPE_AGREED
- UNKNOWN

Do not mark the parent work DONE while material requirements are PARTIAL/UNKNOWN.

Re-read the original request before final completion review. Long-running tasks must not rely on the agent remembering the request from chat context.

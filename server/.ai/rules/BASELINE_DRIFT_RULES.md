# Baseline Drift Rules

Baseline reuse must not become stale-memory blindness.

During relevant work, compare baseline assertions with repository evidence encountered naturally.

If conflict appears:
- LOCAL_DRIFT: update the affected baseline fact after verification
- SIGNIFICANT_DRIFT: pause planning long enough to reassess affected architecture/design assumptions
- REBASELINE_REQUIRED: foundation has materially changed; use `/rebaseline`

Never silently follow stale baseline prose when code/manifests/config show otherwise.

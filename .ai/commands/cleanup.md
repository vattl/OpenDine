# /cleanup

Identify and safely remove obsolete project weight.

Input: $ARGUMENTS

Inspect candidates such as:
- dead code,
- unused components,
- unused APIs,
- obsolete feature flags,
- unused dependencies,
- duplicate helpers,
- stale CSS,
- deprecated config,
- old tests that only cover removed behavior.

Do not delete uncertain shared code.

Classify:
- SAFE_TO_REMOVE
- STILL_USED
- DEPRECATED
- UNCERTAIN

Removal work must follow normal task-scoped commit and validation rules.

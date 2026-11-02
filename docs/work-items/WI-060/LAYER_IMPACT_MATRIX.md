# Layer Impact Matrix — WI-060

| Layer | Provider change | Consumer obligation | Status |
|---|---|---|---|
| API | same schema, fail-closed 503 documented | none | MAPPED |
| Domain | encrypted token delivery | none | MAPPED |
| Persistence | envelope-only value and legacy cleanup | apply migration | MAPPED |
| Flutter | none | none | VERIFIED_UNAFFECTED |
| Operations | new shared secret | configure all instances | HANDOFF |
| Docs/tests | synchronized | verify rollout | MAPPED |

UNKNOWN count: 0

# Layer Impact Matrix — WI-061

| Layer | Provider change | Consumer obligation | Status |
|---|---|---|---|
| API | structured 429; stricter 403 | parse retry data and show permission guidance | HANDOFF |
| Domain | exact action approval policy | use canonical action permissions | MAPPED |
| Persistence | permission seeds and limiter rows | apply V040 | MAPPED |
| Flutter | no code changed here | adopt binding v2, terminal ID, 429 countdown | HANDOFF |
| Operations | audit rejection semantics | monitor 403/429 trends | HANDOFF |
| Docs/tests | synchronized | verify consumer rollout | MAPPED |

UNKNOWN count: 0

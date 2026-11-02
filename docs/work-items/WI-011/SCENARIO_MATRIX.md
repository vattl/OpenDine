# Scenario Matrix — WI-011

| Scenario | Expected Result | Status | Evidence |
|---|---|---|---|
| POS/KDS legacy branch | branch becomes ancestor; tree unchanged | PASS | ancestor=true; tree hash unchanged |
| love-food legacy branch | branch becomes ancestor; tree unchanged | PASS | ancestor=true; tree hash unchanged |
| repository boundary | deleted cross-app directories remain absent | PASS | three legacy roots absent; all 22 refs covered |

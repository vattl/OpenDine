# v4.0 Role

This is a specialist SELF_VERIFY/REVIEW check inside a Work Item, not a separate lifecycle. If contract verification reveals consumer changes, update consumers or produce an API_CONSUMER_HANDOFF and keep acceptance truthful.


---

# /contract-verify

Verify consistency across:

Frontend request ↔ API/OpenAPI ↔ backend request DTO

Backend response DTO ↔ API/OpenAPI ↔ frontend type/mapping ↔ UI rendering

Also inspect semantic contract changes that are not represented by field names.

## Output

- Request Contract: PASS/FAIL
- Response Contract: PASS/FAIL
- Consumer Coverage: PASS/FAIL
- UI Interaction Consistency: PASS/FAIL
- Display Mapping: PASS/FAIL
- State/Action Mapping: PASS/FAIL
- CONTRACT_GAP items

Do not auto-resolve contract gaps with hidden mocks or client-side workarounds.

# v4.0 Integration

Capability repair is an escalation inside DISCOVER + DESIGN. `/bug` and `/work` should escalate automatically when a shared root cause/repeated patch/multiple consumers are discovered.


---

# Capability-Aware Repair Rules

- Fix the capability, not only the symptom.
- Identify the authoritative owner before patching consumers.
- Search direct and semantic duplicates of the same business rule.
- Review all known consumers of a changed shared capability.
- Prefer a central domain fix over caller-specific special cases when the rule is shared.
- Repeated `if caller == ...`, page-specific exceptions, or duplicated date/state logic are PATCH_SMELL signals.
- A symptom can be resolved while the capability remains inconsistent; that is PARTIAL, not DONE.

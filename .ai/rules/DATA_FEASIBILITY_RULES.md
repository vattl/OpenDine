# UI Data Feasibility Rules

UI design must verify that visible data and actions are supported by real project capabilities.

For each material UI datum/action classify:
- AVAILABLE
- DERIVABLE
- API_EXTENSION
- NEW_API
- NOT_SUPPORTED

Record the result in `PROTOTYPE_INTERACTION_CONTRACT.md`. This includes buttons, submissions, filters, sorting, pagination, uploads/downloads, state transitions, notifications, permission-dependent actions and visible server-derived values.

Do not fabricate prototype data requirements into assumed backend capabilities.
When API work is needed, generate a Backend Capability Request and connect it to the Work Item/Implementation Design.

`API_EXTENSION` and `NEW_API` require an assigned request before production UI editing. `NOT_SUPPORTED` blocks implementation until the interaction is removed/redesigned and the HTML prototype is re-approved, or backend capability work is authorized.

Before UI acceptance, all rows must be VERIFIED end-to-end, all required backend requests must be VERIFIED, unresolved backend capabilities must equal zero, and `BACKEND_COORDINATION_REPORT.md` must be CLEAR.

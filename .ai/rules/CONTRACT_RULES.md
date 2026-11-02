# v4.0 Integration

Material producer contract changes trigger API_CONSUMER_HANDOFF_RULES. Producer-only completion is not full acceptance when required consumers remain stale.


---

# Interface Contract Rules

Interfaces include more than HTTP APIs:

- REST/GraphQL contracts
- WebSocket messages
- Events
- Queue messages
- Webhooks
- Shared persisted payloads

For interface changes:
- identify producers and consumers,
- determine backward compatibility,
- version or migrate when necessary,
- add contract validation for important boundaries.

Do not change a payload field or semantic meaning silently.

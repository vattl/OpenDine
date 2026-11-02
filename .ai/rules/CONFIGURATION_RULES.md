# Configuration Rules

Every required configuration value must have a defined contract:

- key name,
- environment scope,
- required/optional,
- safe default when applicable,
- secret/non-secret classification,
- validation behavior.

Release validation must detect missing required configuration.

Never embed secrets in:
- source,
- Git history,
- logs,
- docs,
- test fixtures,
- screenshots.

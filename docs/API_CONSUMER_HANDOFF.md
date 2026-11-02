# API Consumer Handoff Guide

Use when a producer/backend/interface changes in a way that requires another frontend/service/agent to adapt.

The handoff is not a generic changelog. It must tell the consumer exactly what changed, how to call/map it now, what UI/state changes follow, whether compatibility is breaking, and how to verify migration.

If the repository contains the affected frontend and it is in scope, prefer updating it in the same Work Item rather than stopping at documentation.

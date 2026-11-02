# Dependency Governance

Before adding a third-party dependency, evaluate:

- Can existing project code solve this safely?
- Can the platform/standard library solve it?
- Is the package maintained?
- Runtime or bundle cost?
- Security history?
- License compatibility?
- Transitive dependency cost?
- Long-term ownership burden?

New dependencies are explicit Diff operations and must not be silently introduced.

Do not add a dependency merely to avoid writing a small, clear amount of project-native code.

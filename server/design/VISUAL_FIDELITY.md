# Visual Fidelity Workflow

For structural UI redesigns:

1. Create and approve HTML prototype.
2. Record target viewport.
3. Extract `measured-ui-spec.md`.
4. Create UI Diff.
5. Create `implementation-map.md`.
6. Implement in production while preserving business logic.
7. Render prototype and production at the same viewport.
8. Create `visual-comparison.md`.
9. Correct material differences.
10. Pass fidelity gate before task completion/commit.

Recommended files per prototype:

```text
design/prototypes/UI001-name/
├── index.html
├── prototype.md
├── approved.md
├── measured-ui-spec.md
├── implementation-map.md
└── visual-comparison.md
```

The prototype is not only a picture of the desired structure. It is the source for measurable scale, spacing, density and hierarchy.

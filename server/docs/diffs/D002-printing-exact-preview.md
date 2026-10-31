# D002 — 精确打印预览一致性

Status: COMPLETED

| Operation | Target | Target state |
|---|---|---|
| REPLACE | `previewExact` rendering path | Read-only use of the same rule/device/template renderer as dispatch; no mock fallback or print jobs. |
| ADD | Exact-context resolver | Strict current-shop order/shift/detail/refund resolution and business errors. |
| MODIFY | Preview response / AST | Per-ticket print source metadata; ordered native-control AST and warnings. |
| MODIFY | Template DSL | Explicit audio, control blocks, barcode validation and text binding warnings. |
| MODIFY | Cashier settings | Exact-preview request and display of true-source tickets/warnings while retaining mock design preview. |
| MODIFY | API contract | Exact endpoint permission and OpenAPI/API documentation. |

Negative acceptance: ordinary `/admin/printing/preview` retains its mock/template-design behavior; exact preview creates no `t_printing_job` records and never accepts mock or arbitrary business overrides.

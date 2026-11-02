# Contract Delta — WI-010

## Scope

接入 KDS 命令 revision/账本与跨日经营报表分支中已经设计的接口变化，不另行发明新契约。

## Sources of Truth

- `docs/openapi.yaml`
- `docs/API.md`
- `docs/KDS_ARCHITECTURE.md`
- `G:/Mini Program/my_project_admin_panel/admin_panel_flutter/docs/KDS_CLOUD_AUTHORITY_PROXY_ARCHITECTURE.md`

## Compatibility Rule

冲突时保留当前已验收接口与权限语义，并只叠加分支中不冲突的新能力；任何字段级变化必须同步两份 API 文档并由测试证明。

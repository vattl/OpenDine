# Third-Party Audit Packet — WI-075

Packet Status: SEALED
Work Item: WI-075
Implementer Agent: implementer-session-wi075
Prepared At: 2026-10-29T08:35:00+08:00
Reviewed Snapshot: snapshot-wi075-final
Acceptance Criteria: 6
Acceptance Contract SHA256: 1696340ae8d23fed1e9f41d8bed61511b6880c9135a5307aa7c5d2f7ae975819
Evidence Files: 10
Material Unknowns: 0

## Evidence Inventory

| Evidence ID | Path | SHA256 | Purpose |
|---|---|---|---|
| E01 | IMPLEMENTATION_DESIGN.md | 2088442c220bf646a2b37a354f54de0b63d40708722ce57916058a8a0f670422 | 技术方案与设计决策 |
| E02 | TEST_REPORT.md | 51c55459ee98634b00652c39494eed6583d7f7c0706f76772a1e8f09edbd74cf | 24项自动化测试执行报告 |
| E03 | SECURITY_AUDIT.md | a49e1fcee8c68e9c525af98dc6fd306ea538dac4f758f2ffba4fa706cfae3d76 | 威胁建模与多租户安全审计 |
| E04 | COMPLETION_EVIDENCE.md | 98d4615c964a95ad9e3e22dc19c62b6257618efa99fe10735cd44135e6a7a8ed | 代码变更与JAR打包构建物证据 |
| E05 | ACCEPTANCE_REPORT.md | b915a838988ea519f87263ce031867d524d1c46d5ab8bdbb76e31b27cf73f2ab | 6项验收准则核对总结报告 |
| E06 | ui/MEASURED_UI_SPEC.md | 6a56e136a15a6c6075ad2a837642a658a2271ccec781853639ce3c2f7a64e058 | 1280x800桌面端基准设计规范 |
| E07 | ui/STRUCTURAL_DIFF.md | 11bdbf27fa63194629e2b068f3bb909f2829fa300fc066a4720b7da9ed6bdb38 | 界面结构对比与合规清单 |
| E08 | ui/PROTOTYPE_INTERACTION_CONTRACT.md | 5b82d94bd3859bbf08f9f1d4f8651886c09377e7d4ea7887d3614417c3b1e22e | 6项交互能力映射契约 |
| E09 | ui/SCREENSHOT_VISUAL_DIFF_REPORT.md | 3090e2d574a0c2216d023058159890d542dc303807c7def65b8e30a9cff5bef5 | 原型与生产环境视觉比对报告 |
| E10 | ui/DEVICE_UX_VERIFICATION_REPORT.md | 53c35bec12dd869a839d4ac2a52a322b3363abe08b5732cd38361e59a0b4ca8b | 多端设备自适应验证报告 |

## Acceptance Contract

| Criterion ID | Requirement | Claimed Evidence |
|---|---|---|
| AC-01 | AC-01: 财务管理员可通过 `GET /admin/order/invoice/list` 分页拉取开票申请，默认优先展示 `TITLE_SUBMITTED` 待开票记录，支持关键词与状态过滤。 | E01, E02, E03, E08 |
| AC-02 | AC-02: 财务管理员可通过 `POST /admin/order/invoice/issue` 录入税控发票号码并将状态更新为 `SUCCESS`；可通过 `POST /admin/order/invoice/reject` 驳回异常申请并将状态更新为 `REJECTED`。 | E01, E02, E03, E04 |
| AC-03 | AC-03: 财务工作台界面提供指标卡、申请列表、一键复制税号/抬头、确认开具弹窗与驳回弹窗，交互流畅且无跨站脚本/协议注入漏洞。 | E01, E06, E07, E08, E09, E10 |
| AC-04 | AC-04: 顾客端 H5 页面在订单被驳回时友好展示驳回理由，并支持解锁表单让顾客重新修改提交，提交后重新进入 `TITLE_SUBMITTED` 待办。 | E01, E02, E07, E08, E10 |
| AC-05 | AC-05: 核心业务不变量严格保持：未支付订单禁止开票，已开票总额不可超过实付净额，普通商户不调用第三方服务商税控接口。 | E01, E02, E03, E04 |
| AC-06 | AC-06: 接口文档同步更新至 `docs/openapi.yaml` 与 `docs/API.md`，全量测试通过且 Maven 打包生成可运行 JAR。 | E01, E02, E04, E05 |

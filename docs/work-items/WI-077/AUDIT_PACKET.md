# Third-Party Audit Packet — WI-077

Packet Status: SEALED
Work Item: WI-077
Implementer Agent: implementer-session-wi077
Prepared At: 2026-10-30T00:18:00+08:00
Reviewed Snapshot: snapshot-wi077-completed
Acceptance Criteria: 7
Acceptance Contract SHA256: 9089b447a4bdde9e3f963e5912626de8ffde3b37f6ca8b7e94c712eb1898c46b
Evidence Files: 5
Material Unknowns: 0

## Evidence Inventory

| Evidence ID | Path | SHA256 | Purpose |
|---|---|---|---|
| E01 | IMPLEMENTATION_DESIGN.md | 0bb592062f080fee6c3f29c737880bd63980fd34f5a9c923b5b8692a530ebff2 | 权威税务解析架构、计划单列市前置与前端交互设计说明 |
| E02 | TEST_REPORT.md | 5d02e87fc4e892fc14291dfbc6654a0304d8afcbf1a8d1eb26803d5976edd8f9 | 32项自动化单元测试全通报告与DOM完整性报告 |
| E03 | SECURITY_AUDIT.md | fa91372ade357b437b668752cc9c4ba070fbfa53cae83bc3cf925757167254d9 | 官方域名白名单绑定、独立纳税主体防篡改与XSS转义安全审计报告 |
| E04 | COMPLETION_EVIDENCE.md | d5eb4f73d3fa60321faf4519a5f5124417963874fd7272252a025469bdc0ee9f | 代码交付物、文档同步与可运行JAR包构建凭证 |
| E05 | ACCEPTANCE_REPORT.md | 55a59aeabe287a9c09a5fcedd9ccb9ef4bb00e59acac050b78afaa38480c2bbc | 验收准则核对与验收决议报告 |

## Acceptance Contract

| Criterion ID | Requirement | Claimed Evidence |
|---|---|---|
| AC-01 | AC-01: 后端提供 `TaxBureauResolver` 权威解析器，覆盖国家税务总局全国统一规范电子税务局总入口及全国 36 个省级/计划单列市电子税务局官方门户，优先匹配计划单列市，精准支持省份与重点地级市关键词匹配，无地址或未识别时优雅回退全国统一电子税务局总门户。 | E01, E02, E04, E05 |
| AC-02 | AC-02: 订单发票实体 `OrderInvoice` 扩展扩展字段 `shop_address`、`tax_bureau_name`、`tax_bureau_url`；分页查询接口 `/admin/order/invoice/page` 自动丰富门店地址与所属税局门户信息。 | E01, E02, E04, E05 |
| AC-03 | AC-03: 管理员登录与门店摘要接口（`toShopSummaries`）扩展返回 `address`、`taxBureauName`、`taxBureauUrl`，使财务端全局掌握各门店纳税归属地及对应税局。 | E01, E04, E05 |
| AC-04 | AC-04: 财务工作台（`admin.html`）顶部导航栏提供「🏛️ 打开当地电子税局」一键直达入口；单店模式下直接新标签页打开对应税局，全部门店模式下弹出多门店税局导航抽屉与全国总平台入口。 | E01, E02, E04, E05 |
| AC-05 | AC-05: 财务工作台表格每行提供「🏛️ 税局开票」快捷操作，直达该笔发票销方门店对应的电子税局。 | E01, E02, E04, E05 |
| AC-06 | AC-06: 财务工作台「确认开票」弹窗内展示销方门店地址及匹配税局，提供「🌐 一键打开当地税局开票系统」与「📋 一键复制开票资料」按钮，方便财务在税局快速录入。 | E01, E02, E04, E05 |
| AC-07 | AC-07: 单元测试全覆盖解析规则，同步更新 `docs/openapi.yaml` 与 `docs/API.md`，执行 Maven 编译打包生成可运行 JAR 包。 | E02, E04, E05 |

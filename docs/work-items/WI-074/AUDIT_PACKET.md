# Third-Party Audit Packet — WI-074

Packet Status: SEALED
Work Item: WI-074
Implementer Agent: implementer-session-wi074
Prepared At: 2026-10-28T10:25:00+08:00
Reviewed Snapshot: snapshot-wi074-remediated
Acceptance Criteria: 6
Acceptance Contract SHA256: 25be533b4759c3b49da5a5ecc8db09d6cedf7e0b8fc428c205e050ad5af78ac7
Evidence Files: 9
Material Unknowns: 0

## Evidence Inventory

| Evidence ID | Path | SHA256 | Purpose |
|---|---|---|---|
| E01 | IMPLEMENTATION_DESIGN.md | 59f578acdcfce3733d12f5835f842dd2e400941fdb0698d766d4f214ce6df5c1 | 架构设计与根因治理说明 |
| E02 | TEST_REPORT.md | 50c7c54b7976cc1ebeec8bc4336e8a939eb7f020ac1c3b21cf458a73cdf96a6a | 29项测试用例与场景矩阵执行报告 |
| E03 | SECURITY_AUDIT.md | 471a01c6016e1277c6b6918c87628ffde1a09ec251d825ff30dbcd21717d97fd | 威胁建模与安全鉴权脱敏审计报告 |
| E04 | COMPLETION_EVIDENCE.md | 64d69faf32fa3c361c5e23755ef5a63f505bf741c0addb4a1a5d0ac8d4a421ac | 代码改动与可运行JAR构建物凭证 |
| E05 | ACCEPTANCE_REPORT.md | c09d0593eaab3aa2d264ac62a569317a5749f3fdedb151dc0e70a08a8c98175c | 验收准则核对与验收决议报告 |
| E06 | ui/MEASURED_UI_SPEC.md | aa85a0903340441d6dc99360791513b10868cdbc48ef0092cd2d242f6f59e005 | 390x844移动端基准设计规范 |
| E07 | ui/STRUCTURAL_DIFF.md | 748d122a63594a5400f6782ef6bba5b000a4d1d0d56f6510c04483c208d9f852 | 界面结构与合规改造差异清单 |
| E08 | ui/PROTOTYPE_INTERACTION_CONTRACT.md | 6b544bce54a1bec2bbb62ff8ba52cfb39eb8fbde97019a5fb841e144097d9c98 | 交互能力交付契约与端到端验证 |
| E09 | ui/SCREENSHOT_VISUAL_DIFF_REPORT.md | 83fa22a5d0e827e397881a86054cae22834a2d54f0d488696fde51f42f851134 | 视觉截图比对与零Delta差异报告 |

## Acceptance Contract

| Criterion ID | Requirement | Claimed Evidence |
|---|---|---|
| AC-01 | AC-01: 公开开票查询与提交接口实现 Token 强校验与防遍历，无有效 Token 或查无申请时直接返回错误，禁止匿名自动创建记录。 | E01, E02, E03 |
| AC-02 | AC-02: 敏感数据（税号、手机、邮箱）在日志中脱敏打印，在顾客端 H5 界面中掩码显示，修复公开泄露风险。 | E01, E02, E03, E07 |
| AC-03 | AC-03: 顾客端 H5 界面修正虚假税务总局宣称，明确标注门店登记属性，提交按钮实现防抖控制，下载链接具备安全校验。 | E06, E07, E08, E09 |
| AC-04 | AC-04: 服务端实现严格状态机与开票金额校验：未支付订单禁止开票，已开票金额 + 本次申请不得超过实付减去累计退款金额。 | E01, E02, E03, E04 |
| AC-05 | AC-05: 微信 JSAPI 下单通道增加可配置的 `support_fapiao: true` 参数传递支持。 | E01, E02, E04 |
| AC-06 | AC-06: 数据库通过 Flyway V050 引入 Token 哈希与时效字段，API 变更同步至 `docs/openapi.yaml`，并通过 Maven 打包验证。 | E01, E04, E05 |

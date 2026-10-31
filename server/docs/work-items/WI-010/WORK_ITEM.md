# WORK ITEM — WI-010

## Request

把所有服务端分支统一到一个可验证的本地集成基线，消除并行开发导致的功能回退；UI 分支由关联的 UI 工作项单独通过原型门禁后接入。

## Type

MAINTENANCE / INTEGRATION

## State

ACCEPTED

## Requirement Contract

### Goal

把三条尚未进入当前服务端基线的分支历史安全接入 `integration/unified-baseline-20261012`，保留已验收的多门店排序、账单自定义时间和加菜不改下单时间修复。

### Current behavior

服务端能力散落在 KDS 命令账本、跨日经营报表和外卖迭代分支；直接选择任一分支作为基线都会遗漏其他能力。外卖迭代分支相对当前基线仅剩本机数据库、PID、证书私钥和密码文件差异。

### Target behavior

- KDS 命令账本与 revision 能力合入且符合 KDS-CA-1.3 云端唯一权威约束。
- 跨日经营报表能力合入且保持门店营业窗口语义。
- 外卖迭代分支历史被接入，但 `.local` 运行物和凭据不进入目标树。
- WI-007、WI-008、WI-009 的业务不变量继续成立。

### Must preserve

- 云端是 KDS 身份、命令终态、revision 和事件序列的唯一权威。
- API 变更同步 `docs/openapi.yaml` 与 `docs/API.md`。
- 不推送远端、不改默认分支、不删除分支。
- 不吸收其他 worktree 中尚未提交的用户文件。

### Acceptance criteria

- [x] 三条服务端分支均成为集成分支祖先。
- [x] `.local`、私钥、root-password 和 MySQL 数据文件未进入集成树。
- [x] 三项既有业务修复的回归测试通过。
- [x] KDS 与报表专项测试通过。
- [x] 完整 Maven 测试与 JAR 打包通过。

### Open product questions

NONE。

## Impact Summary

见 `IMPACT_MAP.md`。

## Design Summary

见 `IMPLEMENTATION_DESIGN.md`。

## Tasks / Vertical Slices

- [x] T01 合并 KDS 命令账本分支并解决契约/迁移冲突。
- [x] T02 合并跨日经营报表分支并解决 API 文档冲突。
- [x] T03 以内容保留策略接入仅剩敏感本机运行物差异的外卖分支。
- [x] T04 运行专项、全量测试和 JAR 打包，完成独立复核。

## Verification Evidence

执行后记录到 `TEST_REPORT.md`、`SECURITY_AUDIT.md` 与 `COMPLETION_EVIDENCE.md`。

## Review

PASS：分支能力包含性、KDS 云端权威边界、敏感文件排除、API 文档同步和回归测试均复核通过。

## Acceptance Decision

ACCEPTED（服务端本地集成验收，不代表 UI 分支已集成、远端已推送或已发布）。

## Consumer Handoffs

包含 API/数据库契约的同仓服务端变更；UI 分支整合由后续 UI 工作项承接。

## Integration / Release

目标为本地 `INTEGRATED` 候选，不包含远端推送或部署。

## Related IDs

Parent request: merge-all-branches
UI follow-up: WI-011
Target branch: integration/unified-baseline-20261012

## Business Invariants

- INV-KDS-AUTHORITY-01：云端始终是 KDS 唯一业务权威。
- INV-ORDER-TIME-01：加菜不得改变订单首次创建时间。
- INV-SHOP-SORT-01：分类和菜品排序按门店隔离且确定。
- INV-BILL-RANGE-01：自定义账单时间范围仅 `admin:super` 可调用。
- INV-LOCAL-ARTIFACT-01：本机数据库、PID、证书私钥和密码不得进入统一基线。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-010/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-010/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

`ACCEPTED`

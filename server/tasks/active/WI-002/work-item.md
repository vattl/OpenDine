# WORK ITEM — WI-002

## Request

基于 2026-10-05 KDS 全链路审计，输出落地执行方案并开始修复当前 KDS 的跨门店、设备接管、命令越权、状态聚合和归档一致性问题。

## Type

REPAIR / SECURITY / BACKEND

## State

IMPLEMENTING

## Requirement Contract

### Goal

关闭可利用的 KDS 跨门店与越权路径，并使权限、订单完成、归档、回撤和配置语义与云端唯一权威契约一致。

### Current behavior

- `/kds/settings` 接受任意 `shop_id` 并返回含 `kds_pin` 的原始配置。
- KDS 设备命令入口可执行 POS 加菜/整行退菜；退菜未校验订单门店。
- V2 设备工作流权限主要由客户端隐藏按钮，服务端命令入口未统一校验。
- 整单完成无条件清台，忽略 `auto_off_order_on_kds_done`。
- 手工归档可隐藏未完成工单；完成即归档与 `archive_hours` 冲突。
- 聚合异常可被吞掉，形成明细与整单状态分裂。

### Target behavior

- 设备只能读取自身门店的非敏感 KDS 设置，响应绝不包含 PIN。
- KDS 设备入口拒绝 POS 财务命令；POS 管理入口保留独立 JWT/门店上下文，并在领域层再次校验门店。
- 所有 KDS 命令按设备 workflow、目标队列和命令类型在服务端授权。
- 自动清台严格受门店开关控制。
- 未完成订单不能归档；归档清理不破坏回撤和批次完整性。
- 核心聚合失败回滚当前命令或进入可恢复的明确失败状态。

### Must preserve

- 云端唯一权威、`command_id` 幂等、revision 冲突和 after-commit WS 语义。
- WI-001 已实现的 `done → ready_serve` 长期回撤。
- `/admin/order/commands` 的受控 POS 命令能力和正式收银接口。
- 收银 LAN 仅透明代理，不引入第二业务状态机。
- 现有打印任务幂等和重试行为。

### Acceptance criteria

- [x] 跨门店设置/PIN 读取测试由 RED 变 GREEN。
- [x] KDS 设备入口拒绝 POS 财务命令，管理员 POS 入口仍可用。
- [x] POS 退菜领域层验证订单门店。
- [ ] 工作流权限负向测试覆盖配菜、制作、传菜、退菜、归档和配置。
- [x] 自动清台开关测试通过。
- [ ] 未完成归档和物理清理边界测试通过。
- [ ] 聚合失败不会留下已提交的半状态。
- [x] `docs/openapi.yaml`、`docs/API.md` 与消费者交接同步。
- [ ] KDS 定向测试、完整 Maven 测试/编译以及 `mvn clean package -DskipTests` 成功。

### Open product questions

- 门店 PIN 自动绑定是现有明确产品能力；本 Work Item 先关闭 PIN 泄露和默认凭据暴露，再以兼容迁移方式处理默认 PIN，不在无消费者迁移时直接删除自动绑定。

## Impact Summary

见 `impact-map.md`。

## Design Summary

见 `implementation-design.md`。

## Tasks / Vertical Slices

- [x] T01 跨门店设置与 PIN 响应边界
- [x] T02 KDS 设备入口与 POS 财务命令隔离
- [x] T03 设备 workflow/配置服务端授权
- [x] T04 自动清台和完成回撤一致性
- [ ] T05 归档、历史与批次完整性
- [ ] T06 聚合事务失败语义
- [ ] T07 契约、消费者、全量验证与 JAR

## Verification Evidence

- RED 证据：T01/T02 13 个用例中 3 failures + 1 error；T03 1 failure + 1 error；T04 1 failure。
- GREEN：`KdsReplicationContractTest,KdsSettingsControllerSecurityTest,KdsWorkflowV2ConfigControllerTest,KdsV2CommandContractTest,KdsLegacySyncServiceTest,KdsWorkflowAuditScenariosTest` 通过。
- 宽回归：`*Kds*Test,AdminPosCommandControllerTest` 通过。
- 打包：`mvn clean package -DskipTests` BUILD SUCCESS，JAR `target/diancan-0.0.1-SNAPSHOT.jar`，SHA-256 `91BBD7E1ED9A9157DFE543F0B4F75FE7C9111A164F02939980F597639B2A8ADF`。
- `git diff --check` 通过（仅 Git 行尾转换提示）。

## Review

PENDING

## Acceptance Decision

PENDING

## Consumer Handoffs

见 `api-consumer-handoff.md`。

## Integration / Release

依赖 WI-001 先集成或在同一分支保留其差异；涉及 PIN 契约的服务端与 KDS/Admin 消费者必须按交接顺序发布。

## Related IDs

- Depends on: WI-001
- Workstream: KDS cloud authority security hardening
- Branch: feat/kds-dual-mode-architecture


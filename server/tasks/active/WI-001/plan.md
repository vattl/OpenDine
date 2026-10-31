# WI-001：KDS 已完成菜品长期回撤

## Requirement Contract

- Goal：保留完成后 5 秒快捷撤回，并允许提示消失后从“已完成”看板手动回撤到“待传菜”。
- Current：KDS 已完成卡片已有长期“回撤”入口，收银历史本地状态机也理解 `done → ready_serve`；但云端唯一权威 `KdsWorkflowService` 拒绝 `from_queue=done`，导致实际命令失败。
- Target：`POST /kds/v2/commands` 的 `revoke_item` 接受未清理已完成数量，按最近完成优先（LIFO）从 `done` 回到 `ready_serve`；5 秒快捷入口和长期入口使用同一命令语义。
- Must Preserve：云端唯一权威、同一 `command_id`/revision 幂等与冲突规则、原有 `ready_serve → pending_cook`、`pending_cook → pending_prep` 回撤、已清理/不存在/无已完成数量时拒绝。
- Acceptance：云端工作流和批次层测试通过；KDS 已完成卡片长期入口测试通过；OpenAPI/API.md 同步；完整 Maven JAR 打包成功。

## Impact Map

| Surface | Classification | Evidence / action |
|---|---|---|
| Authoritative owner | AFFECTED | 云端 `KdsWorkflowService` + `KdsFlowBatchService`；完成态回撤同时恢复订单头，避免 bootstrap 再次强制归入 done |
| KDS UI / interaction | VERIFIED_UNAFFECTED | 已完成菜品卡及整单卡已有长期“回撤”按钮；补交互回归测试 |
| Frontend state / API client | VERIFIED_UNAFFECTED | 已支持 `revoke_item`、`from_queue=done` 和乐观落点 `ready_serve` |
| Request contract | AFFECTED | `revoke_item.target.from_queue` 有效语义扩展为 `done` |
| Controller / auth | VERIFIED_UNAFFECTED | 复用 `/kds/v2/commands`、设备 Token 与现有命令账本 |
| Service / domain | AFFECTED | 已完成批次反向迁移到待传菜；清除 `served_at` 供再次完成重记时间 |
| Persistence / schema | AFFECTED | 复用 `t_kds_flow_batch.queue_status`，并将显式回撤订单恢复为 `order_receiving=rec_order`、清除 `off_time`；无迁移 |
| Response / event | AFFECTED | patch 的工作流落点为 `ready_serve`，现有响应结构不变 |
| Cashier LAN proxy | VERIFIED_UNAFFECTED | KDS-CA-1.3 下仅透明代理同一云端命令，不拥有业务状态机 |
| Printing | VERIFIED_UNAFFECTED | 回撤不触发传菜单；再次 `ready_serve → done` 时按既有规则打印 |
| Tests / release | AFFECTED | 云端服务、批次层、KDS widget、完整 JAR 打包 |

## Contract Delta

- Endpoint：`POST /kds/v2/commands`
- Before：`revoke_item` 仅接受 `pending_cook`、`ready_serve`。
- After：新增接受 `done`，将指定已完成数量回撤到 `ready_serve`。
- Compatibility：NON_BREAKING；现有请求/响应字段、鉴权、状态码、幂等规则不变。
- Consumers：KDS 客户端已具备请求构造、状态映射和长期操作入口，不需要生产代码迁移；以 widget 测试确认。

## Implementation Design

1. 在批次权威层增加 `DONE → READY_SERVE` 的 LIFO 反向迁移，并清除回撤份数的 `served_at`。
2. 在工作流层允许 `from_queue=done`，仅选择仍有 `served_quantity` 的有效工单；迁移后同步工单/整单聚合并发布既有 patch。
3. 显式完成态回撤成功后同步恢复订单头 `order_receiving=rec_order` 并清除 `off_time`，确保命令补丁和后续 bootstrap 都落入 `ready_serve`。
4. 保持 5 秒快捷撤回不变；长期按钮继续发送同一 `revoke_item`。
5. 同步 API 文档并执行定向测试与强制完整打包。

## Verification Plan

1. RED/GREEN：`KdsWorkflowServePrintTimingTest` 复现云端拒绝并验证落点。
2. 批次测试：验证部分数量拆批、`READY_SERVE` 落点和 `served_at` 清除。
3. KDS widget：验证不依赖 5 秒提示的已完成卡片仍发送 `from_queue=done`。
4. `mvn clean package -DskipTests` 生成 runnable JAR。

## Acceptance Evidence

- 后端定向回归：`KdsWorkflowServePrintTimingTest`、`KdsFlowBatchCompletedRevokeTest`、`KdsBootstrapWindowIsolationTest`，共 11 项通过。
- KDS 客户端：`done queue keeps manual revoke available after quick undo expires`，1 项通过。
- 契约：`docs/openapi.yaml` 通过 YAML 解析，`docs/API.md` 同步。
- 发布包：`mvn clean package -DskipTests` 成功；生成 `target/diancan-0.0.1-SNAPSHOT.jar`，SHA-256 `3E8B5C6AE53983465125493FB487E439265B1EC1E502C972198D40ED0FA255E2`。


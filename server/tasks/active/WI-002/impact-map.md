# Impact Map — WI-002

## Authoritative Owner

- 身份与门店：`KdsDeviceAuthInterceptor`、`KdsDeviceController`、`KdsDeviceService`
- 设置边界：`KdsSettingsController`、管理员 KDS 配置接口
- 命令权威：`KdsWorkflowV2Controller`、`KdsWorkflowV2Service`
- 数量状态机：`KdsWorkflowService`、`KdsFlowBatchService`
- 整单状态：`KdsOrderStatusAggregator`、`KdsLegacySyncService`
- 归档：`KdsArchiveJob`、V2 archive commands

## Change Propagation Path

```text
KDS/Admin/POS 输入
→ Token/JWT 与门店上下文
→ HTTP 控制器授权
→ V2 命令账本与 revision
→ 工作流/订单/库存领域事务
→ ticket/batch/order/config
→ event_seq / command result / WS
→ KDS、收银代理、管理端消费者
```

## Consumer Coverage

| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| `KDS_front/kds_app` | 设备登录、V2 命令/config | AFFECTED | PIN 默认值与权限错误展示需同步 | `login_page.dart`、`kds_v2_client.dart` |
| `admin_panel_flutter` | PIN 管理、LAN 透明代理、正式 POS | AFFECTED | PIN 空态/轮换文案需同步；POS 正式接口不变 | `kds_devices_page.dart`、`cashier_kds_lan_server.dart` |
| `/admin/order/commands` | 管理员 POS 命令 | AFFECTED | 保留受控入口，与 KDS 设备入口隔离 | `AdminPosCommandController` |
| 收银正式接口 | `/cashier/order/addDishes|refundDish` | VERIFIED_UNAFFECTED | 否 | JWT/权限码路径独立 |
| LAN 代理 | 原样转发云端 KDS 路径 | VERIFIED_UNAFFECTED | 否，错误码原样透传 | Cloud-authority 文档 |
| C 端小程序 | 普通订单接口 | VERIFIED_UNAFFECTED | 否 | 不调用 KDS 设备接口 |

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | AFFECTED | KDS/Admin PIN 默认值和权限拒绝提示 |
| Interaction | AFFECTED | 自动绑定前置条件和无权限命令反馈 |
| Frontend State | VERIFIED_UNAFFECTED | V2 patch/outbox 状态结构不变 |
| API Client | AFFECTED | `/kds/settings` 不再支持裸 shop 查询/原始 config |
| Request Contract | AFFECTED | KDS 设备命令允许集合收紧 |
| Backend/Domain | AFFECTED | 鉴权、门店、状态、归档、事务 |
| Persistence | AFFECTED | 复用现有表；PIN 迁移可能需数据脚本 |
| Response Contract | AFFECTED | 设置响应移除敏感原始字段 |
| Jobs/Events/Integrations | AFFECTED | 归档任务与事件一致性 |
| Config/Security | AFFECTED | PIN、设备 workflow、管理员边界 |
| Runtime/NFR | AFFECTED | 登录限流/错误信息与事务可靠性 |
| Tests | AFFECTED | 控制器、领域、契约、集成、打包 |

## Duplicate Logic / Patch Smells

- legacy workflow controller 有 `canAccessQueue`，V2 命令入口缺失。
- KDS 设备和管理员 POS 共用 `executeCommand`，必须在入口区分 actor 能力并在领域层保留租户校验。
- `archived` 同时表示“刚完成”“超时归档”“手工隐藏”，语义混用。
- `auto_off_order_on_kds_done` 有读取函数但业务路径未使用。

## Contract Delta Summary

- `/kds/settings`：由“token 或裸 shop_id，返回原始 config”收紧为“必须 token，仅自身门店，返回非敏感 settings”。
- `/kds/v2/commands`：设备入口拒绝 `pos_add_dishes/addDishes/pos_refund_dish/refundDish`；管理员 POS 入口继续支持。
- 标准 KDS 命令：新增服务端 workflow/命令授权，拒绝返回 403。

## UI Semantic Impact

安全拒绝必须展示为权限/重新绑定问题，不得进入 UNKNOWN 重试；PIN 未配置时引导管理员设置，而不是预填 `123456`。

## Risks

- 旧 KDS 客户端依赖裸 settings 或默认 PIN 时会显式失败，需要消费者同步。
- 收紧权限可能暴露历史设备 workflow 配置缺失；默认推导规则必须保持兼容。
- 归档语义调整会影响 done 队列数量和历史页，需要回归 bootstrap/changes/business-day。


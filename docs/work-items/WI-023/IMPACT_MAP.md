# Impact Map — WI-023

## Authoritative Owner

新增 `com.lanf.receivable` 模块作为应收账户、应收单和不可变应收流水的唯一业务权威；订单仅保存完成结账后的展示状态，不承担应收余额真相。`DailyCloseServiceImpl` 只消费该模块提供的窗口汇总。

## Change Propagation Path

```text
收银/管理端请求
→ SysInterceptor 认证、权限和门店解析
→ Receivable Controller DTO 边界校验
→ ReceivableService 事务/行锁/额度规则
→ t_receivable_account + t_receivable_claim + t_receivable_ledger + t_order
→ 应收响应 / 日结窗口汇总
→ 外部收银和管理端消费者
```

## Consumer Coverage

| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| 收银端 | 发起挂账、查看账户/应收、收款 | AFFECTED | YES | 新增 API，见 handoff |
| 管理端 | 账户管理、坏账、账龄和对账单 | AFFECTED | YES | 新增 API，见 handoff |
| 微信小程序 | 既有支付 | VERIFIED_UNAFFECTED | NO | 不暴露 C 端挂账入口 |
| KDS/打印 | 挂账后履约 | AFFECTED | NO contract change | 复用 `PaymentSuccessHandler.run(order, 0)` |
| 日结/X-Z 报表 | 销售与实收分离 | AFFECTED | additive response fields | `DailyCloseServiceImpl` |
| 支付/退款/对账 | 真实支付权威 | AFFECTED | guard only | 挂账不得创建 PaymentLedger |

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | UI 仓库不在本检出；交付消费者 handoff |
| Interaction | AFFECTED | 新增账户、挂账、回款、撤销、坏账操作语义 |
| Frontend State | AFFECTED | 新增账户/应收状态枚举与账龄数据 |
| API Client | AFFECTED | 新增 `/cashier/receivables/**`、`/admin/receivables/**` |
| Request Contract | AFFECTED | DTO、幂等键、分页、金额和状态校验 |
| Backend/Domain | AFFECTED | 新增应收领域服务及订单转换事务 |
| Persistence | AFFECTED | V025 三表和日结快照扩列 |
| Response Contract | AFFECTED | 新增资源响应与日结 `receivable_summary` |
| Jobs/Events/Integrations | VERIFIED_UNAFFECTED | 无新外部支付/定时任务；履约复用既有 after-commit |
| Config/Security | AFFECTED | 新权限码、接口映射、门店隔离、审计 |
| Runtime/NFR | AFFECTED | 行锁、幂等唯一键、分页、索引和不可变流水 |
| Tests | AFFECTED | 服务、控制器、权限、日结和回归测试 |

## Duplicate Logic / Patch Smells

- `/cashier/order/hang` 是“挂单”占位，不作为应收实现基础。
- 不把“挂账”加入普通支付渠道，不用 `PaymentLedger.CHANNEL_OTHER` 伪装收款。
- 不在 Controller 重复额度和门店规则；统一由 `ReceivableService` 处理。

## Contract Delta Summary

新增 API 和日结可选字段，既有请求字段不删除。消费者需要实现新功能入口，但旧支付客户端保持兼容。

## UI Semantic Impact

外部客户端必须区分“挂单（暂不处理）”“挂账（形成应收）”“回款（实际收款）”；禁止继续将三者显示为同一个按钮或状态。

## Risks

- 并发挂账突破额度：账户与订单 `FOR UPDATE` + 唯一键。
- 重试重复入账：商户级 request_id 唯一约束。
- 日结虚增实收：挂账跳过支付台账，实收改由真实台账汇总。
- 越权跨店：所有查写条件包含 merchant/shop scope，MERCHANT 账户显式放行。
- 撤销破坏历史：仅零回款 OPEN 应收允许撤销；其余追加坏账/回款流水。

## Unknowns

NONE

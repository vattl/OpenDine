# Implementation Design — WI-023

## Root Fix / Owner

新增独立 `receivable` 领域，而不是把挂账塞进支付渠道。应收账户保存授信与当前占用，应收单保存订单级余额和到期日，不可变流水保存每次 CHARGE/COLLECTION/REVERSAL/WRITE_OFF。领域服务持有唯一写路径，并通过行锁、唯一幂等键和事务维护资金不变量。

## Data Model

- `t_receivable_account`：merchant/shop scope、客户资料、额度、账期、状态、未清余额、版本和审计字段。
- `t_receivable_claim`：一单一应收，原始金额、未清金额、到期日、OPEN/PARTIAL/SETTLED/OVERDUE/WRITTEN_OFF/REVERSED。
- `t_receivable_ledger`：不可变有符号流水；CHARGE 为正，COLLECTION/REVERSAL/WRITE_OFF 为负；保存渠道、营业日、操作人、请求幂等键和原流水引用。
- `t_daily_close_snapshot`：增加应收新增、回款、坏账、期末余额、实际收款和应收水位字段。

## API Design

- Admin accounts: create/list/detail/update/status/close。
- Cashier: eligible accounts、charge order、claim/detail、collect。
- Admin receivables: claims、statement、aging、collect、reverse、write-off。
- 所有写请求要求 `requestId`，服务端拒绝同一键不同业务参数的重放。
- 列表采用 cursor/limit 或 page/pageSize 的有界分页。

## Order / Fulfillment Semantics

成功挂账后订单置为业务已结 `success`，`payment_method=挂账`、支付分项为 0，并用 `pay_time` 记录业务结账时刻。应收单是欠款真相。挂账不生成 PaymentLedger；既有支付台账自愈必须显式跳过挂账订单。事务提交后以零支付金额运行既有履约处理，避免积分/邀请返利按未收金额发放。

## Daily Close Semantics

- `net_sales_fen` 保持销售口径，包含挂账销售。
- `receivable_charged_fen` 是本营业窗口新增应收。
- `receivable_collected_fen` 是本营业窗口真实回款。
- `receivable_writeoff_fen` 不属于实收。
- `total_collections_fen = 支付台账净收款 + 应收回款 + 充值本金`。
- 期末应收余额按门店范围从账户/应收单汇总，不因日结清零。

## Security / Failure Design

- 认证门店来自 `AdminShopRequest`，不接受 body 中的 shopId 覆盖。
- 账户管理、挂账、回款和坏账使用独立权限；坏账必须非空原因并全量审计。
- 金额使用整数分；客户端不提交挂账金额，回款金额必须正且不超过未清。
- 所有财务写入在事务内失败回滚；after-commit 履约失败不回滚财务真相并保留日志。
- 账户关闭前必须零余额；暂停账户禁止新增挂账但允许回款。

## Compatibility / Migration

- V025 为加法迁移，不修改 `t_order.transac_status` enum。
- `/cashier/order/hang` 保持兼容，不代表应收。
- 日结新增字段为加法；旧客户端可忽略。
- 外部 UI 未在本仓库，提供 `API_CONSUMER_HANDOFF.md`，后端验收状态不得冒充 UI 已完成。

## Vertical Slices

1. 账户、三表迁移、权限、分页查询。
2. 挂账事务、订单/履约、支付台账隔离。
3. 回款、撤销、坏账和账户对账单。
4. 账龄、逾期与日结销售/实收分离。
5. 契约同步、消费者交接、回归、打包、审查。

## Verification Strategy

1. TDD：先写账户额度/范围、挂账幂等与超额失败测试。
2. TDD：覆盖部分回款、全额结清、超收、重复回款、撤销和坏账。
3. 日结测试证明挂账计销售不计实收、后续回款在实际发生日计实收。
4. 权限映射和跨店访问测试。
5. 全量 Maven 测试、迁移/schema 审查、secret scan、`mvnw.cmd clean package -DskipTests`。

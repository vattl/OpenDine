# API Consumer Handoff — WI-023

## Interface

`/cashier/receivables/**`, `/admin/receivables/**` 以及日结响应 `receivable_summary`。

## Compatibility

ACTION_REQUIRED（仅新挂账功能）；现有支付流程 NON_BREAKING。

## Before

`/cashier/order/hang` 仅返回订单号，没有真实挂账能力。

## After

消费者通过独立应收端点选择授信账户、提交订单挂账、查询应收、执行回款；管理端管理账户、账龄、撤销和坏账。

## Consumer Impact

收银 Flutter/管理端和可能的其他 POS 客户端需要新增类型、API client、页面和权限态。服务端仓库不包含这些文件。

## Required Frontend / Consumer Changes

1. 将“挂单”与“挂账”拆成不同操作。
2. 挂账前查询 eligible accounts 并展示额度、可用额度和账期。
3. 每次财务写操作生成稳定 `requestId`，失败重试复用同一值。
4. 显示应收状态、到期日、未清金额、回款流水和账龄。
5. 根据 403/409/422 错误禁用或提示超额度、跨店、状态冲突。

## Type / Model Changes

新增 Account、Claim、Ledger、AgingSummary、ReceivableSummary；金额均为 `*_fen` 整数。

## Request Construction

不得提交挂账金额；charge 只提交 `orderNo/accountId/requestId/note`。collect 提交 `claimId/amountFen/channel/requestId/note`。

## Response Mapping / Display

状态使用服务端英文稳定码，UI 映射中文；禁止把 WRITTEN_OFF 显示为已收款。

## UI / Interaction Impact

需要新界面，必须在消费者仓库遵循其 UI 原型审批流程；本 Work Item 不声称 UI 已实现。

## Example Call

`POST /cashier/receivables/charges {"orderNo":"ORD...","accountId":12,"requestId":"POS-AR-001"}`

## Example Response

`{"code":0,"claim":{"status":"OPEN","originalAmountFen":12800,"outstandingFen":12800}}`

## Defaults / Fallbacks

账户默认 SHOP 范围；状态未知时客户端只读展示，不允许猜测可操作性。

## Rollout / Migration Order

数据库迁移 → 服务端 → API contract → 收银/管理端功能开关启用。

## Verification Checklist

- [ ] consumer request updated
- [ ] consumer response mapping updated
- [ ] UI/state semantics updated if applicable
- [ ] old contract references removed or intentionally supported
- [ ] end-to-end flow verified

## Owner / Status

External cashier/admin consumer teams — PENDING。后端完成后 Work Item 仅可标记 backend ACCEPTED / consumer pending。

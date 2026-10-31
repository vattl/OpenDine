# API Consumer Handoff — WI-067

## Interface

`GET /admin/daily/pre-check`, `POST /admin/daily/settle`, 日结只读摘要接口。

## Compatibility

ACTION_REQUIRED

## Before

Flutter `DailySettlePage` 用客户端本机时间和硬编码 16:00 计算 `_businessDate`，随后把该日期传给所有接口。

## After

页面先调用不带 `stat_date` 的 precheck，以响应 `stat_date/next_close_business_day` 作为该次页面会话唯一目标日。

## Consumer Impact

若不修改消费者，后端能拒绝跳日，但页面标题和摘要仍可能显示错误日期。

## Required Frontend / Consumer Changes

1. 删除 `_businessDate` 作为业务权威的用途。
2. 首先调用 `precheckDaily()`，再用返回日期加载 summary/channel/gross-profit。
3. settle/Z 报表均使用同一服务端日期。
4. 展示 pending_day_count 和历史待结提示。
5. 409 顺序冲突时重新加载 precheck，不自动重试 settle。

## Type / Model Changes

`DailyPrecheckResult` 增加 `currentBusinessDay`、`nextCloseBusinessDay`、`pendingDayCount`、`hasPreviousUnclosedDay`。

## Request Construction

首次 precheck 不传 `stat_date`；执行 settle 时传 precheck 返回的 `statDate` 与 token。

## Response Mapping / Display

标题显示“待日结营业日 yyyy-MM-dd”；有积压时显示“还有 N 个营业日待处理，完成后自动进入下一日”。

## UI / Interaction Impact

可参考 UI-DAILY-SEQUENCE-001 HTML 原型；该原型未作为本次后端工作的生产 UI 批准或实现。

## Example Call

`GET /admin/daily/pre-check`

## Example Response

```json
{
  "stat_date": "2026-10-24",
  "current_business_day": "2026-10-25",
  "next_close_business_day": "2026-10-24",
  "pending_day_count": 2,
  "has_previous_unclosed_day": true,
  "can_settle": true
}
```

## Defaults / Fallbacks

precheck 加载失败时不得以本机日期执行日结；页面保留只读错误态和重试入口。

## Rollout / Migration Order

后端兼容加字段和 409 先部署，随后 Flutter 消费者启用权威日期；完成端到端验证后接受 UI。

## Verification Checklist

- [ ] consumer request updated
- [ ] consumer response mapping updated
- [ ] UI/state semantics updated if applicable
- [ ] old local-date authority removed
- [ ] end-to-end flow verified

## Owner / Status

Owner: `my_project_admin_panel/admin_mini`; Status: PLANNED

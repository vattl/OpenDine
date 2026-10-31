# Contract Delta — WI-067

## Before

- `stat_date` 缺省等于当前活动营业班次。
- 调用者可传任意营业日进入 precheck/settle。
- precheck 仅返回所选日及预览，无积压/权威 next 信息。

## After

- `GET /admin/daily/pre-check` 缺省选择 `next_close_business_day`。
- 响应新增：
  - `current_business_day: string(date)`
  - `next_close_business_day: string(date)`
  - `pending_day_count: integer >= 0`
  - `has_previous_unclosed_day: boolean`
- `POST /admin/daily/settle` 请求日不等于 next 时返回 HTTP 409：

```json
{
  "code": 409,
  "error_code": "DAILY_CLOSE_OUT_OF_SEQUENCE",
  "msg": "存在更早未日结营业日，请按顺序完成日结",
  "details": {
    "expected_business_day": "2026-10-24",
    "requested_business_day": "2026-10-25"
  }
}
```

## Compatibility

ACTION_REQUIRED：正确顺序调用保持兼容；依赖客户端本地日期的消费者必须先取 precheck 权威日期。历史显式只读查询保持原义。

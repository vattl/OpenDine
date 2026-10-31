# API Consumer Handoff — WI-068

## Interface

`GET /admin/daily/z-reports`

## Compatibility

ACTION_REQUIRED

## Consumer Changes

1. 按 `close_state` 显示已结、待日结、已重开。
2. 只有 `can_close=true` 的行显示“去日结”入口。
3. 点击时把该行 `business_day` 传给日结页面；进入后仍以 pre-check 返回值为权威。
4. `id` 可为 null，不得作为未结行的导航条件。
5. `cursor` 仅原样回传，禁止按快照主键解释。

## Example

```json
{
  "current_business_day": "2026-10-25",
  "next_close_business_day": "2026-10-24",
  "items": [
    {"business_day":"2026-10-25","close_state":"PENDING","can_close":false},
    {"business_day":"2026-10-24","close_state":"PENDING","can_close":true},
    {"business_day":"2026-10-23","close_state":"CLOSED","can_close":false,"id":101}
  ],
  "has_more": false,
  "next_cursor": null
}
```

## Owner / Status

Owner: external Flutter/admin client; Status: PLANNED（本 Work Item 仅后端）。

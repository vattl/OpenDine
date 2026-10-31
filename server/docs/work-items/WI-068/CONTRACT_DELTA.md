# Contract Delta — WI-068

## Before

- `items` 只包含 `state=CLOSED` 的持久化快照。
- 缺失/重开营业日不可见，前端无法从历史列表识别待结日。
- `cursor` 实际为快照主键。

## After

- `items` 按营业日倒序连续返回，并新增：
  - `close_state: CLOSED|PENDING|REOPENED`
  - `can_close: boolean`
  - `is_next_close_business_day: boolean`
- 响应新增 `current_business_day`、`next_close_business_day`。
- 无快照项以 `id/snapshot_no/closed_at` 等 nullable 字段表达，不伪造财务数据。
- `next_cursor` 是不透明 long，当前编码为 `yyyyMMdd`；请求语义为排他上界。

## Compatibility

ACTION_REQUIRED：字段为加法兼容，但 `items` 会新增未结行且游标底层含义变化。消费者不得把 `items` 全部视为已结快照，也不得解释游标；旧快照 ID 游标在过渡期仍接受。

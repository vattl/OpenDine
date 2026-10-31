# Implementation Design — WI-068

## Route

- Work type: CHANGE
- Complexity: STANDARD
- UI impact: NONE
- Contract impact: PROVIDER_ACTION + CONSUMER_ACTION
- Baseline impact: LEVEL_1
- UI design track: NOT_APPLICABLE（后端限定）

## API Design

沿用 `GET /admin/daily/z-reports` 和现有查询参数。`cursor` 继续是客户端不得解释的 long；新响应值编码为 `yyyyMMdd`，代表本页最后一日，下一页从其前一日开始。为滚动升级兼容，收到非有效日期游标时按旧快照 ID 查询其营业日并转换。

`items[]` 以营业日倒序返回：

- `CLOSED`：有 CLOSED 快照，原字段完整。
- `REOPENED`：有 REOPENED 快照，保留快照身份和审计字段，财务汇总仍取最后快照值。
- `PENDING`：日结序列锚点至当前营业日之间无快照。
- `can_close` 仅在 `business_day == next_close_business_day` 且状态非 CLOSED 时为 true。

响应顶层增加 `current_business_day` 和 `next_close_business_day`，便于消费者校验上下文。

## Root Fix / Owner

根因是历史列表以“已存在的 CLOSED 快照行”为分页实体，无法表达序列中的缺失日期；修复归属 `DailyCloseServiceImpl`，由它把 WI-067 的权威序列投影成连续的只读列表。控制器不复制状态判断。

## Data Access

1. 复用 `resolveCloseSequence(shop)` 获得当前营业日、锚点快照映射与最早待结日。
2. 根据 `date_to`、`cursor`、`date_from` 和序列锚点计算最多 `limit + 1` 个日期。
3. 从序列映射直接组装，不逐日访问数据库。
4. 旧游标只额外执行一次 `selectById`。

## Error Handling

- 非法日期沿用日期解析异常，由控制器包装 `Z_REPORTS_FAILED`。
- 未来 `date_to` 裁剪到当前权威营业日。
- 不属于当前门店的旧 ID 游标不用于定位，退化为空页而不泄露日期。

## Verification Strategy

- 单元测试先失败后通过，覆盖连续缺口、REOPENED、唯一 can_close、分页与旧游标。
- 运行 `DailyCloseServiceTest` 专项回归。
- 运行全量测试并披露任何既有失败。
- 解析 OpenAPI、运行 `git diff --check`。
- API 变化后执行 `mvnw.cmd clean package -DskipTests` 并验证 JAR。

## Vertical Slices

1. 连续状态列表及唯一可操作日。
2. 日期范围、日期游标与旧游标兼容。
3. 契约、测试和打包证据。

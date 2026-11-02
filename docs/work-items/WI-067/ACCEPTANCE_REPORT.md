# Acceptance Report — WI-067

Decision: ACCEPTED

## Acceptance Basis

- 后端以门店快照序列为权威，默认返回最早缺失或 `REOPENED` 营业日。
- 预检、正式日结和相关写入入口均不能跳过前序营业日，稳定返回结构化 HTTP 409。
- 后续营业日的钱箱与财务变化不会污染历史补结窗口。
- 重开只允许最后一个快照营业日，再次日结不会违反 `(shop_id, business_day)` 唯一约束。
- 专项自动化测试、API 契约同步、YAML 解析和完整 JAR 打包均通过。
- 用户限定仅修复后端，生产前端未改；消费者后续工作已通过 handoff 明示。

## Completion Level

ACCEPTED in repository for backend scope. Not claimed INTEGRATED or RELEASED; frontend consumer adaptation is not claimed.

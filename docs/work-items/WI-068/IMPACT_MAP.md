# Impact Map — WI-068

## Authoritative Owner

- 日结序列和状态：`DailyCloseServiceImpl`。
- 历史 Z 报表 HTTP 契约：`AdminDailyController` + `IDailyCloseService`。
- 快照事实：`t_daily_close_snapshot` / `DailyCloseSnapshotMapper`。
- 消费者：仓库外 Flutter/admin 客户端。

## Change Propagation Path

```text
GET /admin/daily/z-reports
→ 解析门店权威当前营业日与日结序列锚点
→ 按日期游标确定最多 limit 个连续营业日
→ 批量读取该日期窗口内快照
→ 合并 CLOSED/PENDING/REOPENED 状态
→ 标注唯一 can_close 行
→ 前端以 business_day 进入日结页
```

## Layer Coverage

| Layer | Classification | Reason |
|---|---|---|
| Production UI | VERIFIED_UNAFFECTED | 用户明确只修后端；不编辑前端仓库 |
| API response/pagination | AFFECTED | items 增加状态字段并纳入无快照日期；游标变为营业日不透明值 |
| Backend/domain | AFFECTED | 列表复用权威日结序列 |
| Persistence | AFFECTED | 查询由 CLOSED 快照页改为日期窗口内全部快照 |
| Security | VERIFIED_UNAFFECTED | 认证、门店解析及权限不变 |
| Database schema | VERIFIED_UNAFFECTED | 无迁移 |
| Tests/docs | AFFECTED | 服务测试与两份 API 文档更新 |
| External consumer | HANDOFF | 新字段及点击规则写入交接文档 |

## Contract Delta Summary

`items[]` 新增 `close_state/can_close/is_next_close_business_day`；缺失快照的营业日也成为列表项。`next_cursor` 改为 `yyyyMMdd` 数值型不透明日期游标。

## Risks

- 把首张快照前日期误列为待结会违反兼容启动规则；必须以下限锚点裁剪。
- 把全部 PENDING 行标为可操作会绕过严格时序；必须只标记最早待结日。
- 逐日查询会形成 N+1；必须一次批量查询后内存合并。

UNKNOWN count: 0

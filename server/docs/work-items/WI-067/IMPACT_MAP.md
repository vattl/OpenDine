# Impact Map — WI-067

## Authoritative Owner

- 日结时序与关账权限：`DailyCloseServiceImpl`。
- 营业窗口：`ShopBusinessWindowResolver`。
- 门店日结快照事实：`t_daily_close_snapshot` / `DailyCloseSnapshotMapper`。
- 移动端日结页面消费者：外部同项目仓库 `my_project_admin_panel/admin_mini`。

## Change Propagation Path

```text
老板进入门店日结
→ Flutter 页面不再按客户端时钟选日
→ GET /admin/daily/pre-check（不传 stat_date）
→ 后端计算 next_close_business_day
→ 页面以返回 stat_date 加载 summary/channel/gross-profit/Z preview
→ POST /admin/daily/settle（stat_date + precheck_token）
→ 事务内再次校验门店日结序列
→ 生成/重结唯一营业日快照
→ 下一次预检推进到下一营业日
→ 页面显示新的待结日期
```

## Consumer Coverage

| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| Flutter `DailySettlePage` | 日结中心主消费者 | AFFECTED | YES | 客户端 `_businessDate` 按本机时间计算并显式传参 |
| `CashierShiftRepository` | precheck/settle/Z API client | AFFECTED | YES | 需允许缺省预检日期并映射权威日期/顺序错误 |
| `BossRepository` | summary/channel/gross-profit | AFFECTED | YES | 改用 precheck 返回日期 |
| 旧 API 客户端 | 可继续显式传日期 | AFFECTED | CONDITIONAL | 跳日写请求新增 409；历史只读不变 |
| 历史 Z 报表列表 | 已结快照查询 | VERIFIED_UNAFFECTED | NO | `listZReports` 只读且显式范围 |
| 开店流程 | 辅助拦截 | AFFECTED | YES | 改为复用权威待结日，不能承担最终保证 |

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | VERIFIED_UNAFFECTED | 用户明确限定仅后端；本 Work Item 不编辑生产 UI |
| Interaction | AFFECTED | 旧客户端跳日写入由错误成功收紧为结构化 409 |
| Frontend State | VERIFIED_UNAFFECTED | 不在本 Work Item 修改；迁移要求写入 handoff |
| API Client | AFFECTED | 缺省 `stat_date` 与 409 顺序错误需消费者后续适配 |
| Request Contract | AFFECTED | 写入目标日必须等于权威待结日 |
| Backend/Domain | AFFECTED | 新增门店级日结序列解析与重开状态机 |
| Persistence | AFFECTED | 复用唯一快照行；无需新增表/破坏唯一键 |
| Response Contract | AFFECTED | 增加权威日期、当前营业日、积压与顺序字段 |
| Jobs/Events/Integrations | VERIFIED_UNAFFECTED | 无日结异步任务或外部事件变化 |
| Config/Security | AFFECTED | 权限不变；新增服务端强制校验，不能 force 绕过 |
| Runtime/NFR | AFFECTED | 每次预检/结算增加一次门店最新快照查询，需索引命中 |
| Tests | AFFECTED | 服务、控制器、Flutter widget/repository、并发和兼容测试 |

## Duplicate Logic / Patch Smells

- `DailyCloseServiceImpl` 与 `AdminDailyController` 各自实现日期解析，必须收敛到日结服务上下文。
- Flutter `_businessDate` 复制业务规则并硬编码 16:00，必须删除作为关账权威的用途。
- 开店流程自有“前一天是否日结”查询，只可复用统一策略，不能保留第二套时序定义。

## Contract Delta Summary

- `GET /admin/daily/pre-check` 缺省日期时返回最早待结日而不是当前活动营业日。
- precheck 响应增加 `current_business_day`、`next_close_business_day`、`pending_day_count`、`has_previous_unclosed_day`。
- `POST /admin/daily/settle` 对跳日返回 409 `DAILY_CLOSE_OUT_OF_SEQUENCE`，携带 expected/requested。
- 历史只读接口显式日期语义不变。

## UI Semantic Impact

本 Work Item 的生产范围为后端 API/领域约束，不编辑 UI。已生成的 HTML 原型仅作消费者参考，不作为本次生产实现门禁；前端适配通过 handoff 显式留待独立工作。

## Risks

- 没有历史快照的老门店若追溯全部订单会产生不可控补结量；采用当前营业日兼容启动。
- 补结时若水位继续取门店全局最大值，会被后续营业日交易扰动。
- 重开较早日期会造成已结序列中间空洞，必须禁止。
- 前端若未同步，虽然后端能拒绝跳日，但页面仍可能显示错误日期；因此需要显式消费者修改。

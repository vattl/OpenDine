# Implementation Design — WI-067

## Root Fix / Owner

在 `DailyCloseServiceImpl` 建立唯一的门店日结序列策略，并由所有关账写入口在事务内强制执行；Flutter 页面只消费服务端返回的权威待结日期。

## Why this location

日结顺序是财务领域不变量，不能由 UI、开店接口或调用者传参保证。服务层已拥有门店、快照、预检令牌和 SERIALIZABLE 关账事务，是唯一能覆盖全部调用路径的权威位置。

## End-to-End Change

### Backend

1. 新增内部 `resolveCloseSequence(shop)`：
   - 查询该门店截至当前营业日的全部快照，按 `business_day ASC` 构建序列（包含 CLOSED/REOPENED）。
   - 无快照：`next = operationalBusinessDay`，作为兼容启动锚点。
   - 有快照：以首张快照为兼容锚点，逐日寻找最早缺失或 `REOPENED` 日。
   - `pending_day_count` 统计锚点至当前日范围内实际缺失或 `REOPENED` 的天数；当前日已结且无缺口时为 0。
2. `precheck`：日期缺省选 next；显式日期晚于 next 返回结构化 `DAILY_CLOSE_OUT_OF_SEQUENCE` blocker，不签 token；早于 next 且不是该日现存 CLOSED 的写预检拒绝。
3. `settle`：在 SERIALIZABLE 事务中重新解析 next；目标不等于 next 时抛 409，`force` 不得绕过。
4. `voidStalePackTakeoutOrders` 复用同一目标日校验。
5. 活动钱箱按目标 `business_day` 过滤。
6. 预检/结算水位按目标营业窗口取最大 ID/成功数量，避免后续日数据扰动历史补结。
7. `generateZReport`：缺省日期使用 next；显式日期保持历史只读语义。
8. `summary/income/byChannel/grossProfit` 显式日期保持原义；页面从 precheck 取得权威日期再调用。

### Frontend

不在本 Work Item 修改。所需迁移已完整记录于 `API_CONSUMER_HANDOFF.md`；后端安全性不依赖消费者更新。

### UI / Interaction

不修改生产 UI。参考原型仅帮助消费者理解后续可见语义。

### Data / Persistence

- 保留 `uk_shop_business_day(shop_id,business_day)`。
- 重开只允许最新 CLOSED 快照；重结时更新同一 REOPENED 行为 CLOSED 并重新固化摘要，不插入第二行。
- 不新增迁移。若实现需要数据库级门店行锁，锁定现有 `t_shop` 行，不创建新锁表。

### Interfaces / Contracts

详见 `CONTRACT_DELTA.md`、`BACKEND_CAPABILITY_REQUEST.md` 与 `API_CONSUMER_HANDOFF.md`。

### Jobs / Events / Integrations

无。

## Preserve / Compatibility

- 历史显式只读查询不被 next 日期重定向。
- 旧客户端对正确 next 日期的调用保持成功。
- 跳日写调用从错误成功收紧为 409，是有意的安全兼容变化。
- 预检 token 继续绑定门店、操作员、营业日及财务水位。

## API Consumer Migration / Handoff

Flutter 同项目仓库必须移除本地 `_businessDate` 的权威角色。详见 `API_CONSUMER_HANDOFF.md`。

## Failure / Boundary Behavior

- 多日漏结：逐日推进。
- 零销售日：允许零值预检/快照，但仍必须显式完成。
- 当前日已结：返回 `is_already_settled=true`，不制造未来日期。
- 非最新日重开：409 `DAILY_REOPEN_OUT_OF_SEQUENCE`。
- 并发结算不同日期：SERIALIZABLE 事务内重新解析序列，非权威日期在任何财务写入前失败。
- 日期格式错误沿用既有全局异常处理，不在本 Work Item 扩展。

## Runtime / Performance / Reliability

- 序列查询使用现有 `(shop_id,business_day)` 唯一索引并按营业日排序；按天扫描仅覆盖门店已有日结锚点至当前日。
- 关账继续使用数据库 SERIALIZABLE 隔离并在事务内二次解析序列，避免跨日期并发写入穿透。
- 窗口水位查询需使用现有 shop/time 或 shop/business_day 索引，不进行全表扫描。

## Security / Permissions

权限与二次授权保持；`force` 仅覆盖软警告，不能覆盖顺序、门店或资金一致性硬约束。

## UI Design Track

NOT_APPLICABLE：用户明确将实现范围限制为后端；`ui/` 仅保留为非生产参考。

## Vertical Slice Plan

1. RED：增加服务测试，证明旧代码会选择今天并允许跳过昨天。
2. GREEN：实现只读 close context 与 precheck 顺序行为。
3. RED/GREEN：settle 事务内顺序锁、窗口水位及目标日钱箱过滤。
4. RED/GREEN：最新日重开与同一快照重结。
5. 契约/交接：OpenAPI、API.md、前端消费者 handoff。
6. 全量 Maven 验证、审查、接受门禁。

## Verification Strategy

- Java 小型单元测试覆盖日期策略、blocker/error payload 和重开规则。
- 服务集成式测试覆盖 precheck→settle→next、零销售、多日积压与并发。
- 不运行或修改 Flutter；前端端到端状态保留在 handoff 中。
- 运行完整 Maven tests 与 `mvnw.cmd clean package -DskipTests`。

## Rollback / Recovery

- 代码回滚不涉及模式回滚。
- 上线前执行只读日期断层审计；若发现已存在跳日快照，先出修复清单，不自动改写财务快照。

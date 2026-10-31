# SaaS 跨天营业日报执行方案

最后更新：2026-10-02
工作流：`WS004 / change/C012-cross-day-business-report`
状态：`VERIFIED_DONE`（已合并并完成最终 JAR 构建，待迁移/部署）

## 1. 目标与硬约束

- 不新增 HTTP 接口，复用现有 `/admin/report/daily`、`/weekly`、`/monthly`、日报导出及日结接口。
- 前端只选择并传递营业日，不计算 `startTime`、`endTime`，不根据切日时间自行加减日期。
- 门店 `settle_time` 是营业日分界点；营业日 `D` 固定对应 `[D settle_time, D+1 settle_time)`。
- 查询必须左闭右开，禁止 `BETWEEN` 和 `<= endTime`。
- 单店查询必须使用鉴权解析出的 `shop_id` 和该门店的 `settle_time`，禁止串店。
- API 语义修改必须同步 `docs/openapi.yaml`、`docs/API.md`，并生成完整 JAR。

## 2. 当前已确认缺口

1. `ShopBusinessWindowResolver` 的实际显式日期窗口为 `[D,D+1)`，但类注释、部分接口文档仍存在 `[D-1,D)` 描述。
2. 统一窗口解析器使用 `ZoneId.systemDefault()`，结果受部署主机时区影响。
3. `/admin/report/daily`、周报、月报先加载全部订单再在 JVM 汇总，数据规模增大后性能不稳定。
4. 在线日报按 `pay_time`，导出聚合按 `order_time`，业务口径不一致。
5. 导出聚合使用 `order_time <= endTime`，切日点订单可能被相邻营业日重复统计。
6. 周/月导出使用自然日 `00:00:00` 至 `23:59:59`，没有应用门店 `settle_time`。
7. HQ 无门店上下文时，部分逻辑读取第一家门店的切日时间却可能汇总全部门店。
8. 收银端部分报表页面仍描述“切日前 12 小时”，与完整 24 小时营业日冲突。

## 3. 目标业务规则

### 3.1 日期语义

```text
营业日 D：
start = D settle_time（含）
end   = D+1 settle_time（不含）
```

示例：`settle_time=04:00`，选择 `2026-10-02`：

```text
[2026-10-02 04:00:00, 2026-10-03 04:00:00)
```

### 3.2 财务归属时间

- 正常成功订单按 `pay_time` 归属营业日。
- 仅为兼容历史异常数据，在 `pay_time IS NULL` 时回退 `order_time`。
- 金额计算沿用现有净收入公式，不在本任务引入新财务字段。

### 3.3 多门店

- 单店报表：必须有授权门店上下文，使用该门店切日时间。
- 总部跨店汇总：每店按自己的切日窗口聚合后求和，不能使用第一家门店窗口覆盖全部门店。
- 本轮先保证现有单店接口正确；跨店汇总仅在现有调用确实存在时复用当前接口实现，不设计新接口。

## 4. 执行切片

### S1 — 固化窗口契约与时区

状态：`COMPLETED`

- 为显式营业日、区间、切日边界和非系统默认时区补充回归测试。
- 将统一解析器固定为 `Asia/Shanghai`。
- 修正文档和代码注释中的 `[D-1,D)` 冲突，不改变现有 endpoint。
- 验证：`ShopBusinessWindowResolverTest`。

### S2 — 数据库聚合替代 JVM 全量汇总

状态：`COMPLETED`

- 扩展 `ReportOrderAggregate`，使用 `BigDecimal` 返回单行聚合。
- 查询条件统一为门店、商户、成功状态、接单状态和财务时间窗口。
- 使用 `pay_time`；仅 `pay_time IS NULL` 回退 `order_time`。
- 修复结束边界为 `< endTime`。
- 验证：H2/JdbcTemplate 聚合测试，覆盖边界、空支付时间、门店隔离。

### S3 — 复用现有日报/周报/月报接口

状态：`COMPLETED`

- `/admin/report/daily` 接收的 `date` 明确定义为营业日起始日期。
- `/weekly` 的 `[startDate,endDate]` 解析为 `[startDate settle, endDate+1 settle)`。
- `/monthly` 使用该月营业日起始日期范围。
- 控制器改为调用数据库聚合，不加载完整订单列表。
- 保留现有响应字段兼容，不新增 endpoint。
- 验证：控制器定向测试及门店授权范围测试。

### S4 — 日结与导出口径统一

状态：`COMPLETED`

- 日报导出逐日调用同一营业窗口与聚合逻辑。
- 周/月导出删除自然日字符串拼接。
- 日结预览、收入、毛利与日报使用一致的窗口解析。
- 已日结快照继续优先返回，避免历史结果随配置变化而漂移。
- 验证：在线日报、日结预览、导出结果对账测试。

### S5 — 收银端只传营业日

状态：`COMPLETED`

- 移动营业报表继续复用 `reportDailyEndpoint`、`reportWeeklyEndpoint`、`reportMonthlyEndpoint`。
- 将 `_anchor` 语义收敛为选中的营业日；请求只传日期/营业日期范围。
- 默认营业日从现有 dashboard 的 `businessDay.businessDayDate` 获取，客户端不根据 `settle_time` 推算。
- 删除报表设置页“切日前 12 小时”等过期文案与报表时间推算。
- 门店切换后使用 `shopId + period + businessDate` 隔离状态，旧请求不得覆盖新门店结果。
- 验证：repository/widget 测试，断言请求不存在 `startTime/endTime/settleTime`。

### S6 — 性能、文档与发布验证

状态：`COMPLETED`

- 核实 `(shop_id, pay_time)` 与 `(shop_id, order_time)` 索引；只在生产 schema 缺失时增加幂等迁移。
- 使用真实 MySQL `EXPLAIN` 验证范围索引计划（如环境可用）。
- 同步 `docs/openapi.yaml`、`docs/API.md`、必要的 `docs/DATABASE.md`。
- 执行后端定向测试、完整 Maven 测试、`mvn clean package -DskipTests`。
- 执行 Flutter analyze、定向测试和 Windows 构建。
- 执行 `.ai/scripts/validate.py --release`。

## 5. 验证结果与需求追踪

| 原始要求 | 落地证据 | 验证结果 |
| --- | --- | --- |
| 不新增接口，复用现有日报接口 | `/admin/report/daily`、`/weekly`、`/monthly` 路径与响应字段保持不变 | 控制器定向测试 4 项通过；OpenAPI 可解析 |
| 营业日按门店 `settle_time` | `ShopBusinessWindowResolver` 固定 `Asia/Shanghai`，显式 D 为 `[D,D+1)` | 解析器测试 7 项通过，含 JVM 默认 UTC 场景 |
| 前端只传营业日 | `business_report_query.dart` 仅生成 date/startDate/endDate/year/month | Flutter 定向测试 3 项、定向 analyze 0 问题 |
| 财务时间与右开边界 | 聚合优先 `pay_time`，NULL 才回退 `order_time`，结束条件 `< end` | H2 聚合测试 3 项通过，覆盖切日点、历史回退和门店隔离 |
| 多店不共用第一家切日时间 | 总部逐店使用各自窗口再求和 | 控制器测试覆盖 02:00/05:00 两店，结果正确 |
| 性能避免加载完整订单 | 控制器调用数据库单行 `COUNT/SUM`，新增 `(shop_id,pay_time)` 索引迁移 | 全量 Maven 测试 1027 项：0 失败、5 跳过 |
| 在线与导出一致 | 日/周/月导出均复用营业窗口和统一聚合 | `ReportLogServiceTest` 与日结窗口测试通过 |
| 可发布构建 | 后端 JAR、收银 Windows Release | 两项构建成功，哈希见执行游标 |

限制：本地没有受控生产 MySQL 数据集与连接，因此没有宣称完成真实生产数据分布下的
`EXPLAIN`。上线前须执行迁移并核验 `idx_order_shop_pay_time` / `idx_order_shop_time` 的实际计划。

## 6. 关键代码范围

### 后端

- `src/main/java/com/lanf/util/ShopBusinessWindowResolver.java`
- `src/main/java/com/lanf/controller/admin/AdminReportController.java`
- `src/main/java/com/lanf/controller/admin/AdminDailyController.java`
- `src/main/java/com/lanf/report/service/ReportOrderAggregate.java`
- `src/main/java/com/lanf/report/service/ReportExportService.java`
- `src/test/java/com/lanf/util/ShopBusinessWindowResolverTest.java`
- `src/test/java/com/lanf/report/ReportOrderAggregateTest.java`
- `docs/openapi.yaml`
- `docs/API.md`

### 收银端

- `admin_panel_flutter/lib/src/features/mobile/presentation/boss_reports_page.dart`
- `admin_panel_flutter/lib/src/features/cashier_settings/presentation/cashier_settings_report_page.dart`
- 对应 repository/widget 测试

## 7. 验收矩阵

- `settle_time`：`00:00`、`02:30`、`04:00`、`23:59`。
- 边界：开始前 1ms、开始时刻、结束前 1ms、结束时刻。
- 日期：月末、年末、闰年二月。
- SaaS：两个门店不同切日时间，同一绝对时间归属结果正确且不串店。
- 一致性：日报 = 日结预览 = 同日导出；周报 = 对应每日结果之和。
- 客户端：请求只包含营业日参数，无时间窗口计算。
- 性能：查询按门店和时间范围聚合，不读取完整订单实体列表。

## 8. 中断恢复

恢复时按以下顺序检查：

1. `docs/EXECUTION_CURSOR.md`
2. `workstreams/WS004-cross-day-business-report/STATE.md`
3. 本文档各切片状态
4. `git status` 与当前分支差异
5. 最近一次已执行测试结果


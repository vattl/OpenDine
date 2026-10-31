# D008 营业日分桶统一为 settle\_time 截止口径



* 日期：2026-09-07

* 状态：IMPLEMENTED（编译通过、回归测试通过、SQL 实机验证通过）

* 涉及文件：见各 Diff 段

* 风险等级：STRUCTURAL（跨 analytics/order/report/kds 四模块的营业日口径统一）

* 关联：C007（营业日窗口模型 ShopBusinessWindowResolver）；`/bug` 需求 "营业日分桶未按 settle\_time 截止，落地修复并将其他接口对齐"



***

## 1. SYMPTOM（用户报告的现象）

`GET /admin/analytics/business/trend` 的 `business_day.series` 分桶与日结（`AdminDailyController.businessWindow`）、营收报表不一致：



* 门店配置 `settle_time=04:00`（默认）时恰好一致，纯属巧合（默认 04:00 = 硬编码值）；

* 门店把 `settle_time` 改为 02:00 / 06:00 等自定义值时，trend 的营业日分桶**完全不生效**：仍按固定 `open_time`（默认 16:00）单边划分；

* 凌晨关门时段（如 15:59 前、非营业时段）的订单被错误归入桶。

## 2. REPRODUCTION（复现路径）



1. 门店 A 设置 `t_shop.settle_time='06:00'`（open\_time='16:00'）。

2. 查询 `GET /admin/analytics/business/trend?granularity=day&startTime=...&endTime=...`。

3. 观察 `business_day.series`：09-02 02:00 的订单被分到 09-02 桶（应为 09-01 桶），因为 `AnalyticsMapper.businessDateOfOrder` 只判断 `TIME(order_time) >= '16:00'`，无 settle 边界。

4. 对照 `AdminDailyController` /admin/daily/businessWindow 与 OrderMapper 营收统计：均按 `settle_time` 截止，口径不一致坐实。

## 3. ROOT CAUSE（根因）

统一口径模型（`ShopBusinessWindowResolver.windowFor`）：

> 营业日 D = [ D 的 
>
> `open_time`
>
> , D+1 的 
>
> `settle_time`
>
>  )，
>
> `settle_time`
>
>  为空回退 
>
> `close_time`
>
> ，再空回退 04:00；
>
> `open_time`
>
>  为空回退 16:00。

已遵循该模型的实现：



* `AdminDailyController.businessWindow`（日结，order\_time ∈ \[win \[0], win \[1])）

* `OrderMapper.getSalesVolumeByEveningPeriod`（settleTime 截止 + 关门时段排除）

* `OrderMapper.countByTimeRange`（由 `IOrderServiceImpl.getTodayOrderCount` 用 `resolveWindow` 算好窗口再传入）

* `CashierOrderController.today`（`resolveWindow`）

**未遵循该模型、仍是硬编码 / 单边判断的实现**（本次修复对象）：



| # | 位置                                                                       | 问题                                                                   |
| - | ------------------------------------------------------------------------ | -------------------------------------------------------------------- |
| 1 | `AnalyticsMapper.xml` `businessDateOfOrder`（27-32 行）                     | 仅 `TIME(order_time)>=#{openTime}` 单边归当天 / 前一天，无 settle\_time、无关门时段过滤 |
| 2 | `AnalyticsMapper.xml` `selectNewDishSalesTrendByBusinessDate`（289-322 行） | 内联同款单边 CASE（298-301 行）                                               |
| 3 | `AnalyticsServiceImpl.resolveOpenTime`（339-348 行）                        | 只解析 `open_time`，不解析 `settle_time`（默认 "04:00" 丢失）                     |
| 4 | `OrderMapper.xml` `currentBusinessDayBoundsRow`（38-43 行）                 | 硬编码 `16:00`/`04:00`，不感知门店配置                                          |
| 5 | `AdminReportController.businessDayRange()`（714 行）                        | 静态硬编码 16:00/04:00                                                    |
| 6 | `ReportExportService.businessDays()`（275-285 行）                          | 硬编码 16:00/04:00 逐日窗口                                                 |
| 7 | `KdsWorkflowService.businessDayStart()`（351-361 行）                       | 硬编码 16:00 起点（凌晨 0-4 归属前一营业日）                                         |

## 4. TARGET（目标口径，用户拍板）

> 用户原话："settle_time 作为截止时间，比如我设置的是 4:00，那么 opentime 就是 D16:00，end 就是 D+1 4:00，接口也可以自定义时间区间来获取历史数据。"

统一后，所有 "营业日" 概念（统计分桶 / 日结 / 当前营业日 / 报表导出 / KDS 工单起点）一律：



* 起点：D 的 `open_time`（门店配置，空回退 16:00）

* 截止：D+1 的 `settle_time`（门店配置，空回退 `close_time`，再空回退 04:00），**左闭右开**

* 关门时段（既不满足 `TIME >= open_time` 也不满足 `TIME < settle_time`）：**不属于任何营业日，从分桶中排除**

分桶归属（单条订单）：



```
TIME(order\_time) >= open\_time          → 归属 DATE(order\_time)（当天）

TIME(order\_time) <  settle\_time        → 归属 DATE(order\_time) - 1（次日凌晨）

否则（关门时段）                        → 不归属（NULL，配合 WHERE 排除）
```

## 5. MINIMAL BEHAVIOR DIFF（行为差异）

分桶规则对照（open=16:00 固定；settle 视门店配置）：



| 订单时刻              | 修复前（单边 TIME>=open）    | 修复后（三态 + 关门过滤）                      | 差异     |
| ----------------- | --------------------- | ----------------------------------- | ------ |
| 默认 settle=04:00   |                       |                                     |        |
| 09-01 17:00       | 09-01                 | 09-01（>=16:00 → 当天）                 | 无      |
| 09-02 03:00       | 09-01                 | 09-01（<04:00 → 前一天）                 | 无      |
| 09-01 15:00（关门时段） | 08-31（错误纳入）           | **排除**（15:00 既不 >=16:00 也不 < 04:00） | **修复** |
| settle=06:00      |                       |                                     |        |
| 09-02 05:00       | 09-01（<16:00 归前一天，巧合） | 09-01（<06:00 → 前一天）                 | 无      |
| 09-02 06:30（关门时段） | 09-01（错误纳入）           | **排除**（06:30 已过 06:00 截止）           | **修复** |
| settle=02:00      |                       |                                     |        |
| 09-02 01:00       | 09-01                 | 09-01（<02:00 → 前一天）                 | 无      |
| 09-02 03:00（关门时段） | 09-01（错误纳入）           | **排除**（03:00 已过 02:00 截止且未到 16:00）  | **修复** |

**结论**：默认配置（16:00/04:00）下，营业时段内的订单分桶结果与修复前完全一致；**行为差异集中于两点：① 自定义&#x20;**`settle_time`**&#x20;真正生效（凌晨截止边界正确）；② 关门时段订单不再污染营业日分桶。**

补充注意：`OrderMapper.getSalesVolumeByEveningPeriod` 以 `pay_time` 为基准、Analytics 以 `order_time` 为基准 —— 这是既有字段口径差异（营收统计 vs 经营分析），本次**不改基准字段**，只统一 "营业日窗口边界" 口径；基准字段差异在 §8 交付说明中明示。

## 6. FIX（逐文件 Diff）

### 6.1 `AnalyticsMapper.xml`

**(a)&#x20;**`businessDateOfOrder`**（27-32 行）改为三态 CASE：**



```
\<!-- 营业日标签：统一口径（与 ShopBusinessWindowResolver 一致）：营业日 D = \[D 的 open\_time, D+1 的 settle\_time)，

&#x20;    settle\_time 空回退 close\_time / 04:00，open\_time 空回退 16:00。

&#x20;    order\_time >= open\_time → 当天；order\_time < settle\_time（次日凌晨）→ 前一天；其余（关门时段）→ NULL，

&#x20;    必须配合 businessDayFilter 排除 NULL 桶。 -->

\<sql id="businessDateOfOrder">

&#x20;   (CASE

&#x20;       WHEN TIME(o.order\_time) \&gt;= #{openTime} THEN DATE(o.order\_time)

&#x20;       WHEN TIME(o.order\_time) \&lt; #{settleTime} THEN DATE\_SUB(DATE(o.order\_time), INTERVAL 1 DAY)

&#x20;       ELSE NULL

&#x20;   END)

\</sql>
```

**(b) 新增&#x20;**`businessDayFilter`**（紧随其后）：**



```
\<!-- 关门时段过滤：不属于任何营业日的订单（TIME 在 \[settle\_time, open\_time) 墙钟区间）一律排除，

&#x20;    与 getSalesVolumeByEveningPeriod 的 (TIME(pay\_time)>=openTime OR TIME(pay\_time)\<settleTime) 同构。 -->

\<sql id="businessDayFilter">

&#x20;   AND (TIME(o.order\_time) \&gt;= #{openTime} OR TIME(o.order\_time) \&lt; #{settleTime})

\</sql>
```

**(c)&#x20;**`selectBusinessTrendByBusinessDate`**（166-203 行）**：内层 y 的 WHERE 末尾（`shopFilter` 之后）追加 `<include refid="businessDayFilter"/>`。

**(d)&#x20;**`selectDistinctBusinessDayCount`**（205-215 行）**：内层 x 的 WHERE 末尾追加 `<include refid="businessDayFilter"/>`（COUNT (DISTINCT bd) 天然忽略 NULL，追加过滤是为语义一致与 NULL 桶防御）。

**(e)&#x20;**`selectNewDishSalesTrendByBusinessDate`**（289-322 行）**：内层 t 的 `(CASE ...) AS bd` 替换为 `<include refid="businessDateOfOrder"/> AS bd`；WHERE 末尾追加 `<include refid="businessDayFilter"/>`。

**(f)&#x20;**`selectTimeSlotRevenueBusinessAnchor`**（86-107 行）**：**保持 SQL 不变**（墙钟四段固定分档 \[16,22)/\[22,24)∪\[0,4)/\[4,10)/\[10,16) 是产品固定定义，与营业日窗口解耦）；仅更新 Javadoc 措辞（见 6.3）。

### 6.2 `AnalyticsMapper.java`



* `selectBusinessTrendByBusinessDate`、`selectDistinctBusinessDayCount`、`selectNewDishSalesTrendByBusinessDate` 三个方法签名追加 `@Param("settleTime") String settleTime`。

* Javadoc：`selectBusinessTrendByBusinessDate` 的 "按营业日标签（16:00 为界）分桶" 改为 "按营业日标签（open\_time 起点 /settle\_time 截止）分桶"；`selectTimeSlotRevenueBusinessAnchor` Javadoc 标注 "固定墙钟分档，与门店营业日窗口（settle\_time 口径）解耦"。

### 6.3 `AnalyticsServiceImpl.java`



* 新增 `resolveSettleTime(Integer shopId)`：`shop.settle_time`（非空）→ `shop.close_time`（非空）→ `"04:00"`，与 `IOrderServiceImpl` 既有解析一致。

* `businessTrend` / `businessOverview` / `dishAnalysis` 三处调用 `selectBusinessTrendByBusinessDate` / `selectDistinctBusinessDayCount` / `selectNewDishSalesTrendByBusinessDate` 时追加 `settleTime` 参数。

* 类注释 "营业日（16:00～次日 04:00 标签）" 改为 "营业日（open\_time 起点 /settle\_time 截止，空值回退默认）"。

### 6.4 `OrderMapper.xml` + `OrderMapper.java` + `IOrderServiceImpl.java`

**(a)&#x20;**`currentBusinessDayBoundsRow`**（38-43 行）参数化：**



```
\<!-- 当前营业日窗口：D = \[D 的 open\_time, D+1 的 settle\_time)（settle\_time 由 service 按 settle>close>04:00 解析）。

&#x20;    openTime/settleTime 为 'HH:mm'；跨夜（settle<=open）时结束顺延到 D+1。 -->

\<sql id="currentBusinessDayBoundsRow">

&#x20;   SELECT

&#x20;       CASE WHEN CURTIME() \&gt;= #{openTime} THEN CURDATE() ELSE DATE\_SUB(CURDATE(), INTERVAL 1 DAY) END AS target\_date,

&#x20;       CONCAT(CASE WHEN CURTIME() \&gt;= #{openTime} THEN CURDATE() ELSE DATE\_SUB(CURDATE(), INTERVAL 1 DAY) END, ' ', #{openTime}) AS start\_time,

&#x20;       CASE WHEN CURTIME() \&gt;= #{openTime} OR CURTIME() \&lt; #{settleTime} THEN NOW()

&#x20;            ELSE CONCAT(DATE\_ADD(CASE WHEN CURTIME() \&gt;= #{openTime} THEN CURDATE() ELSE DATE\_SUB(CURDATE(), INTERVAL 1 DAY) END, INTERVAL 1 DAY), ' ', #{settleTime})

&#x20;       END AS end\_time

\</sql>
```

> 边界验证：CURTIME ()='16:00:00' 与 #{openTime}='16:00' 字符串比较：'16:00:00'>='16:00' → true（16:00:00 整点属于新营业日，左闭 ✓）；CURTIME ()='04:00:00' 与 #{settleTime}='04:00'：'04:00:00'>='04:00' → true → end=NOW () ✓（04:00 整点已在 D 营业日内，因窗口右开于 04:00，04:00:00 整点实际属于 D 之后，但结算时刻为 NOW ()，语义为 "当前已结算部分"，与修复前一致）。

**(b)&#x20;**`OrderMapper.java`：`listRevenueByPaymentMethodCurrentBusinessDay`、`aggregateCurrentBusinessDayPaidOrderMetrics` 签名追加 `@Param("openTime") String openTime, @Param("settleTime") String settleTime`。

**(c)&#x20;**`IOrderServiceImpl.java`：



* 提取私有 `resolveOpenTime(shopId)` / `resolveSettleTime(shopId)`（复用既有解析逻辑，消除 `getSalesVolumeByEveningPeriod` 两处内联重复）。

* `listRevenueByPaymentMethodCurrentBusinessDay(shopId)` / `aggregateCurrentBusinessDayPaidOrderMetrics(shopId)` 调用 mapper 时传入解析结果。

### 6.5 `AdminReportController.java`

`businessDayRange()` 由 `private static` 改为 `private`（实例方法），内部：



```
Shop shop = resolveReportShop();

LocalDate day = ShopBusinessWindowResolver.businessDayFor(shop, LocalDate.now());

return ShopBusinessWindowResolver.windowFor(shop, day);
```

调用处（501 行 dashboard）不变。`resolveReportShop()` 返回 null 时 windowFor 走默认 16:00/04:00，行为与修复前一致。

### 6.6 `ReportExportService.java`



* 注入 `IShopService`。

* `buildDailyRows`：解析 `Shop shop = shopId != null ? shopService.getById(shopId) : null;` 并传给 `businessDays`。

* `businessDays(LocalDate start, LocalDate end)` → `businessDays(Shop shop, LocalDate start, LocalDate end)`（仍 static），循环内用 `ShopBusinessWindowResolver.windowFor(shop, d)` 取 \[start,end) 格式化。

* 类注释 /businessDays 注释更新为 settle\_time 口径。

### 6.7 `KdsWorkflowService.java`



* 注入 `IShopService`（+ import Shop / IShopService / ShopBusinessWindowResolver / LocalDate / ZoneId）。

* `businessDayStart()` → `businessDayStart(int shopId)`（实例方法）：



```
private Date businessDayStart(int shopId) {

&#x20;   Shop shop = shopId > 0 ? shopService.getById(shopId) : null;

&#x20;   LocalDate day = ShopBusinessWindowResolver.businessDayFor(shop, LocalDate.now());

&#x20;   return ShopBusinessWindowResolver.windowFor(shop, day)\[0];

}
```



* 调用处（`archivedHistory` 257 行）改 `businessDayStart(shopId)`；239 行注释更新。

* 说明：KDS 工单只取营业日**起点**（无截止概念），起点口径与营业日模型对齐。

### 6.8 `CashierOrderController.java` + `OrderBusinessDayRangeResolver.java`



* `CashierOrderController`：删除未使用的 `import com.lanf.util.OrderBusinessDayRangeResolver;`（死 import）。

* `OrderBusinessDayRangeResolver`：保留类与既有测试（`OrderBusinessDayRangeResolverTest`），类级 `@Deprecated` + Javadoc 指向 `ShopBusinessWindowResolver`，不再新增使用方。

### 6.9 纯注释同步（无行为变化）



* `AdminDailyController` 类注释：`open_time/close_time` → `open_time/settle_time`。

* `AdminAnalyticsController` Javadoc（"16:00 为界" 类措辞）→ settle\_time 口径。

* `OrderMapper.xml`：`countByTimeRange`（88 行）、`getSalesVolumeByEveningPeriod`（103-104 行）、`listRevenueByPaymentMethodCurrentBusinessDay`（199 行）、`aggregateCurrentBusinessDayPaidOrderMetrics`（221 行）注释更新。

## 7. REGRESSION（回归验证，2026-09-07 实测）



1. 编译：`.\mvnw.cmd compile` **通过**（exit 0）。

2. 全量测试 `.\mvnw.cmd test`：**基线（HEAD，stash 后）即存在测试编译失败**——`PersonalPaymentWebhookServiceTest`、`PersonalAlipayWebhookControllerTest`（processPayment 签名漂移）、`CashierOrderControllerTest`（today 签名漂移，期望 2 参、源码 3 参），均为仓库既有问题，与本次改动无关。

3. 排除上述 3 个基线编译失败类后运行 714 个测试：仅剩 `PersonalPaymentReverseMatchTest`（支付，基线）、`KdsReplicationContractTest`（openapi.yaml 解析，基线，与本次无 API 变更）2 失败 2 错误；**本次改动相关测试全部通过**（含 `ShopBusinessWindowResolverTest`、`OrderBusinessDayRangeResolverTest`、`ReportLogServiceTest` 14/14—— 后者因本次新增 `shopService` 依赖已补 mock 修复）。

4. SQL 实机验证（debug 库 127.0.0.1:3307）：三态 CASE + 关门过滤 6 场景全部符合预期：

* 默认 settle=04:00：03:00 凌晨→前一天桶 ✓；17:00→当天桶 ✓；15:00 关门→NULL 排除 ✓

* settle=06:00：05:00→前一天桶 ✓；06:30 关门→排除 ✓

* settle=02:00：03:00 关门→排除 ✓

1. 口径自洽性：`businessDateOfOrder` 三态 + `businessDayFilter` 与 `getSalesVolumeByEveningPeriod` 的 `(TIME>=open OR TIME<settle)` 逻辑一致（后者已按 settle\_time 实现，本次未改其基准字段 pay\_time）。

## 8. 交付说明



* 覆盖范围：Analytics 营业日分桶（trend/businessOverview/dishes）、OrderMapper 当前营业日（日结 / 看板渠道实收）、报表导出 daily、KDS 工单起点、注释与死代码清理。

* 未覆盖 / 明示差异：


  * `OrderMapper.getSalesVolumeByEveningPeriod` 基准字段为 `pay_time`，Analytics 为 `order_time`—— 本次不改基准字段（既有设计，交付说明明示）。

  * `selectTimeSlotRevenueBusinessAnchor` 墙钟四段固定分档（产品定义）不随 settle\_time 变化，仅文档措辞澄清。

  * `OrderBusinessDayRangeResolver` 保留（有测试引用），仅废弃标记，不删除。

* 行为差异集中在：自定义 settle\_time 生效 + 关门时段订单不再污染营业日桶；默认配置（16:00/04:00）下非关门时段结果与修复前一致。
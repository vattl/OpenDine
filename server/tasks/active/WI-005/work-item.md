# WORK ITEM — WI-005

## Request

数据报表的所有接口start和end的时间不需要传时分秒，只需要传年月日即可，除了自定义时间可以传时分秒，像今日，昨日，近七天和近30天这种就不需要传时分秒，后端会根据营业日截止时间自动补全

## Type

FEATURE / ENHANCEMENT / BACKEND

## State

DONE

## Requirement Contract

### Goal

1. 数据报表与数据分析相关接口在接收 `start` / `startTime` / `startDate` 与 `end` / `endTime` / `endDate` 参数时，支持仅传入年月日格式（`yyyy-MM-dd`），无需强制携带时分秒。
2. 当传入仅包含年月日的日期（如快捷档位：今日、昨日、近七天、近30天等）时，后端自动依据当前门店的营业日截止时间（`settle_time`，未配置默认 `04:00`）补全为完整的营业日窗口：
   - 起始时间补全为：`startDate` 的 `settle_time`（例如 `startDate 04:00:00`）；
   - 截止时间补全为：`endDate + 1日` 的 `settle_time`（例如 `endDate+1 04:00:00`）。
3. 当客户端传入自定义时间且携带有时分秒（例如 `yyyy-MM-dd HH:mm:ss` 或 `yyyy-MM-dd HH:mm`）时，后端尊重客户端传入的具体时分秒，不进行营业日强制覆盖。
4. 统一处理参数别名兼容性（`startTime` / `startDate` / `start` 以及 `endTime` / `endDate` / `end` 以及 `date`），覆盖 `AdminReportController`、`AdminAnalyticsController` 与 `AdminOrderController` 销售统计接口。

### Current behavior

- 部分接口（如 `AdminAnalyticsController.validateRange`、`AdminOrderController.statisticsDishSales`）严格校验格式包含时分秒（`400: startTime 与 endTime 必填，格式 yyyy-MM-dd HH:mm:ss`）。
- 若前端仅传纯日期字符串（`yyyy-MM-dd`），直接在数据库中以自然日 `00:00:00` 比较，导致截断或查询结果为空，未能按门店营业班次对齐。
- 部分报表接口使用 `LocalDate.parse`，若传入带时分秒字符串则直接抛出 `DateTimeParseException`。

### Target behavior

- 统一通过时间窗口解析器识别纯日期与带时分秒的时间串：
  - 纯日期（长度 10 且符合 `yyyy-MM-dd`）：根据当前门店的 `settle_time`，计算出 `[startDate settle_time, endDate+1 settle_time)` 的标准营业日时间窗口；
  - 自定义时分秒（长度 > 10，包含时间部分）：规范化空格并精确保留传入的时分秒；
  - 单日期查询（如 `date`）：同理转化为该单日的营业班次 `[date settle_time, date+1 settle_time)`。
- 覆盖所有报表分析端点：
  - `/admin/report/daily`
  - `/admin/report/weekly`
  - `/admin/report/monthly`
  - `/admin/report/dishRanking`
  - `/admin/report/cashierPerformance`
  - `/admin/report/shopProfit`
  - `/admin/report/compare`
  - `/admin/report/repurchase/weekly`
  - `/admin/report/repurchase/newCustomer`
  - `/admin/report/dashboard`
  - `/admin/analytics/business`
  - `/admin/analytics/business/trend`
  - `/admin/analytics/dishes`
  - `/admin/analytics/customers`
  - `/admin/analytics/members`
  - `/admin/analytics/marketing`
  - `/admin/order/statisticsCategorySales`
  - `/admin/order/statisticsDishSales`
  - `/admin/reports/exports`

### Acceptance criteria

- [x] 提供统一报表时间解析方法，支持纯日期自动按门店 `settle_time` 补全营业日窗口（`[start settle, (end+1) settle)`）。
- [x] 针对自定义时间（带 `HH:mm:ss` / `HH:mm`），保留客户端指定时分秒。
- [x] `AdminReportController` 所有接口支持纯年月日传参并自动按营业日补全。
- [x] `AdminAnalyticsController` 所有接口支持纯年月日传参并自动按营业日补全。
- [x] `AdminOrderController` 销售统计接口解除纯年月日 400 拦截并正确按营业日窗口查询。
- [x] 单元测试覆盖快捷纯日期、跨天多日纯日期、自定义带时分秒、格式校验等场景。
- [x] `docs/openapi.yaml`、`docs/API.md` 同步更新。
- [x] Maven 全量编译打包成功（`mvn clean package -DskipTests`）。

## Verification Evidence

- `AdminAnalyticsAndOrderReportTimeTest`：5/5 通过（报表/分析控制器纯年月日与自定义时分秒窗口）。
- `ShopBusinessWindowResolverReportTest`：7/7 通过（营业日窗口补全边界：settle_time 配置/默认、跨天、左闭右开）。
- 相关回归（Order/Shift/DailyClose/Drawer/MemberRecharge）：45/45 通过。
- 全量打包 `mvn clean package -DskipTests` BUILD SUCCESS（2026-10-09）。

## Acceptance Decision

ACCEPTED（2026-10-09）：验收标准 8/8 满足；集成/发布另行执行。

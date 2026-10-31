# BUG007: 收银端数据报表接口与时间窗口算法标准化整改

## 1. 缺陷概述
- **缺陷标识**：BUG007
- **所属模块**：数据报表 (`/admin/report/*`)、收银端流水与交班 (`/cashier/*`)、日结对账 (`/admin/daily/*`)
- **发现日期**：2026-10-01
- **严重级别**：P0 / 致命（影响全店财务指标、交接班对账及跨日订单可见性）

---

## 2. 缺陷根因分析

1. **营业日（Business Day）与结算截止点（Cut-off Point）概念混淆**：
   - 既有 `ShopBusinessWindowResolver` 将用户传入的日期 `D` 判定为“结算周期的结束日”，计算出的窗口为 `[D-1 settle_time, D settle_time)`。
   - 导致查询 `2026-10-01` 日报实际统计 `2026-09-30` 数据；查询周报 `[10-01, 10-07]` 实际截断丢弃 `10-07` 并吞入 `09-30`，存在整整 24 小时的周期性错位。
2. **统计时间基准双轨撕裂**：
   - 报表中心 `/admin/report/daily` 及收银交班 `/cashier/shift/handover` 使用 `pay_time`（支付完成时间）。
   - 看板营收 `aggregateCurrentBusinessDayPaidOrderMetrics` 与收银台今日流水 `/cashier/order/today` 使用 `order_time`（下单时间）。
   - 跨分界点就餐（如 04:30 开台，05:30 结账买单）的订单，在看板和收银台流水中归属于昨天，而在报表中心和交班中归属于今天，导致四方数据无法勾稽。
3. **前端收银台硬编码营业时段**：
   - 收银端 Flutter `RealCashierBillRepository._searchPage` 写死了 `16:00` 起算且仅计 `12小时`（16:00~04:00），早中餐（08:00~16:00）订单被硬编码过滤隐藏。
4. **开闭区间边界漏洞**：
   - 同比环比接口使用 `le`（双闭区间），整点分界订单被重复计算。
   - 复购率接口使用 `endDate + " 23:59:59"`，导致 `.123` 毫秒级订单漏单。
5. **收银端订单搜索接口缺失租户隔离**：
   - `/cashier/order/search` 未拼入 `shop_id`，存在跨店数据越权漏洞。

---

## 3. 行业标准算法对照与整改规范

| 维度 | 既有缺陷实现 | 行业标准规范 (美团SaaS/客如云/Toast) | 本次整改方案 |
| :--- | :--- | :--- | :--- |
| **营业日定义** | 单日 D 算作 `[D-1 settle, D settle)` | 营业日 D 为 `[D settle, D+1 settle)` | 纠正为 `[D settle, D+1 settle)` |
| **营业日多日区间** | `[start-1 settle, end settle)` | `[start settle, end+1 settle)` | 纠正为 `[start settle, end+1 settle)` |
| **财务营收基准** | 混用 `order_time` 与 `pay_time` | 财务/收款流水严格以 `pay_time` 为准 | 统一以 `pay_time` 过滤已支付订单 |
| **收银台今日流水** | 仅按 `order_time` 过滤 | 支付订单按 `pay_time` 或 `order_time` | 支持已支付跨日订单即时展示 |
| **收银账单搜索** | 前端写死 16:00~04:00 | 服务端权威下发时间窗口，覆盖全天 | 移除硬编码，全天 24h 覆盖 |
| **区间边界** | 双闭 `le` / 拼接 `23:59:59` | 严格半开半闭 `[start, end)` | 统一改为 `>= start AND < end` |
| **门店隔离** | `/cashier/order/search` 漏加 `shop_id` | 强制绑定上下文门店 `shop_id` | 强制校验并拼入 `shop_id` 过滤 |

---

## 4. 实施与验证记录
- **实施状态**：RESOLVED
- **受影响工程**：
  - `server`
  - `admin_panel_flutter`
- **代码走查与单测验收**：
  - `ShopBusinessWindowResolverTest`: 6/6 PASSED (营业日窗口模型、多日区间对齐与 04:00 容错兜底)
  - `ReportOrderAggregateTest` & `ReportLogServiceTest`: 24/24 PASSED (导出任务聚合与每日时间窗口)
  - `cashier_workspace_test.dart`: 10/10 PASSED (收银台工作区与当班状态)
  - `cashier_bill_test.dart` & `cashier_shift_test.dart`: 38/38 PASSED (全天账单预设与权威营业日对齐)
  - `mvn clean package -DskipTests`: BUILD SUCCESS (生成 runnable JAR: `diancan-0.0.1-SNAPSHOT.jar`)
  - `docs/openapi.yaml` & `docs/API.md`: 同步发布 v1.2.258 版本记录与标准化时间契约。

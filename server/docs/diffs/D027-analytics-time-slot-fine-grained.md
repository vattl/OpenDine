# D027 分时段营收细分改造方案

## 1. 现状审计

### 1.1 当前实现（`AnalyticsMapper.xml` + `AnalyticsServiceImpl.businessOverview`）

`GET /admin/analytics/business` 返回两套分时段营收，每套仅 **4 个粗分段**：

| 字段 | 分档 | 键 | 粒度 |
|---|---|---|---|
| `time_slots_natural_clock` | 墙钟自然分档 | `breakfast`(05–10) / `lunch`(10–16) / `dinner`(16–22) / `late_night`(其余) | 4 段 |
| `time_slots_business_anchor` | 营业锚点固定分档（16:00 为锚，与门店营业窗口解耦） | `bd_evening`(16–22) / `bd_late_night`(22–24∪0–4) / `bd_breakfast`(4–10) / `bd_lunch`(10–16) | 4 段 |

每行结构（`AnalyticsTimeSlotRow`）：`slot_key` / `net_revenue`（净额）/ `order_count`（单量）。

### 1.2 问题

- 粒度粗：`dinner` 覆盖 6 小时、`late_night` 跨凌晨，无法观察**高峰小时**（如 18–19 是否为晚市峰值、0–2 是否为夜宵峰值）。
- 无法绘制小时级营收曲线；运营无法定位低峰/高峰窗口做排班与促销。
- 现状无测试覆盖。

### 1.3 约束

- 契约在 `docs/openapi.yaml`（`AnalyticsBusinessData` / `AnalyticsTimeSlotRow`），前端已按 4 段键消费。
- 项目惯例（D014 支付）：**字段名尽量沿用，避免前端失效** → 不删除现有 4 段字段。
- 金额口径不变：净额 = `sett_amount - discount_amount + service_fee - refund_amount - pay_amount_gift`，仅统计 `success` 且接单完成（rec_order/off_order/NULL）订单。

## 2. 方案对比

### 方案 A（推荐）：保留 4 段 + 新增两套小时级序列

- `time_slots_natural_clock` / `time_slots_business_anchor` **原样保留**（前端兼容，零改动）。
- 新增 **`time_slots_hourly`**：墙钟小时逐时（`00`–`23`），返回窗口内有订单的小时桶（有序）。
- 新增 **`time_slots_business_hourly`**：营业日视角 24 小时逐时，以门店 `open_time` 为起点（默认 16:00，即 `16:00–17:00` → `bd_hour_00` … `15:00–16:00` → `bd_hour_23`），返回有订单的小时桶。

新增行结构（独立 schema，不影响旧行）：

```json
{
  "hour_key": "18",
  "start": "18:00",
  "end": "19:00",
  "net_revenue": 1526.5,
  "order_count": 18,
  "avg_ticket": 84.81
}
```

营业锚点行 `hour_key` 形如 `bd_hour_00`…`bd_hour_23`，`start/end` 为墙钟起止。

**优点**：完全向后兼容；信息完整（可画 24h 双曲线）；口径与现有 4 段一致（同 filter）。
**代价**：响应新增 ≤48 行。

### 方案 B：仅把 `time_slots_natural_clock` 改为 2 小时粒度（12 桶）

- 键 `slot_00`…`slot_22`（每 2 小时一桶），删除 `breakfast/lunch/dinner/late_night`。
- **破坏前端现有键映射**，前端需同步改造；营业锚点 4 段仍保留。

### 方案 C：层级结构（段内细分 buckets）

- 每段行增加 `buckets[]`（段内 2 小时小桶）。
- 结构变复杂，前端解析成本高，与"返回简单"的偏好相悖。

**推荐 A**。

## 3. 方案 A 详细设计

### 3.1 SQL（`AnalyticsMapper.xml` 新增 2 个 select）

```sql
<!-- 墙钟小时：与 time_slots_natural_clock 同口径（含 businessDayFilter 排除关门时段） -->
<select id="selectTimeSlotHourly" resultType="map">
    SELECT
        LPAD(HOUR(o.order_time), 2, '0') AS hour_key,
        COALESCE(SUM(<include refid="orderNetExprO"/>), 0) AS net_revenue,
        COUNT(*) AS order_count
    FROM t_order o
    WHERE
    <include refid="orderSuccessFilter"/>
    <include refid="orderTimeRange"/>
    <include refid="shopFilter"/>
    <include refid="businessDayFilter"/>
    GROUP BY HOUR(o.order_time)
    ORDER BY hour_key ASC
</select>

<!-- 营业日视角小时：以门店 open_time 为起点（默认 16:00），(HOUR - openHour + 24) % 24 -->
<select id="selectTimeSlotBusinessHourly" resultType="map">
    SELECT
        CONCAT('bd_hour_', LPAD(((HOUR(o.order_time)
            - CAST(SUBSTRING_INDEX(#{openTime}, ':', 1) AS UNSIGNED) + 24) % 24), 2, '0')) AS hour_key,
        COALESCE(SUM(<include refid="orderNetExprO"/>), 0) AS net_revenue,
        COUNT(*) AS order_count
    FROM t_order o
    WHERE
    <include refid="orderSuccessFilter"/>
    <include refid="orderTimeRange"/>
    <include refid="shopFilter"/>
    <include refid="businessDayFilter"/>
    GROUP BY ((HOUR(o.order_time) - CAST(SUBSTRING_INDEX(#{openTime}, ':', 1) AS UNSIGNED) + 24) % 24)
    ORDER BY hour_key ASC
</select>
```

- 跨天归属：墙钟小时按 `HOUR(order_time)`（00:30 → `00`）；营业锚点小时把 0–15 时订单偏移到前一日营业日尾段（如 03:00、open=16 → `bd_hour_11`，对应墙钟 03:00–04:00 桶；换算公式 墙钟 = (N + openHour) % 24）——与 `businessDateOfOrder` 的营业日归属一致。
- 时间窗内无订单的小时不返回（前端画曲线可补零）。

### 3.2 Service（`AnalyticsServiceImpl.businessOverview`）

```java
out.put("time_slots_hourly", analyticsMapper.selectTimeSlotHourly(startTime, endTime, shopId,
        resolveOpenTime(shopId), resolveSettleTime(shopId)));
out.put("time_slots_business_hourly", analyticsMapper.selectTimeSlotBusinessHourly(startTime, endTime, shopId,
        resolveOpenTime(shopId), resolveSettleTime(shopId)));
```

- `selectTimeSlotHourly` 也需 `openTime/settleTime`（businessDayFilter 用）。
- `avg_ticket` 在 Service 层计算（净额/单量，单量>0）。

### 3.3 Mapper 接口（`AnalyticsMapper.java` 新增 2 方法）

```java
List<Map<String, Object>> selectTimeSlotHourly(@Param("startTime") String startTime,
        @Param("endTime") String endTime, @Param("shopId") Integer shopId,
        @Param("openTime") String openTime, @Param("settleTime") String settleTime);

List<Map<String, Object>> selectTimeSlotBusinessHourly(@Param("startTime") String startTime,
        @Param("endTime") String endTime, @Param("shopId") Integer shopId,
        @Param("openTime") String openTime, @Param("settleTime") String settleTime);
```

### 3.4 time_definition 说明

`time_definition` 增加两条说明：
- `time_slots_hourly`：墙钟小时逐时净额/单量（00–23，与自然钟点 4 段同口径）
- `time_slots_business_hourly`：以门店 open_time（默认 16:00）为起点的营业日小时序列（bd_hour_00…23）

## 4. openapi.yaml 更新

- `AnalyticsBusinessData` 增加 `time_slots_hourly`、`time_slots_business_hourly`（array of `AnalyticsHourlySlotRow`）。
- 新增 schema `AnalyticsHourlySlotRow`（hour_key/start/end/net_revenue/order_count/avg_ticket）。
- `AnalyticsBusinessTimeDefinition` 增加两段说明。
- changelog 顶部加 v1.2.238 条目。

## 5. 测试与验证计划

- 新增单测：`AnalyticsTimeSlotHourlyTest`（mock AnalyticsMapper）验证：
  - 两套小时序列组装正确（含 avg_ticket 计算、无单量时 avg=0/省略）
  - `resolveOpenTime`/`resolveSettleTime` 传参正确（默认 16:00/04:00 与门店配置分支）
  - 空结果不 NPE、返回空列表
- SQL 实机验证（可选，若本地可连 debug 库）：对窗口内跨天订单核对 hour 归属。
- 全量 `mvn test` 回归（基线 854）+ `mvn clean package -DskipTests` 构建 jar。

## 7. 实施记录（2026-09-10 已按方案 A 完成）

- `AnalyticsMapper.java`：新增 `selectTimeSlotHourly` / `selectTimeSlotBusinessHourly`（均带 openTime/settleTime）。
- `AnalyticsMapper.xml`：新增两段 SQL（墙钟 `HOUR(order_time)` 分桶；营业日 `(HOUR + 24 - openHour) % 24` 分桶），同口径含 `businessDayFilter`。
- `AnalyticsServiceImpl.businessOverview`：组装 `time_slots_hourly` / `time_slots_business_hourly`，`withAvgTicket` 补 `avg_ticket`/`start`/`end`（bd_hour_N 按 (N+openHour)%24 换算回墙钟）；`time_definition` 增加两条说明。
- `docs/openapi.yaml`：v1.2.238 changelog + `AnalyticsHourlySlotRow` schema + 2 个新字段 + time_definition 说明。
- 测试：`AnalyticsTimeSlotHourlyTest`（4 用例：默认窗口组装与传参、门店配置优先、null 安全、跨天归属换算）。

### 7.1 上线后 500 修复（生产回归，同日）

部署后 `GET /admin/analytics/business` 仍 500（70ms 快速失败），debug 库（MySQL 8.0.42，ONLY_FULL_GROUP_BY）实机复现定位两处 SQL 问题：

1. **ERROR 1055（ONLY_FULL_GROUP_BY）**：原 SQL 的 SELECT 用 `LPAD(HOUR(order_time),...)` / `CONCAT(...LPAD(...%24...))` 包装分组表达式，MySQL 严格模式拒绝非聚合列 `o.order_time`。修复：分桶表达式下沉子查询（`SELECT HOUR(o.order_time) AS hh ... ) x GROUP BY hh`），外层对**列**做 LPAD/CONCAT 格式化（列在 GROUP BY 中即函数依赖，合法）。
2. **ERROR 1690（BIGINT UNSIGNED out of range）**：`(HOUR - CAST(... AS UNSIGNED) + 24) % 24` 中 `HOUR` 与 `CAST AS UNSIGNED` 均为无符号，凌晨订单（如 01:00 - 16 = -15）触发无符号下溢。修复：改为 `(HOUR + 24 - CAST(SUBSTRING_INDEX(#{openTime},':',1) AS UNSIGNED)) % 24`，恒非负。

实机验证（debug 库，窗口 2026-08-29~08-30，open=16:00）：

| 墙钟小时 | 净额/单量 | 营业日小时 | 净额/单量 |
|---|---|---|---|
| 19 | 672.00 / 7 | bd_hour_03 | 672.00 / 7 |
| 20 | 674.00 / 6 | bd_hour_04 | 674.00 / 6 |
| 21 | 176.00 / 1 | bd_hour_05 | 176.00 / 1 |
| 22 | 360.00 / 6 | bd_hour_06 | 360.00 / 6 |
| 23 | 905.20 / 8 | bd_hour_07 | 905.20 / 8 |
| 00 | 1112.00 / 16 | bd_hour_08 | 1112.00 / 16 |
| 01 | 118.00 / 3 | bd_hour_09 | 118.00 / 3 |
| 02 | 45.00 / 1 | bd_hour_10 | 45.00 / 1 |

偏移映射与营业日归属全部正确；与 4 段汇总交叉核对一致（dinner=1522=672+674+176，late_night=2540.2=905.2+1112+118+45）。全量 `mvn test` 858 run / 0 fail / 2 skip，jar 构建成功。

## 8. 验收标准

- `GET /admin/analytics/business` 返回新增 `time_slots_hourly`（墙钟小时）与 `time_slots_business_hourly`（营业锚点小时），旧 `time_slots_natural_clock` / `time_slots_business_anchor` 不变。
- 小时桶有序、含 start/end 墙钟标签、净额与单量与 4 段汇总可对上（各小时净额合计 = 4 段净额合计）。
- openapi.yaml 契约同步；jar 构建成功；提交 git。

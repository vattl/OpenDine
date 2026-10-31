# D010 订单新增下单渠道与下单管理员ID（支撑个人业绩统计）

- 日期：2026-09-08
- 状态：IMPLEMENTED（2026-09-08 提交 a52990c；compile 通过，全量测试见 REGRESSION 缺口说明）
- 涉及文件：见各 Diff 段
- 风险等级：STRUCTURAL（建单主链路 create/addDishes 统一写入 + 表结构变更）
- 关联：`/change` 需求 "审计订单 t_order 结构，新增下单渠道和下单管理员ID，后期可以实现个人业绩订单统计"

## 1. SYMPTOM（现状缺口）

`t_order` 当前只有 `openid`（创建者，C 端用户维度）与 `shop_id`（门店维度），**无法回答**：

- 订单由哪个渠道产生（小程序扫码 / 收银台开单 / AI 助手代点 / 小程序外卖）？
- 收银/后台的订单是谁操作创建的（管理员维度）？

因此无法按"收银员/管理员"维度统计个人业绩（单量、实收净额、加菜/折扣等），也无法区分渠道对营收的贡献。

## 2. REPRODUCTION（现状验证路径）

1. 查询 `SELECT * FROM t_order LIMIT 1`：无 `order_channel` / `order_admin_id` 列。
2. 收银端 `POST /cashier/order/quickOrder` 开单后查库：订单与 C 端小程序单无法区分来源（`openid` 为占位常量 `CASHIER_OPENID`，非管理员维度）。
3. 后台按管理员统计业绩：无字段可 GROUP BY。

## 3. ROOT CAUSE（根因）

建单链路统一汇聚在 `OrderController.create` / `addDishes`（C 端、收银 `CashierOrderController.quickOrder` → `orderController.create(dto, request)`、外卖 `TakeoutController.createTakeout` → `orderController.create(dto, request)`、AI 工具 `executeCreateOrder` → `create(dto, null)` 全部进入同一入口），但该入口**从未落库渠道与操作员**。现有机制可复用：

- 渠道判别：`request.getAttribute(CASHIER_QUICK_ORDER_ATTRIBUTE)`（收银已设 TRUE）、`dineInOrTakeOut="外卖"`（外卖）、`AI_TOOL_TURN.get() != null`（AI 工具链 ThreadLocal，AI 请求期间设置）；默认即 C 端小程序。
- 操作员：B 端 JWT 鉴权后 `SysInterceptor.ATTR_ADMIN_ID`（request attribute，`CashierOrderController.getAdminIdStr()` 已同源使用）；C 端/AI 无该值 → NULL。

## 4. TARGET（目标口径）

`t_order` 新增两列，**由服务端在建单入口统一写入，不信任客户端传值**：

| 列 | 类型 | 语义 | 取值 |
|---|---|---|---|
| `order_channel` | varchar(20) NULL | 下单渠道（服务端判定） | `cashier`（收银）/ `takeout`（小程序外卖）/ `ai`（AI 助手）/ `mini_program`（C 端小程序默认） |
| `order_admin_id` | int NULL | 下单管理员 ID（B 端 JWT），C 端/AI 为 NULL | 关联 `t_admin.id` |

判定优先级：**cashier（请求标记）> takeout（diningType=外卖）> ai（AI_TOOL_TURN 活跃）> mini_program（默认）**。
`order_admin_id` 仅取 `request.getAttribute(SysInterceptor.ATTR_ADMIN_ID)`，强制覆盖，防客户端伪造。

后期个人业绩统计口径（交付说明，不在本次实现）：`SELECT shop_id, order_admin_id, SUM(sett_amount+service_fee-discount_amount-refund_amount), COUNT(*) FROM t_order WHERE transac_status='success' AND order_admin_id IS NOT NULL GROUP BY shop_id, order_admin_id`。

## 5. MINIMAL BEHAVIOR DIFF（行为差异）

| 入口 | 渠道判定 | order_admin_id |
|---|---|---|
| C 端小程序 `POST /order/create` / `/order/addDishes` | `mini_program`（默认） | NULL |
| 收银 `POST /cashier/order/quickOrder`（内部调 create，带收银标记） | `cashier` | JWT adminId |
| 小程序外卖 `POST /order/takeout/create`（内部调 create，diningType=外卖） | `takeout` | NULL（C 端） |
| AI 助手 `create_order` / `add_dishes` 工具（内部调 create，request=null） | `ai` | NULL |
| 历史存量订单 | 迁移脚本可选回填（外卖→takeout、openid=CASHIER_OPENID→cashier），默认 NULL 不阻塞 | NULL |

新增列默认 NULL，存量数据无破坏；既有查询/索引不受影响。

## 6. FIX（逐文件 Diff）

### 6.1 `docs/db_migration_order_channel_admin.sql`（新迁移脚本）

幂等 ALTER：`t_order` 追加 `order_channel` varchar(20) NULL（COMMENT 含取值枚举）与 `order_admin_id` int(11) NULL（COMMENT 关联 t_admin.id）；`ALTER TABLE ... ADD COLUMN IF NOT EXISTS` 不适用于 MySQL 8.0 常规语法 → 用存储过程守护式加列（与仓库既有 db_migration_* 幂等风格一致）；末尾附可选历史回填（默认注释掉，`openid='cashier_openid'` 回填 cashier 的说明）。

### 6.2 `docs/db_diancan.sql`（主库脚本同步）

`t_order` 建表末尾追加两列定义（与迁移脚本同口径）。

### 6.3 `Order.java`（实体）

追加 `private String order_channel;` 与 `private Integer order_admin_id;`（MyBatis-Plus 下划线自动映射，无需注解）。

### 6.4 `OrderDTO.java`（DTO）

追加同名两字段（内部流转用；`create` 强制覆盖，客户端无法借此篡改——字段虽可绑定，但服务端立即 set 覆盖）。

### 6.5 `OrderController.java`（核心写入点）

新增私有方法：

```java
private static final String CHANNEL_CASHIER = "cashier";
private static final String CHANNEL_TAKEOUT = "takeout";
private static final String CHANNEL_AI = "ai";
private static final String CHANNEL_MINI_PROGRAM = "mini_program";

/**
 * 下单渠道与操作员落库（服务端权威，不信任客户端传值）：
 * channel 判定优先级 cashier（收银标记）> takeout（diningType=外卖）> ai（AI 工具链活跃）> mini_program（默认）；
 * order_admin_id 取 B 端 JWT（SysInterceptor.ATTR_ADMIN_ID），C 端/AI 为 null。
 */
private void resolveOrderChannelAndOperator(OrderDTO order, HttpServletRequest request) {
    String channel = CHANNEL_MINI_PROGRAM;
    if (request != null && Boolean.TRUE.equals(request.getAttribute(CASHIER_QUICK_ORDER_ATTRIBUTE))) {
        channel = CHANNEL_CASHIER;
    } else if ("外卖".equals(order.getDineInOrTakeOut())) {
        channel = CHANNEL_TAKEOUT;
    } else if (AI_TOOL_TURN.get() != null) {
        channel = CHANNEL_AI;
    }
    order.setOrder_channel(channel);
    Integer adminId = null;
    if (request != null) {
        Object attr = request.getAttribute(com.lanf.interceptor.SysInterceptor.ATTR_ADMIN_ID);
        if (attr != null) {
            try {
                adminId = Integer.valueOf(attr.toString());
            } catch (NumberFormatException e) {
                adminId = null;
            }
        }
    }
    order.setOrder_admin_id(adminId);
}
```

调用点：`create`（applyShopContextToOrderDto 之后）、`addDishes`（applyShopContextToOrderDto 之后），均先于金额/明细处理，随 `BeanUtils.copyProperties(order, orderEntity)` 落库。

### 6.6 `docs/openapi.yaml`

`/order/create` 与 `/order/addDishes` 描述追加：服务端统一写入 `order_channel`（cashier/takeout/ai/mini_program）与 `order_admin_id`（收银/后台操作员，C 端为 null），客户端传入值不生效；changelog 追加一条 v1.2.220 记录。

## 7. REGRESSION（回归验证）

1. 编译：`.\mvnw.cmd compile`（PowerShell）。
2. 全量测试：排除既有 3 个编译失败测试类（Personal*Webhook、CashierOrderControllerTest，基线问题）后运行，确认无新增失败（新增字段不影响既有断言）。
3. 手工核对（debug 库）：`create` 落库后 `order_channel` 正确取值（C 端=mini_program、收银=cashier、外卖=takeout、AI=ai）、`order_admin_id` 仅收银/后台有值；客户端在 body 传 `order_channel="admin"` 时落库值仍为服务端判定值。

## 8. 交付说明

- 覆盖范围：建单主链路（create/addDishes 全入口）渠道与操作员落库；表结构与主库脚本同步；openapi 描述同步。
- 未覆盖：**个人业绩统计报表接口**（用户"后期实现"）；历史数据回填（迁移脚本提供可选回填，默认不执行）；渠道枚举扩展（如将来接入美团/饿了么等第三方平台单，在 create 入口或对账落地处新增取值即可）。
- 行为差异集中在：新列默认 NULL、服务端强制覆盖防篡改；存量查询与既有接口响应不受影响（`@JsonIgnoreProperties` 已允许未知字段，新字段不出现在响应序列化白名单外——如前端需要可在 Order 响应透出）。

# API Contract

## 全系统接口权限深度审计与 POS 别名及飞鹅云安全加固（v1.2.338 / WI-080）

- **业务背景与安全加固**：
  - 对系统全部 108 个 Controller 控制器、806 个 API 端点进行全量权限与安全扫描，排查并修复未配置权限导致 403 阻断及未被拦截器有效防护的安全隐患。
- **核心修复与变更明细**：
  1. **飞鹅云打印接口鉴权拦截加固 (`SysInterceptor.java`)**：
     - 在 `SysInterceptor` 中将 `/api/feieyun/` 正式纳入 `isCashierPath` 判定范围。
     - 彻底修复此前 `/api/feieyun/print`、`/api/feieyun/print-label`、`/api/feieyun/order-status`、`/api/feieyun/printer-status`、`/api/feieyun/add-printer` 因未匹配 `isAdminPath` 与 `isCashierPath` 而无条件放行（Bypass）的高危安全隐患，强制要求管理员/收银员有效 JWT 鉴权与 `printing:manage|cashier:operate` 权限。
  2. **统一通知运维端点权限补全 (`NotificationChannelController.java`)**：
     - 补全通道连接数统计接口：`GET /admin/notifications/channel-stats`（`notifications:view|notifications:manage`）、`GET /cashier/notifications/channel-stats`（`notifications:view|cashier:operate`）；
     - 补全测试广播推送接口：`POST /admin/notifications/test-push`（`notifications:manage`）、`POST /cashier/notifications/test-push`（`notifications:manage|cashier:operate`）；
     - 补全历史通知归档清理接口：`POST /admin/notifications/cleanup`（`notifications:manage|admin:super`）。
  3. **移动与桌面 POS 收银写操作别名接口补全 (`/api/pos/**`)**：
     - 补全 `POST /api/pos/orders/quickOrder`、`POST /api/pos/quickOrder`、`POST /cashier/orders/quickOrder`（`cashier:operate`）；
     - 补全 `POST /api/pos/orders/addDishes`、`POST /api/pos/addDishes`、`POST /cashier/orders/addDishes`（`cashier:operate`）；
     - 补全 `POST /api/pos/orders/refundDish`、`POST /api/pos/refundDish`、`POST /cashier/orders/refundDish`（`cashier:operate`）；
     - 补全 `POST /api/pos/orders/refund`、`POST /api/pos/refund`、`POST /cashier/orders/refund`（`cashier:operate`）；
     - 补全 `POST /api/pos/orders/updatePrice`、`POST /api/pos/updatePrice`、`POST /cashier/orders/updatePrice`（`cashier:operate`）；
     - 补全 `POST /api/pos/orders/discount`、`POST /api/pos/discount`、`POST /cashier/orders/discount`（`cashier:operate`）；
     - 补全 `POST /api/pos/orders/checkout`、`POST /api/pos/checkout`、`POST /cashier/orders/checkout`、`POST /api/pos/tables/checkout`（`cashier:operate`）；
     - 补全 `POST /api/pos/orders/force-checkout`、`POST /api/pos/force-checkout`、`POST /cashier/orders/force-checkout`（`admin:manage`）；
     - 补全 `POST /api/pos/orders/hang`、`POST /api/pos/hang`、`POST /cashier/orders/hang`、`POST /api/pos/orders/unhang`、`POST /api/pos/unhang`、`POST /cashier/orders/unhang`（`cashier:operate`）；
     - 补全 `POST /api/pos/orders/unCheckout`、`POST /api/pos/unCheckout`、`POST /cashier/orders/unCheckout`（`cashier:operate`）；
     - 补全 `POST /cashier/order/updateDiners`、`POST /cashier/orders/updateDiners`、`POST /api/pos/orders/updateDiners`、`POST /api/pos/updateDiners` 及 `PUT .../diners` 别名（`cashier:operate|order:operate`）。
  4. **权限基线与数据库同步**：
     - 新增 Flyway 迁移脚本 `V055__api_permission_audit_and_pos_feieyun_sync.sql`；
     - 同步更新系统内置字典与全量初始化脚本 `docs/init_api_permission.sql`。

## 微信订阅消息后端可控与配额台账体系（v1.2.337 / WI-079）

- **业务背景与设计目标**：
  - 微信小程序订阅消息遵循单次订阅机制（授权 1 次仅允许下发 1 条），且必须由用户在前端的触摸点击事件中唤起原生授权弹窗。
  - 前端盲目重复弹窗极易打扰用户，导致用户勾选“总是保持以上选择，不再询问”而永久拒收，且前端无状态缓存极易在切换设备或清理缓存后失效，造成下发时频繁遭遇微信 `43101 (user refuse to accept the msg / quota exhausted)` 错误。
  - 本体系将**订阅决策权收口至服务端**，建立精准的“用户-模板”配额台账，结合业务消息下发配额核销、微信 `43101` 错误自动归零自愈与投递审计流水，实现全链路后端可控、智能静默与防过度打扰。
- **核心机制与闭环链路**：
  1. **场景模板配置管理 (`t_subscribe_scene_template`)**：
     - 支持按业务场景编码（如 `MEAL_PICKUP_READY` 取餐通知、`ORDER_PAID` 支付凭证、`REFUND_COMPLETED` 退款凭证）配置微信模板 ID (`template_id`)、跳转小程序页面路由 (`page_path`) 及动态参数映射规则。
     - 支持模板动态启用/禁用维护，解耦业务代码与微信固定模板配置。
  2. **用户配额台账管理 (`t_user_subscribe_quota`)**：
     - 以 `(openid, template_id)` 唯一键跟踪用户在该模板下的剩余可用额度 (`remain_quota`)、累计同意次数 (`accepted_count`)、拒绝次数 (`rejected_count`) 与永久停用/拒收标记 (`is_blocked`)。
     - 采用原子更新 SQL 杜绝高并发竞争穿透。
  3. **智能弹窗决策（Smart Prompt Decision）**：
     - 前端在关键业务交互节点（如点餐、下单前、结账完成）调用 `GET /api/v1/subscribe/prompt-decision?scene=MEAL_PICKUP_READY&openid=xxx`。
     - 若台账表明该场景已有剩余配额 (`remain_quota > 0`) 或用户已被拉黑 (`is_blocked = 1`)，后端返回 `need_prompt: false`，前端完全跳过弹窗，达成极致静默体验；
     - 仅当配额耗尽 (`remain_quota <= 0`) 且场景有效时返回 `need_prompt: true` 与对应 `template_ids`，指导前端按需精准唤起微信授权。
  4. **授权结果上报与配额流转 (`POST /api/v1/subscribe/report`)**：
     - 前端执行 `wx.requestSubscribeMessage` 后，将各模板的状态（`accept`/`reject`/`ban`）回传服务端。
     - 服务端根据上报结果原子递增剩余额度（`accept`）或标记拒收/拉黑（`reject`/`ban`）。
  5. **业务消息下发核销与 43101 自愈补偿**：
     - KDS 划菜整单出餐完成或订单状态流转下发微信消息时，优先校验并扣减对应配额；
     - 若向微信网关发送请求后微信返回 `errcode: 43101`，系统触发配额自愈补偿，立即将用户该模板的 `remain_quota` 原子重置归零，纠正服务端与微信端的不一致状态；
     - 下发结果（包括耗时、请求参数摘要、微信错误码、msg_id 等）全量沉淀至 `t_subscribe_send_log` 审计日志表。

### 接口契约明细

#### 1. 订阅弹窗决策接口
- **URL**: `GET /api/v1/subscribe/prompt-decision`
- **认证**: 公开接口（`WebAppConfigurer` 放行）
- **请求参数 (Query)**:
  - `scene`: 业务场景编码，例如 `MEAL_PICKUP_READY`（必填）
  - `openid`: 微信用户 openid（必填）
  - `shop_id`: 门店 ID（可选）
- **响应示例**:
  ```json
  {
    "code": 0,
    "msg": "success",
    "data": {
      "scene": "MEAL_PICKUP_READY",
      "need_prompt": true,
      "remain_quota": 0,
      "template_ids": ["wX1234567890abcdef_pickup"],
      "page_path": "pages/order/detail",
      "reason": "配额不足需要弹窗授权"
    }
  }
  ```

#### 2. 授权结果上报接口
- **URL**: `POST /api/v1/subscribe/report`
- **认证**: 公开接口（`WebAppConfigurer` 放行）
- **请求体 (JSON)**:
  ```json
  {
    "openid": "oXXXX1234567890",
    "scene": "MEAL_PICKUP_READY",
    "results": {
      "wX1234567890abcdef_pickup": "accept"
    }
  }
  ```
- **响应示例**:
  ```json
  {
    "code": 0,
    "msg": "上报成功",
    "data": {
      "updated_count": 1,
      "current_quotas": {
        "wX1234567890abcdef_pickup": 1
      }
    }
  }
  ```

#### 3. 用户订阅配额查询接口
- **URL**: `GET /api/v1/subscribe/quota`
- **认证**: 公开接口
- **请求参数 (Query)**:
  - `openid`: 微信用户 openid（必填）
  - `template_id`: 模板 ID（可选）
- **响应示例**:
  ```json
  {
    "code": 0,
    "msg": "success",
    "data": [
      {
        "openid": "oXXXX1234567890",
        "templateId": "wX1234567890abcdef_pickup",
        "remainQuota": 1,
        "acceptedCount": 2,
        "rejectedCount": 0,
        "isBlocked": 0,
        "lastSubscribeTime": "2026-10-31 08:30:00"
      }
    ]
  }
  ```

#### 4. 管理端-场景模板列表
- **URL**: `GET /admin/subscribe/scenes`
- **权限**: `notifications:view`
- **响应示例**:
  ```json
  {
    "code": 0,
    "msg": "success",
    "data": [
      {
        "id": 1,
        "sceneCode": "MEAL_PICKUP_READY",
        "sceneName": "出餐完成取餐通知",
        "templateId": "wX1234567890abcdef_pickup",
        "pagePath": "pages/order/detail",
        "status": 1
      }
    ]
  }
  ```

#### 5. 管理端-场景模板保存/修改
- **URL**: `POST /admin/subscribe/scenes` / `PUT /admin/subscribe/scenes/{id}`
- **权限**: `notifications:manage`
- **请求体 (JSON)**:
  ```json
  {
    "sceneCode": "MEAL_PICKUP_READY",
    "sceneName": "出餐完成取餐通知",
    "templateId": "wX1234567890abcdef_pickup",
    "pagePath": "pages/order/detail",
    "dataPattern": "{\"character_string1\": \"{order_no}\", \"thing2\": \"{dish_summary}\"}",
    "status": 1
  }
  ```

#### 6. 管理端-订阅消息发送审计日志查询
- **URL**: `GET /admin/subscribe/logs`
- **权限**: `notifications:view`
- **请求参数 (Query)**:
  - `openid`: 微信 openid（可选）
  - `scene`: 场景编码（可选）
  - `template_id`: 模板 ID（可选）
  - `success`: 是否成功，1成功 0失败（可选）
  - `page`: 页码，默认 1
  - `limit`: 每页大小，默认 20
- **响应示例**:
  ```json
  {
    "code": 0,
    "msg": "success",
    "count": 1,
    "data": [
      {
        "id": 1,
        "openid": "oXXXX1234567890",
        "sceneCode": "MEAL_PICKUP_READY",
        "templateId": "wX1234567890abcdef_pickup",
        "sendStatus": 1,
        "costMs": 120,
        "createTime": "2026-10-31 08:35:10"
      }
    ]
  }
  ```

## KDS 划菜整单完成外卖订单自动叫骑手联动（v1.2.336 / WI-076）

- **业务场景与触发机制**：
  - 在 KDS 厨房显示系统中，当后厨/传菜员划菜导致订单的所有菜品全部出餐完成时，整单工单状态流转至 KdsOrderStatus.ALL_DONE (40) 并发布领域事件 KdsOrderStatusChangedEvent。
  - KdsEventListener 在事务提交后（TransactionPhase.AFTER_COMMIT）捕获该事件：
    - 若订单为外卖类型（dine_in_or_take_out = '外卖'），自动调用 TakeoutZsqIntegrationService.tryAutoDispatchOnKdsCompleted 触发向聚合配送平台（真省钱/ZSQ）叫骑手派单。
    - 若订单为堂食或打包自提订单，跳过叫骑手逻辑，仅维持原有的点餐端与收银端取餐通知。
- **三层幂等与并发防重保护**：
  - **订单类型守卫**：非外卖订单绝不查询配送单或发起呼叫。
  - **状态机幂等守卫**：若配送单记录已处于 dispatched（已发配送）、delivering（骑手接单/配送中）、completed（配送完成）或 pending（正在发起呼叫中），系统自动跳过，严禁二次发起第三方请求或重复计费。
  - **异常容错隔离**：外部配送平台网络抖动、超时或余额不足时，异常被内部捕获降级并记录 WARN 日志，绝不阻断或影响 KDS 划菜出餐状态的持久化与广播。

## 全量接口权限审计与细粒度权限码补全（v1.2.335 / WI-072）

- **全系统接口权限审计与 100% 覆盖**：
  - 完成系统全量 620 个 Controller 端点扫描审计（覆盖 `/admin/**`、`/cashier/**`、`/api/pos/**`、历史兼容接口及 C 端公开接口）；
  - 补全全部遗漏的 90+ 个接口映射至 `ApiPermissionMapping.java`、Flyway 增量脚本 `V049__api_permission_granularity_and_audit.sql`、全量初始化脚本 `docs/init_api_permission.sql`；
  - 彻底消灭因接口未登记权限而由 `SysInterceptor` 失败关闭触发的 403 `接口权限未配置` 异常。
- **细粒度权限码分类与字典完善**：
  - **菜品与套餐**：`dish:manage:combo`（套餐查看、保存与门店隔离维护），接口映射为 `dish:manage|dish:manage:dish|dish:manage:combo`；
  - **订单与发票**：`order:invoice:create`（发票开具二维码生成）、`order:invoice:view`（发票开具状态与日志查询），映射为 `order:operate|order:invoice:create` 与 `order:view|order:invoice:view`；
  - **高级库存**：`inventory:view`（批次、BOM、采购单、供应商、调拨单、仓库列表查看）、`inventory:manage`（BOM保存/启用、采购创建/更新、供应商维护、调拨/仓库写操作）；
  - **营销活动**：`marketing:firstorder:view`（首单立减活动列表/规则资格查询/核销记录）、`marketing:firstorder:manage`（活动创建/更新/启停）；
  - **日志归档与导出**：`log:archive`（归档检索任务发起与状态查询）、`log:export`（审计日志CSV导出）；
  - **通知规则**：`notifications:view`（通知规则与投递日志查看）、`notifications:manage`（通知规则增删改与测试投递）；
  - **报表导出**：`report:export`（报表导出任务创建、列表与下载）；
  - **系统设置**：`settings:view`（设置概览与门店设置查询）、`settings:manage`（门店设置保存与覆盖删除）；
  - **支付渠道运营**：`payment:view|payment:manage`（渠道停用影响分析、渠道测试交易）；
  - **收银与移动POS别名**：`/api/pos/tables/*`、`/api/pos/orders/*` 映射至 `cashier:operate`、`table:operate`、`table:view`；
  - **飞鹅云打印**：`/api/feieyun/*` 映射至 `printing:manage|cashier:operate`。
- **向后完全兼容机制**：
  - 权限码映射采用管道符多选机制（`coarse:perm|fine:perm`），持有粗粒度权限的历史角色（如超级管理员、店长、收银员等）不受任何影响，新角色支持最小特权安全授权。
- **公共端点白名单完善**：
  - `WebAppConfigurer.java` 显式放行 `/config/contact`、`/config/subscribe-templates`、`/config/app` 及 `/help/**` 端点；
  - `SysInterceptor.java` 将历史遗留端点 `/activity/getAllPopup` 纳入 `isLegacyAdminPath` 保护。

## 会员注册统一默认昵称与资料修改规范（v1.2.333 / WI-071）

- **默认昵称赋值规则**：
  - 会员（`t_user`）注册（初次通过微信授权登录或创建记录）时，若未显式指定昵称，统一生成默认昵称：`老肥吃货` + 用户自增ID（例如 ID 为 10086 则昵称为 `老肥吃货10086`）。
  - **单次写入保证**：默认昵称仅在注册持久化时首次填入，老用户后续的微信登录（`upsertUser`）、会话刷新、手机号绑定（`bindPhoneToOpenid` / `getOfficialPhoneNumber`）均严禁重置或覆盖用户已有昵称。
  - **显式注册防覆盖**：若注册阶段已显式传入自定义昵称，优先保留显式传入的昵称，不进行默认值覆盖。
- **用户信息与昵称修改接口**：
  - **`POST /order/updateUser`**：
    - 请求体支持同时兼容 `nickname` 与 `name` 字段，优先提取非空修改值更新至 `t_user.name`；
    - 响应体与数据对象返回统一的 `nickname` 与 `name`。
  - **`POST /order/updateAvatar`**：
    - 请求参数支持 `nickname`（可选）以及头像文件；
    - 当传入非空 `nickname` 时，同步将昵称保存至 `t_user.name`，支持修改头像时附带更新昵称。
  - **`POST /order/getUserInfo`**：
    - 返回结构除包含原实体字段 `name` 外，补充返回 `nickname` 字段，两者保持一致，彻底杜绝前端读取空白。

## KDS 菜品制作状态生命周期审计与出餐取餐自动通知（v1.2.323）

- **菜品制作状态生命周期审计与“已出餐”纠偏**：
  - **核心准则**：菜品在待传菜（`ready_serve`）中绝不属于已出餐，菜品必须进入已完成（`done`，即 `served_quantity >= line_quantity`）才可标记为“已出餐”（`kds_item_status = 2`，`kds_status_text = "已完成"`）。
  - **底层工单流转修正**：`KdsFlowBatchService.syncTicketAggregates` 彻底修正历史遗留问题——仅当 `lineQty > 0 && served >= lineQty && cookedQty >= lineQty` 时才将 `t_kds_ticket.item_status` 置为 `DONE (2)` 并 `archived = 1`。在待传菜（`ready_serve`，`cookedQty > 0 && served < lineQty`）期间，工单保持为 `COOKING (1)` 且 `archived = 0`。
  - **接口层联查统一解析**：`KdsDetailStatusResolver.enrichDetails` 面向所有包含菜品明细的接口（`GET /order/get`、`GET /order/getOrder`、`POST /order/history`、`GET /cashier/order/today`、`GET /cashier/order/search`、`GET /admin/orderDetail/list`）：
    - 待传菜菜品：返回 `kds_item_status: 1`（在制中），`kds_status_text: "待传菜"`；
    - 已出餐菜品：返回 `kds_item_status: 2`（已完成），`kds_status_text: "已完成"`；
    - 制作中菜品：返回 `kds_item_status: 1`，`kds_status_text: "制作中"`；
    - 待制作菜品：返回 `kds_item_status: 0`，`kds_status_text: "待制作"`；
    - 已退菜菜品：返回 `kds_item_status: 3`，`kds_status_text: "已退菜"`。
  - **彻底杜绝前端误判**：收银台与小程序端不再因 `ready_serve` 误显示为“已出餐”，传菜前台与顾客视角状态绝对可信。
- **整单全部菜品完成自动通知客户取餐**：
  - **自动触发时机**：当订单全部工单均已传菜划单完成（整单聚合状态达 `kds_order_status == KdsOrderStatus.ALL_DONE`）时，通过 `KdsEventListener` 领域事件监听器触发 `KdsCustomerPickupNoticeService.notifyCustomerPickup`。
  - **自动更新订单通知标记**：将 `t_order.notice` 自动更新为 `1`（已通知取餐），内置幂等防重守卫，单笔订单不可重复下发。
  - **多通道实时触达**：
    1. **小程序端实时广播**：通过 `DishMenuPushService` 向 `/ws/menu` 广播 `meal_pickup_ready` 事件，包含 `order_id`、`order_no`、`table_number`、`dine_in_or_take_out`、`pickup_code` 及提示文案，小程序订单页与大屏即时响应；
    2. **KDS 与收银台工作台广播**：通过 `KdsPushService` 广播 `order_notice`，同步更新收银台账单列表上的已通知标识；
    3. **微信订阅消息主动下发**：若下单顾客包含有效微信 `openid` 且后台配置了取餐模板（`weixin.subscribe-templates.pickup-notice`），系统自动调用微信订阅消息接口下发取餐通知（包含取餐码、已出餐状态、温馨提示），调用异常采用安全降级与告警捕获，绝不阻塞主事务。

## 订单与账单时间范围支持年月日纯日期及门店日结时间自动补全（v1.2.322）

- **背景与痛点**：收银台与账单查询客户端传入 `startTime=2026/10/24&endTime=2026/10/24` 等日期格式时，历史解析器未能兼容 `/` 与 `.` 分隔符，且按自然日机械截断至 `00:00:00` 与 `23:59:59`，无法覆盖餐饮门店深夜跨天经营周期（导致 00:00~04:00 订单落入错误班次或丢失）。
- **统一日期解析与门店日结时间补全规则**：
  - 核心解析器 `OrderListTimeRangeResolver` 与 `ShopBusinessWindowResolver` 全面支持纯日期输入（兼容 `yyyy/MM/dd`、`yyyy-MM-dd`、`yyyy.MM.dd`、`yyyyMMdd`）。
  - 当传入纯日期（无具体时分秒）时，后端自动依据当前门店配置的 `settle_time`（默认 `04:00`）补全时分秒：
    - `startTime`：补全为 `startDate settle_time`（例如 `2026-10-24 04:00:00`）；
    - `endTime`：补全为 `(endDate + 1日) settle_time`（例如 `2026-10-25 04:00:00`）；
  - 查询区间在 SQL 层面采用 `[start, end)` 左闭右开逻辑（`order_time >= start AND order_time < end`），严格覆盖至次日 `03:59:59.999`，完整收拢该营业日 24 小时内的全部订单（包含凌晨宵夜订单）；
  - 当 `startTime` 与 `endTime` 传入同一天时（例如 `startTime=2026/10/24&endTime=2026/10/24`），天然映射该营业日完整的 24 小时连续经营周期；
  - 若客户端传入显式时分秒（如 `2026-10-24 18:30:00`），精确保留客户端显式指定的自定义时间范围。
- **覆盖接口范围**：
  - 收银端：`GET /cashier/order/today`、`GET /cashier/order/search`
  - 管理端：`POST /admin/order/list`、`POST /admin/takeout/order/list`、`GET /admin/analytics/*`

## 订单表记录当班收银员与账单接口收银员信息（v1.2.321 / WI-069）

- **数据层扩展**：Flyway `V047__order_add_cashier_id.sql` 为 `t_order` 增加 `cashier_id INT(11) DEFAULT NULL COMMENT '当班收银员ID，关联 t_admin.id'`，并为查询加速创建索引 `idx_order_cashier_id`。
- **开单与结账绑定**：
  - `POST /cashier/order/quickOrder`（收银快速建单）与 `OrderController.create` 开单逻辑中，判定为收银渠道开单时自动写入当前操作员 ID 到 `cashier_id`。
  - `POST /cashier/order/checkout`（收银结账）与 `POST /admin/order/checkout`（管理端结账）在 `CashierCheckoutService` 结账流转中，从请求参数、操作上下文或当班钱箱班次中解析当班收银员 ID，更新并固化订单 `cashier_id`。
- **账单与订单查询结构化双信息**：
  - `GET /cashier/order/today`（今日账单）、`GET /cashier/order/search`（历史账单搜索）、`POST /admin/order/list`（后台订单列表）、`GET /admin/orderDetail/list`（订单详情）在返回订单实体时，通过 `AdminNameResolver.enrichOrdersCashierInfo` 批量查询管理员表：
    - `cashier_id`：当班收银员 ID；
    - `cashier_name`：收银员真实姓名（`t_admin.real_name`，回退 `userName`，例如 `"张晓峰"`）；
    - `cashier_work_no`：收银员工号（`t_admin.work_no`，例如 `"0801"`）；
    - `cashier_display_name` / `display_name`：格式化文案（例如 `"张晓峰 (0801)"` 或 `"张晓峰"`）；
    - `order_admin_name`：开单管理员真实姓名。
  - 前端收银台账单中心直接消费 `cashier_name` 与 `cashier_work_no`，彻底消除仅返回工号或依赖本地硬编码的缺陷。

## 智能配餐与点餐服务（v1.2.319 / WI-065）

深圳烧烤店 AI 智能配餐与智能点餐场景协议，服务于微信小程序与外部智能体（MCP/Skill）。

### 1. 电子发票开具二维码生成接口 (POST /admin/order/invoice/qrcode，权限 order:operate)
- **业务场景**：收银员在账单详情顶栏点击「🧾 电子发票」，向税控服务申请生成本次交易的开票流水号及顾客自助扫码开票二维码。
- **底层架构**：
  - 对接微信官方 APIv3 数电发票抬头收集链接接口：GET /v3/new-tax-control-fapiao/user-title/title-url。
  - 自动通过商户门店凭证生成 WECHATPAY2-SHA256-RSA2048 签名认证。
  - 开票申请持久化记录于 	_order_invoice，状态初始化为 PENDING_SCAN。
  - 支持优雅沙箱降级：未签约商户或微信接口异常时，自动签发防伪一次性令牌兜底链接，收银端永不崩溃。
- **请求参数**：
  - orderNo: 订单号（必填）
  - 	ableNumber: 桌台号（可选）
  - invoiceAmount: 申请开票金额（可选，不可超过订单实付金额）
  - 	axRate: 税率（可选，默认 0.06）
- **响应数据**：
  - orderNo: 订单号
  - apiaoApplyId: 微信或平台开票申请流水号
  - invoiceStatus: 开票状态（PENDING_SCAN）
  - invoiceQrUrl: 二维码 URL（微信官方抬头收集页或安全防伪开票页）
  - invoiceAmount: 最终开票金额
  - 	axRate: 税率
  - xpireMinutes: 有效期（默认 1440 分钟 / 24小时）
  - 
otice: 顾客扫码开票提示文案

### 1.1 电子发票状态与开具明细查询接口 (`GET /admin/order/invoice/status/{orderNo}`，权限 `order:view`)
- **业务场景**：收银员打开或刷新发票弹窗、或定时轮询顾客扫码开票进展。
- **路径参数**：`orderNo` 订单号
- **响应数据**：
  - `orderNo`: 订单号
  - `fapiaoApplyId`: 开票申请流水号
  - `invoiceStatus`: 开票状态（`PENDING_SCAN` 待扫码、`TITLE_SUBMITTED` 抬头已提交、`SUCCESS` 发票已开具、`FAILED` 开票失败）
  - `invoiceAmount`: 开票金额
  - `taxRate`: 税率
  - `titleType`: 抬头类型（`PERSONAL` 个人 / `COMPANY` 企业）
  - `buyerTitle`: 发票抬头
  - `buyerTaxNo`: 纳税人识别号
  - `buyerEmail`: 接收发票邮箱
  - `buyerPhone`: 联系电话
  - `invoiceCode`: 发票代码
  - `invoiceNo`: 发票号码
  - `downloadUrl`: 电子发票 PDF/OFD 下载链接
  - `failReason`: 失败原因（如有）
  - `invoiceQrUrl`: 若为待扫码状态，附带二维码 URL 便于重新展示

### 1.2 财务/收银员录入并确认已开具发票接口 (`POST /admin/order/invoice/issue`，权限 `order:operate`)
- **业务场景**：收银员或财务核对顾客提交的抬头税号后，录入已开出发票的发票号码、代码及 PDF 下载链接，将发票状态置为已开具（SUCCESS）。
- **请求参数**：
  - `orderNo`: 订单号（必填）
  - `fapiaoNumber`: 发票号码（必填）
  - `fapiaoCode`: 发票代码（可选）
  - `fapiaoFileUrl`: 发票 PDF/OFD 下载链接（可选）
- **响应数据**：`code: 200, msg: "发票开具成功"`

### 1.3 顾客手机扫码开票信息查询接口 (`GET /public/invoice/info`、`GET /api/invoice/info`、`GET /order/invoice/public/info`，公开免登录，凭令牌防伪)
- **业务场景**：顾客扫描发票二维码打开移动端页面 `/invoice/apply.html` 时，前端携带安全访问令牌调用该接口获取消费订单号、可开票金额及当前开票状态。
- **请求参数**：`orderNo`（必填）、`token`（必填，24小时高熵安全防伪令牌）、`applyId`（可选）
- **响应数据**：`orderNo`, `applyId`, `invoiceStatus`, `invoiceAmount`, `buyerTitle`, `buyerTaxNo`（已脱敏）, `buyerEmail`（已脱敏）, `buyerPhone`（已脱敏）, `fapiaoNumber`, `fapiaoFileUrl`
- **安全约束**：缺失令牌返回 401，令牌哈希不匹配或过期返回 403，无开票记录返回 404（拒绝任何匿名自动初始化）。

### 1.4 顾客自主提交发票抬头接口 (`POST /public/invoice/submit`、`POST /api/invoice/submit`、`POST /order/invoice/public/submit`，公开免登录，凭令牌防伪)
- **业务场景**：顾客在移动端页面填写企业或个人抬头、税号、电子邮箱/手机后点击提交，数据实时落库并通知收银端。
- **请求参数**：
  - `orderNo`: 订单号（必填）
  - `token`: 安全防伪令牌（必填）
  - `applyId`: 申请流水号（可选）
  - `titleType`: `COMPANY` 企业 / `PERSONAL` 个人（必填）
  - `buyerTitle`: 抬头名称（必填，<=100字符）
  - `buyerTaxNo`: 纳税人识别号/统一社会信用代码（企业必填，15-20位大写字母数字）
  - `buyerEmail`: 接收电子发票邮箱（与手机至少二选一）
  - `buyerPhone`: 联系手机（与邮箱至少二选一）
- **安全约束**：缺失令牌返回 401，令牌哈希不匹配或过期返回 403，无记录返回 404，已开具完成订单返回 400 禁止篡改抬头。日志自动执行敏感个人信息遮蔽。
- **响应数据**：`code: 200, msg: "发票抬头提交成功"`

### 2. 标准远程 MCP 工具协议 (`/mcp/v1/*`)
> **试点门店与开放说明**：菜品查询相关 MCP 工具（`get_store_menu` 与 `get_dish_profile`）已全面**解除门店限制**，支持传入任意合法 `shop_id`（缺省默认为 3）查询对应门店的真实在售菜单与菜品画像；点餐会话/桌台/下单履约类写操作工具（`get_store_tables`, `create_dining_session`, `submit_order` 等）当前试点仍限定为 **`shop_id=3`**（深圳宝安试点门店），非 3 号门店一律阻断并返回 HTTP 403 `SHOP_NOT_SUPPORTED_FOR_MCP`。

- **`GET /mcp/v1/tools`**：查询智能点餐支持的标准 MCP 工具声明（`get_store_menu`, `get_dish_profile`, `get_store_tables`, `create_dining_session`, `solve_meal_plan`, `adjust_meal_plan`, `validate_order_draft`, `submit_order`, `chat_with_llm`）。返回各工具的标准 JSON Schema 格式 `inputSchema`。
- **`POST /mcp/v1/tools/{toolName}`**：路径参数风格执行 MCP 工具调用，请求体 `{"arguments": {...}}`，返回 MCP Tool Execution 协议结构 `{"content": [{"type": "text", "text": "..."}], "isError": false}`。
- **`POST /mcp/v1/tools/execute`**：网关/Dify 格式通用执行入口，请求体 `{"name": "tool_name", "arguments": {...}}`。
- **`GET /mcp/v1/tables`**：MCP 门店桌台查询 HTTP 端点。入参 `shop_id`（固定为3）、可选 `status`（0: 空闲可入座/下桌, 1: 就餐中, 2: 待清台）、可选 `area_code`（hall 大厅/box 包厢/patio 外摆）。返回桌台列表、各状态计数及空闲可用桌号列表 `available_tables`。
- **新增桌台 MCP 工具 (`get_store_tables`)**：在 `GET /mcp/v1/tools` 中注册，外部 Agent 可通过此工具查询门店桌台实时占用、各区域分类及空闲桌号列表，支持 Agent 精确下桌与开台推荐。
- **`POST /mcp/v1/chat`**：MCP 大模型自然语言调用接口。请求体 `{"prompt": "...", "shop_id": 3, "messages": [...]}`，服务端内部自动注入试点门店真实在售菜单与 System Prompt，请求配置的大模型（OpenAI/DeepSeek/火山方舟等）并返回推理回复。
- **`GET /mcp/v1/config`**：大模型环境变量配置探测接口。返回当前生效的模型、API 地址、超时时长、代理及脱敏后的密钥状态。
- **大模型 MCP 工具 (`chat_with_llm`)**：在 `GET /mcp/v1/tools` 中暴露，支持外部 MCP 智能体直接调用大模型推理。
- **环境变量配置优先级与网络调优**：
  - API Key: `LLM_API_KEY` > `AI_API_KEY` > `ARK_API_KEY` > `ai.api.key`
  - API URL: `LLM_API_URL` > `AI_API_URL` > `ai.api.url` (默认 `https://api.deepseek.com/v1/chat/completions`，支持只配置 base host 自动智能补全)
  - Model: `LLM_MODEL` > `AI_MODEL` > `ARK_MODEL` > `ai.model` (默认 `deepseek-chat`)
  - 超时控制: `LLM_TIMEOUT_SECONDS`（默认 90 秒，大模型推理或境外网关如 `lax.toklens.ai` 耗时较长时可设为 120）、`LLM_CONNECT_TIMEOUT_SECONDS`（默认 15 秒）
  - 正向代理: `LLM_PROXY_HOST`、`LLM_PROXY_PORT`（可选，配置 HTTP 代理解决国内服务器访问境外大模型网关网络延迟/丢包问题）
- **入参规范与兼容性**：MCP 接口已统一采用 **`shop_id`** 作为标准入参字段（试点门店固定为 3），工具的 `inputSchema` 统一声明为 `shop_id`（服务端底层保留对历史 `store_id` 的兼容回退）。
- **菜单数据增强**：`get_store_menu` 工具及底层 `menu-snapshot` 接口响应菜品列表中已包含月销量 `monthlysale`、`sales_count` 以及菜品主图 `image`，便于 Agent 基于菜品热度与图片生成推介。
- **订单与桌台联动**：`submit_order` 工具支持传入 `table_number`，下单成功后自动联动更新 `t_table` 桌台状态为 `status=1`（就餐中）并绑定正式订单号与消费金额。

### 3. 菜品食材、营养与风味画像维护接口 (`/api/v1/ai/stores/{storeId}/dish-profiles*`)
- **`GET /api/v1/ai/stores/{storeId}/dish-profiles`**：查询指定门店的全部菜品及其当前 AI 画像配置状态。支持参数 `categoryId` 按分类过滤、`configuredOnly` 按已配置/未配置过滤，响应携带菜品单价(分)、在售售罄状态及详细画像，供前端管理后台列表展示。
- **`GET /api/v1/ai/stores/{storeId}/dish-profiles/{dishId}`**：查询单个菜品的画像详情。
- **`PUT /api/v1/ai/stores/{storeId}/dish-profiles/{dishId}`**：新增或修改指定菜品的 AI 画像配置（支持原料、调料、后厨免辣制作开关 `non_spicy_available`、可选辣度数组、过敏原数组、交叉接触风险、健身控重标识、卡路里、蛋白质、脂肪及净重克数）。
- **`POST /api/v1/ai/stores/{storeId}/dish-profiles/batch`**：批量保存或更新菜品画像配置。
- **`POST /api/v1/ai/stores/{storeId}/dish-profiles/auto-init`**：一键根据门店在售菜品名称与分类进行规则推断初始化，极大降低商户首次冷启动配置门槛。

---

## 订单写入版本前置校验第一批（v1.2.318 / WI-064）

- 适用接口：`POST /order/addDishes`、`POST /cashier/order/addDishes`、`POST /cashier/order/refundDish`、`POST /cashier/order/updatePrice`、`POST /cashier/order/discount`。
- 请求可选传 `expectedVersion`，兼容别名 `expected_version`；值必须是非负整数。省略时保持旧客户端兼容，但成功写入仍会推进订单版本。
- 服务端在订单行锁内比较 `expectedVersion` 与 `t_order.revision`，并在业务写入成功后用 CAS 原子递增。成功响应统一新增 `revision`，前端应立即替换本地版本。
- 版本过期返回 HTTP `409`、`error_code=ORDER_VERSION_CONFLICT`、`msg=订单已被其他终端修改，请刷新后重试`；`data` 含 `orderNo/revision/transacStatus/settAmount/discountAmount/serviceFee`。冲突检查先于审批令牌消费和业务副作用。
- 非法版本返回 HTTP `400`、`error_code=ORDER_VERSION_INVALID`。收银端 Map 请求同时携带两个别名时，值必须一致；客户端应统一只发送 `expectedVersion`。
- KDS 云端仍是业务权威；POS 加菜经 `/order/addDishes` 已推进 `t_order.revision`，KDS 命令层只推进票据与 KDS 聚合版本，不重复推进订单版本。

前端适配：读取订单后保存 `revision`；执行上述动作时传入该值；成功后使用响应 `revision` 覆盖本地值；409 时刷新订单与桌台权威快照，展示冲突提示并由用户确认后重新操作，禁止使用旧版本自动重放。

## 高风险订单动作权限迁移（v1.2.317 / WI-063）

- `POST /cashier/order/refund`、`refundDish`、`updatePrice`、`discount`、`unCheckout` 及 `POST /admin/order/refund` 已统一接入动作级三态决策，不再由 Controller 分别拼接密码校验和令牌核销。
- HTTP 入口权限保持 `cashier:operate`（运营退款入口保持 `order:operate`）；真正执行分别要求 `order:operate:refund`、`order:operate:changePrice`、`order:operate:discount`、`order:operate:reopen`。
- 当前登录人有精确 execute 权限时直接执行；仅有收银入口权限时返回 `code=40322`、`outcome=REQUIRE_APPROVAL`、`reasonCode=APPROVAL_REQUIRED` 和精确 `approval.permission`，业务不会执行。
- `approvalToken` 由统一决策器按动作、订单、金额、操作者、门店和终端严格核销。兼容的 `authorization: {account,password}` 会先签发 `bindingVersion=2` 一次性令牌并立即经同一决策器核销，不再构成旁路。
- Flyway `V042__high_risk_action_role_migration.sql` 从内置 `cashier` 角色移除四类 execute/approve 权限，只保留 `cashier:operate` 发起能力；已知管理角色显式获得四类 execute/approve。自定义角色不被重写，可按职责逐项授权。
- 授权失败响应是增量兼容：保留 `code/msg`，新增 `outcome/reasonCode/approval`；成功业务响应不变。

## 权限三态决策与接口映射单一权威（v1.2.316 / WI-062-AUTH）

- `POST /admin/access/evaluate` 无论是否传 `context` 都统一进入 `AccessDecisionService`，不再存在旧/新两套解释逻辑。
- 响应新增权威字段 `outcome`：
  - `ALLOW`：动作可以继续。
  - `REQUIRE_APPROVAL`：当前收银员只有入口权限，应打开现场密码/PIN 或扫码审批流程。
  - `DENY`：硬拒绝，客户端不得自动重试或当作可审批状态。
- 兼容字段 `allow`、`approvalRequired`、`permissionGranted`、`reasonCode` 继续返回；新客户端应优先使用 `outcome`。
- 首批动作词汇：

  | 动作 | 入口权限 | 执行权限 | 审批权限 |
  |---|---|---|---|
  | 退款/退菜 | `cashier:operate` | `order:operate:refund` | `order:operate:refund:approve` |
  | 改价/赠送 | `cashier:operate` | `order:operate:changePrice` | `order:operate:changePrice:approve` |
  | 优惠 | `cashier:operate` | `order:operate:discount` | `order:operate:discount:approve` |
  | 反结账 | `cashier:operate` | `order:operate:reopen` | `order:operate:reopen:approve` |

- 仅持有入口权限时，无令牌返回 `REQUIRE_APPROVAL`；严格绑定、未过期且未使用的审批令牌核销成功后返回 `ALLOW/APPROVED_OVERRIDE`；无效令牌返回 `DENY/ACCESS_APPROVAL_INVALID`。
- `t_api_permission` 是接口入口权限的唯一运行时权威。数据库映射缺失返回 403“接口权限未配置”；`ApiPermissionMapping` 仅作为审计清单和 CI/迁移比对来源，不参与运行时兜底。
- Flyway `V041__authorization_mapping_authority.sql` 与 `docs/init_api_permission.sql` 同步完整映射清单及动作权限词汇。

示例响应：

```json
{
  "code": 200,
  "data": {
    "permission": "order:operate:refund",
    "outcome": "REQUIRE_APPROVAL",
    "allow": false,
    "approvalRequired": true,
    "reasonCode": "APPROVAL_REQUIRED",
    "approval": {
      "required": true,
      "permission": "order:operate:refund:approve"
    }
  }
}
```

## 桌台页面 (Table Overview) 前后端交互接口规范（v1.2.315 / WI-062）

- **业务背景与解决痛点**：
  依据 `TABLE_BACKEND_COORDINATION.md` 规范，收银端桌台页面采用黑白极简工业风（UI061 原型）。后端支持区域字典分区、就餐人数动态修改与茶位费联动、原子批量清台与事务保护、以及实时经营脉搏指标计算口径对齐。
- **数据库升级**：
  Flyway `V039__table_area_partitioning.sql` 为 `t_table` 增加 `area_code`（区域编码，如 `hall`, `box`, `patio`）与 `area_name`（区域名称，如 `大厅散座`, `特色包厢`, `露天外摆`）字段，并创建复合索引 `idx_table_shop_area`；同时幂等注册 API 权限映射。
- **新增接口契约**：
  1. `GET /api/pos/table-areas`（及 `/cashier/table/areas`）
     - **权限**：`cashier:operate|table:view`
     - **功能**：获取当前门店桌台分区列表。
     - **返回示例**：
       ```json
       {
         "code": 200,
         "message": "success",
         "data": [
           { "code": "hall", "name": "大厅散座", "sort": 1 },
           { "code": "box", "name": "特色包厢", "sort": 2 },
           { "code": "patio", "name": "露天外摆", "sort": 3 }
         ]
       }
       ```
  2. `PUT /api/pos/orders/{orderNo}/diners`（及 `/cashier/orders/{orderNo}/diners`）
     - **权限**：`cashier:operate|order:operate`
     - **请求体**：
       ```json
       {
         "diners": 6,
         "operator_account": "cashier_01"
       }
       ```
     - **业务规则**：
       - 订单未结账（`unsettled`）时，若门店启用固定人头茶位费或订单已存在茶位费明细，人数调增时自动追加对应份数茶位费；人数调减时冲减对应份数茶位费并重新计算订单金额与桌台金额；已结账或已封账订单禁止修改。
       - 修改成功后通过 `CashierEventWebSocketHub` 广播 `table_order_changed` 事件，协同收银副屏客显与 KDS。
     - **返回示例**：
       ```json
       {
         "code": 200,
         "message": "修改用餐人数成功",
         "data": {
           "order_no": "ORD-20261023-001",
           "number_of_diners": 6,
           "previous_diners": "4",
           "table_number": "A01",
           "amount": 104.0
         }
       }
       ```
  3. `POST /api/pos/tables/batch-clear`（及 `/cashier/table/batch-clear`）
     - **权限**：`cashier:operate|table:operate`
     - **请求体**：
       ```json
       {
         "table_ids": [101, 102, 108],
         "operator_account": "cashier_01"
       }
       ```
       （支持 `table_ids` 或 `table_numbers`）。
     - **业务规则**：
       - 单一事务内处理桌台状态归位（`status -> 0`，`order_no -> null`，`amount -> 0`），完成关联已结账订单收单状态（`order_receiving -> off_order`），写入翻台日志；
       - 若桌台存在未结账订单，则予以拦截并记录到 `failed_table_numbers`。
     - **返回示例**：
       ```json
       {
         "code": 200,
         "message": "批量清台成功",
         "data": {
           "success_count": 3,
           "failed_table_numbers": []
         }
       }
       ```
  4. `GET /api/pos/tables/pulse`（及 `/cashier/table/pulse`）
     - **权限**：`cashier:operate|table:view`
     - **功能**：计算实时经营脉搏指标。
     - **计算口径**：
       - 开台率：`(就餐中桌台数 + 待结账桌台数) / 营业总可用桌台数 * 100%`
       - 在席总额：`SUM(在席消费中的桌台实时消费金额)`
       - 待翻台：已结账但尚未执行清台保洁的桌台数（`status = 2`）
     - **返回示例**：
       ```json
       {
         "code": 200,
         "message": "success",
         "data": {
           "occupancy_rate": 0.5,
           "occupancy_rate_percent": 50.0,
           "active_dining_count": 2,
           "total_tables": 4,
           "available_table_count": 4,
           "total_seated_amount": 200.5,
           "pending_clear_count": 1
         }
       }
       ```

## 统一支付证书凭证上传与付款码（Micropay）凭证体系（v1.2.314 / WI-037）

- **业务背景与解决痛点**：
  收银端微信付款码（Micropay）在执行支付时需要具备独立商户 `apiV2Key` 与双向客户端证书 `clientCertP12Ref`（`apiclient_cert.p12`）。此前系统仅支持 PEM 私钥和平台公钥上传，缺乏 PKCS12（.p12/.pfx）及支付宝（.crt/.pem）上传能力。本方案提供统一凭证上传接口，支持全格式证书与密钥的安全校验、门店隔离存储与商户配置直绑。
- **新增接口**：
  1. `POST /admin/payment/certificate/upload`
     - **参数**：
       - `shopId`（query，可选）：目标门店，不传默认当前门店（总部 0）；
       - `merchantKey`（query，可选，默认 `default`）：商户实例键（如 `default`, `small_amount`）；
       - `type`（query，可选，默认 `AUTO`）：证书类型，支持 `AUTO`, `CLIENT_CERT_P12`, `PRIVATE_KEY`, `PLATFORM_PUBLIC_KEY`, `ALIPAY_ROOT_CERT`, `ALIPAY_APP_CERT`, `ALIPAY_PUBLIC_CERT`；
       - `file`（multipart/form-data，必填）：证书或密钥文件。
     - **权限**：`payment:config:write`。
     - **返回**：`certificateType`, `fileRef`, `filename`, `fileSize`, `shopId`, `merchantKey`，以及兼容别名 `clientCertP12Ref`, `privateKeyRef`, `platformPubKeyRef`。
  2. `POST /admin/payment/merchants/{id}/certificate/upload`
     - **参数**：
       - `id`（path，必填）：商户配置 ID；
       - `type`（query，可选，默认 `AUTO`）：凭证类型；
       - `file`（multipart/form-data，必填）：证书文件。
     - **权限**：`payment:config:write`。
     - **功能**：上传证书并直接绑定至商户对应字段（如 `client_cert_p12_ref`、`private_key_ref`、`platform_pub_key_ref`、`alipay_*_cert_ref`），自动自增凭据版本 `credential_version` 并生成快照，最后重新加载缓存。

## 门店商户多条件可编辑路由规则模块（v1.2.313 / WI-036）

- **业务背景与解决痛点**：
  为满足餐饮门店多商户、多主体灵活分流合规需求（例如：打包/自提订单分流至小额商户、单笔订单金额介于 50~100 元进小额商户、订单包含“三文鱼”特产/生鲜菜品进特产专用商户号等），系统构建了可视化、可配置、多维度组合判定的商户路由引擎。
- **新增管理端接口**：
  1. `GET /admin/payment/routing-rules`
     - **参数**：`shopId`（门店ID，0为全店模板），可选 `channel`（支付渠道，默认 `wechat`）。
     - **权限**：`payment:config:read`。
     - **功能**：查询当前门店配置的商户分流规则列表（按 `priority` 降序排列）；若为分店且启用了全局策略，附带返回继承自总店的只读全局模板列表。同时返回各条规则目标商户的支付就绪状态（`targetMerchantPayReady`）。
  2. `GET /admin/payment/routing-rules/{id}`
     - **权限**：`payment:config:read`。
     - **功能**：获取指定路由规则详情。
  3. `POST /admin/payment/routing-rules`
     - **参数**：`shopId`（门店ID）。
     - **请求体**：
       ```json
       {
         "channel": "wechat",
         "ruleName": "三文鱼生鲜专线商户",
         "priority": 150,
         "enabled": true,
         "targetMerchantKey": "small_amount",
         "matchMode": "ALL",
         "conditions": {
           "diningTypes": ["打包", "自提"],
           "minPaidYuan": 50.00,
           "maxPaidYuan": 200.00,
           "goodsMatch": {
             "goodsNameKeywords": ["三文鱼"],
             "categoryIds": [10, 12],
             "mode": "CONTAINS_ANY"
           },
           "timeRange": {
             "startTime": "10:00",
             "endTime": "22:00"
           }
         },
         "remark": "打包且含三文鱼且金额在50~200元时走小额商户"
       }
       ```
     - **权限**：`payment:config:write`。
     - **功能**：新增商户分流路由规则，入库时自动对 `conditions` 进行语法与维度有效性校验。
  4. `PUT /admin/payment/routing-rules/{id}`
     - **权限**：`payment:config:write`。
     - **功能**：修改路由规则，具备多门店隔离保护（禁止跨店修改）。
  5. `DELETE /admin/payment/routing-rules/{id}`
     - **权限**：`payment:config:write`。
     - **功能**：删除路由规则（具备门店隔离校验）。
  6. `PUT /admin/payment/routing-rules/sort`
     - **参数**：`shopId`，可选 `channel`。
     - **请求体**：`[101, 102, 103]`（规则 ID 数组，排在前面的优先级更高）。
     - **权限**：`payment:config:write`。
     - **功能**：在管理后台拖拽重排后一键批量重置并更新优先级字段 `priority`。
  7. `POST /admin/payment/routing-rules/simulate`
     - **参数**：`shopId`。
     - **请求体**：
       ```json
       {
         "channel": "wechat",
         "paidYuan": 88.00,
         "diningType": "打包",
         "goodsItems": [
           { "goodsId": 1001, "goodsName": "挪威三文鱼刺身", "categoryId": 10, "price": 88.00, "quantity": 1 }
         ]
       }
       ```
     - **权限**：`payment:config:read`。
     - **功能**：规则试算模拟器。根据输入上下文完整模拟路由链决策，返回命中规则 ID、规则名称、目标商户 Key、商户就绪状态、最终生效商户 Key 及若商户凭据未就绪时的自动回退降级说明。
- **多条件匹配引擎维度（PaymentRoutingRuleMatcher）**：
  - **就餐方式（`diningTypes`）**：支持字符串数组（如 `["堂食", "打包", "自提"]`），大小写/空格自愈比对。
  - **实付金额区间（`minPaidYuan` / `maxPaidYuan`）**：闭区间判断。
  - **菜品商品明细（`goodsMatch`）**：
    - `goodsNameKeywords`：菜品名称模糊匹配（如 `["三文鱼"]`）；
    - `goodsIds` / `categoryIds`：菜品 ID 与分类 ID 精确命中；
    - `mode`：`CONTAINS_ANY`（包含任一即可）、`CONTAINS_ALL`（必须包含所有列出的条件项）、`ONLY`（整单内所有菜品必须全部属于该类范围）。
  - **时段控制（`timeRange`）**：`startTime` ~ `endTime`（支持跨午夜，如 `22:00` ~ `02:00`）。
  - **组合关系（`matchMode`）**：`ALL`（AND，配置的所有维度必须同时满足）与 `ANY`（OR，配置的维度满足任一即触发）。
- **资金安全与保底降级机制**：
  - 路由决策以数据库配置为准；
  - 规则命中目标商户后，强制执行 `isMerchantPayReady` 全量就绪性检查（密钥文件存在、私钥可解密、APIv3 Key 解密成功）；
  - 若目标商户配置不完整或损坏，系统记录警告审计日志并平滑降级至默认主商户（`default`），绝不因单商户异常导致点餐或收银支付中断。

## 微信支付平台公钥证书文件上传（v1.2.312 / WI-057）

- **新增接口**：`POST /admin/payment/platform-public-key/upload`（`multipart/form-data`，参数 `file`，可选 `shopId`，可选 `merchantKey`）。
- **权限标识**：`payment:config:write`。
- **能力说明**：接收管理员上传的微信支付平台公钥（`BEGIN PUBLIC KEY`）或 X.509 平台证书（`BEGIN CERTIFICATE`），排斥私钥文件；服务端验证 RSA 算法后保存至门店隔离目录，返回 `platformPubKeyRef` 路径及 `materialType`（`PUBLIC_KEY` 或 `CERTIFICATE`）。客户端在保存商户配置时仅记录路径引用，不直接存 PEM 内容。

## 多门店多商户支付绑定加固（v1.2.311 / WI-030）

- **服务端权威选商户**：JSAPI、Native、MICROPAY 新交易只按订单所属门店、门店商户策略和 `routing_rule_json` 选商户；分流目标商户前置检查 `isMerchantPayReady` 就绪性，凭据未就绪自动降级至默认商户，避免因个别子商户配置损坏阻断支付；没有命中规则时使用服务端 `default` 配置，不再把订单或请求中的客户端 `merchantId` 当作回退路由。交易创建后固化 `merchant_config_id`、`merchant_key` 和 `merchant_config_version`。
- **多实例配置一致性**：新交易解析商户配置时以数据库为准，本机缓存只保存最近读取结果，不再让无 TTL 的 JVM 缓存覆盖配置停用、轮换或退役。支付回调按 `Wechatpay-Serial` 精确查询当前/历史候选配置，避免全表扫描。
- **门店与商户绑定**：查单、关单、撤销、退款和支付成功入账按固化的配置 ID/版本读取当前或历史凭据，并验证配置 `shop_id` 必须等于订单门店或为显式全局模板 `0`。微信支付成功通知（含点餐订单与会员充值）必须包含且匹配 `mchid`、`appid`，且会员充值回调金额执行 `total.equals(expectFen)` 严格比对，缺失或不一致时拒绝入账并记录错误审计。
- **退款回调闭环**：发起微信退款时把商户配置 ID/版本、原微信 `transaction_id`、`mchid` 写入 `t_payment_refund_request`。退款通知只接受已登记的 `out_refund_no`，并逐项核对门店、订单、退款金额、交易号、商户号及配置版本；未知退款单或任一差异返回 `FAIL`，不得通过模糊订单号猜测归属。
- **数据库约束**：Flyway `V033__payment_merchant_binding_hardening.sql` 增加退款绑定字段、回调公钥序列号索引及 `t_order.order_no` 全局唯一约束。上线前必须检查并清理历史重复订单号；发现重复时迁移会有意中止，防止支付回调命中歧义订单。

## 菜品套餐完整商业化运营能力升级（v1.2.310 / WI-033）

- **变更背景与问题解决**：
  此前结构化套餐仅支持基础子菜组合和金额校验，缺乏主流餐饮 SaaS 的商业化运营能力（无单单限购、无用户周期限购、无时段与星期售卖控制、无堂食外卖场景限制、优惠券无法互斥、无划线原价展示、退款未联动子菜等）。
- **主要新增与增强能力**：
  1. **限购与风控管控**：
     - 单笔订单限购（`limit_per_order`）：单笔订单最多允许点选 N 份，超额即时阻断；
     - 用户周期限购（`limit_per_user` + `limit_cycle`）：按用户 `openid` 维度统计周期内（`daily` 当日、`lifetime` 终生）有效订单中的累计购买份数，超额抛出业务拦截提示；
     - 用餐场景限制（`apply_dining_type`）：支持设定 `all`（全部）、`dine_in`（仅限堂食，防止特惠引流套餐被打包带走）、`take_out`（仅限外卖打包）；
  2. **时效与分时段售卖（Dayparting）**：
     - 生效日期范围（`start_time` / `end_time`）：限时促销活动起止时间；
     - 适用星期控制（`available_days`）：如 `1,2,3,4,5` 表示仅限工作日售卖，周末自动提示不可售；
     - 每日售卖时段（`time_range_start` / `time_range_end`）：如 `11:00` 至 `14:00`，未到时段或已过时段均优雅提示；
  3. **优惠券互斥控制（`allow_coupon`）**：
     - 套餐配置 `allow_coupon = 0` 时，下单使用全场满减券/折扣券时，该套餐金额**不计入优惠券可用门槛与打折基数**，杜绝“折上折”造成的商家毛利倒挂；
  4. **营销展示与划线原价**：
     - 小程序详情（`GET /combo/detail`）自动根据各固定子菜及默认可选菜门店价汇总计算门市原价 `originalPrice` 与立省金额 `savedAmount`，并返回 `isAvailableNow` 标识；
  5. **售后退款级联**：
     - 后台/收银整行退套餐头（`combo_header`）时，自动级联将同单同套餐实例（`combo_instance_id`）下的所有子菜明细（`combo_component`）一并退菜并作废 KDS，确保库存与厨房出餐口径一致。
- **涉及端点**：
  - `POST /admin/combo/save`：请求体支持 `limitPerOrder`, `limitPerUser`, `limitCycle`, `applyDiningType`, `allowCoupon`, `dailyStock`, `startTime`, `endTime`, `availableDays`, `timeRangeStart`, `timeRangeEnd`。
  - `GET /admin/combo/getByDishId`：返回结构体内增加上述商业化字段。
  - `GET /combo/detail`：返回结构体补充 `originalPrice`, `savedAmount`, `isAvailableNow` 及商业化限制字段。
  - `POST /order/add`、`POST /order/addDishes`：下单与加菜流程自动执行商业化限购与时段核验。

## 客户端版本管理安装更新包与下载升级（v1.2.311 / WI-038）

### 1. 客户端安装包上传与元数据推断
- **端点**：`POST /admin/app/version/upload`（限 `admin:super` 权限，`multipart/form-data`）
- **功能说明**：支持管理后台直接上传客户端安装更新包（`.exe`, `.msi`, `.apk`, `.zip`, `.dmg`, `.pkg`, `.deb`, `.rpm`, `.AppImage`, `.wgt`）。
- **服务端自动化处理**：
  1. **安全校验与落盘存储**：严格校验后缀白名单，杜绝危险脚本；支持自动在 `appPackagesFilePath` 与工作区多目录智能降级容错。
  2. **SHA-256 签名计算**：流式计算文件 SHA-256 哈希值，直接用于客户端版本升级防篡改验签。
  3. **真实文件大小统计**：提取精确字节数（`fileSize`），自动赋给版本策略。
  4. **包类型智能推断**：根据文件扩展名自动识别 `exe`, `apk`, `zip`, `msi`, `dmg` 等包体类型。
  5. **下载直链生成**：自动组装可供外网下载的完整直链（`${publicBaseUrl}/admin/app/packages/${subPath}`），原生适配 Nginx `/admin/` 代理通道，杜绝前端 SPA `try_files` 回退为 HTML 造成的假 200 哈希校验异常。

### 2. 客户端安装包流式下载与断点续传
- **端点**：`GET /admin/app/packages/**` 及 `/packages/**`（免签放行）
- **功能说明**：支持客户端流式下载安装包，支持多物理目录搜索（`appPackagesFilePath` 与 `user.dir/upload/packages`），强制输出 `application/octet-stream` 二进制头与 `Content-Disposition` 附件头，并支持 HTTP 206 Partial Content 断点续传。

### 3. 安装包直链公网连通性与 SHA-256 远端验证
- **端点**：`POST /admin/app/version/verify-url`（限 `admin:super` 权限，`application/json`）
- **请求体**：
  - `downloadUrl`（必填，字符串）：待检测的下载直链地址。
  - `expectedSha256`（可选，字符串）：期望比对的 SHA-256 散列值。
- **返回结构**：
  - `statusCode`：远端 HTTP 状态码（200 为正常）。
  - `contentType`：响应媒体类型（若为 `text/html` 将触发预警）。
  - `fileSize`：实际下载内容字节数。
  - `isHtmlFallback`：是否命中 Nginx SPA HTML 假响应。
  - `actualSha256`：远端文件的真实 SHA-256 散列值。
  - `hashMatched`：是否与 `expectedSha256` 完全匹配。
  - `warning`：诊断预警说明。

## 收银挂单与厨房等叫业务完善与商用优化（v1.2.308 / WI-031）

### 1. 厨房 KDS 等叫/起菜全流程安全加固
- **接口**：`POST /kds/workflow/hold` 与 `POST /kds/workflow/release`（以及 `/kds/v2/commands` 的 `hold_item` / `release_item`）
- **多门店严格隔离**：服务端在执行等叫/起菜前，通过菜品明细 `detail_id` 关联反查订单归属门店，严格核验 `order.shop_id == currentDevice.shop_id`（兼容总店未分配老数据），杜绝跨店横向越权。
- **状态防呆校验**：已退菜品（`refunded`）或已出餐完成的菜品（工单已达 `item_status == 2` 或已传菜数量达到明细数量）禁止设为等叫，防止厨师误操作与生产流程混淆。

### 2. 前台收银「挂单 / 取单」全流程商用闭环
- **实体与数据表扩展（Flyway V032）**：`t_order` 新增 `hang_status`（0未挂单/1挂单中）、`hang_time`（挂单时间）、`hang_reason`（挂单原因/备注）、`hang_admin_id`（操作员 ID）。
- **挂单接口加固（`POST /cashier/order/hang`）**：
  - 必须提供 `order_no`，可选 `reason`（挂单原因）；
  - 强制校验门店上下文与归属；严格拦截已结账（`success`）或已取消（`cancelled`）单据；
  - 写入挂单状态、时间与操作员，记录 `@AuditLog` 审计日志及订单变更日志。
- **新增取单接口（`POST /cashier/order/unhang`）**：
  - 收银员取回挂起订单时调用，复位 `hang_status = 0`，记录取单审计日志，返回最新单据状态以便收银端拉起结算。
- **新增挂单池列表查询（`GET /cashier/order/hang-list`）**：
  - 查询当前门店处于挂单状态的所有未结订单（按挂单时间升序），返回单号、桌号、用餐人数、金额、挂单时长（分钟）、挂单原因及操作人。
- **结账与取消生命周期联动**：收银结账成功（`CashierCheckoutService`）或整单取消时，自动清除挂单标记，避免已结订单在挂单池残留。

## 营业日结报告新增会员多店数据隔离（v1.2.307 / WI-030）

- **端点**：`GET /admin/report/daily`（营业日报商业级 8 维度全量日结报表）
- **变更背景**：
  在连锁多门店运营场景下，`GET /admin/report/daily?detail=true` 的会员维度（`report.member.newMembers`）此前直接通过 `QueryWrapper<User>` 查询全局 `t_user`（`phone IS NOT NULL AND TRIM(phone) != '' AND time BETWEEN start AND end`），缺乏门店隔离。导致分店（如西二旗店）在生成日结营业报表时，将全平台其他门店（如总店、朝阳分店）新注册绑手机会员全部混入，造成分店新增会员虚高。
- **隔离与防护方案**：
  1. **多维度门店上下文子查询过滤**：
     由于 `t_user` 表为全平台会员基表（无物理 `shop_id` 列），会员与门店的关联通过交易订单（`t_order`）、储值记录（`t_member_recharge`）以及分店会员钱包（`t_shop_member_wallet`）建立。
     当报表在门店上下文（`shopId != null`）下生成时，`AdminReportController.countShopNewMembers` 自动对 `QueryWrapper<User>` 附加多表联合存在性子查询条件：
     - `u.openid IN (SELECT openid FROM t_order WHERE ...)` OR
     - `u.openid IN (SELECT pay_openid FROM t_order WHERE ...)` OR
     - `u.id IN (SELECT user_id FROM t_member_recharge WHERE ...)` OR
     - `u.openid IN (SELECT openid FROM t_member_recharge WHERE ...)` OR
     - `u.id IN (SELECT user_id FROM t_shop_member_wallet WHERE ...)`
  2. **历史老数据向下兼容**：
     当 `shopId == 1`（总店）时，订单与储值历史老数据中可能存在 `shop_id IS NULL` 的记录，条件采用 `(shop_id = 1 OR shop_id IS NULL)` 兼容历史总店存量会员。
  3. **总部全局聚合保持透明**：
     当无单店上下文（总部全平台视角 `shopId == null`）时，保留全量有效新会员全局统计，不附加子查询过滤。

## 营业日报挂账与实际收款口径修复（v1.2.306 / WI-029）

- `GET /admin/report/daily?detail=true` 在保留既有字段的基础上新增 `receivableSummary`、`totalCollectionsFen` 和 `totalCollections`。`receivableSummary` 包含新增挂账、应收回款、坏账核销、挂账撤销、期末应收余额和应收流水截止水位，金额字段以分为单位。
- `netRevenue`/`netSales` 表示净销售额，包含挂账销售；`totalCollections` 表示真实收款合计，即支付流水净额、应收回款和会员充值本金之和。支付渠道明细不包含新增挂账。
- 日结打印将原“净营业实收”更正为“净销售额”，并独立显示实际收款及挂账应收摘要；Z 报表异常降级时不再把挂账订单金额归入支付渠道。
- 日报 CSV 保留原 7 列并在尾部追加 `receivable_charged_amount`、`receivable_collected_amount`、`receivable_writeoff_amount`、`receivable_reversed_amount`，单位为元。
- Flyway `V031__daily_close_receivable_reversal.sql` 为不可变日结快照补充 `receivable_reversed_fen`，确保历史 Z 报表不会丢失挂账撤销金额。

## 版本管理接口权限映射修复（v1.2.305 / WI-028）

- 修复 `GET /admin/app/versions` 在到达 Controller 前返回 `code=403, msg="接口权限未配置"`：统一权限映射及数据库权限种子此前遗漏了版本管理路由。
- `GET /admin/app/versions`、`POST /admin/app/version/save`、`POST /admin/app/version/toggle-enabled`、`DELETE /admin/app/version/{id}` 统一要求 `admin:super`；Controller 内部仍保留二次校验。
- 数据库通过 `V030__admin_app_version_permissions.sql` 幂等补齐映射。部署新 JAR 并完成 Flyway V030 后生效；非超级管理员仍返回 403。

## 商户、挂账与权威资金闭环集成（v1.2.303 / WI-027）

- 修复集成/部署版本缺少挂账 Controller 导致 `GET /cashier/receivables/eligible-accounts` 返回 Spring 404：当前构建已包含完整收银挂账 Controller、`receivable:view` 权限映射、门店隔离服务和 OpenAPI 契约。没有符合条件的授信账户时返回 `code=0, accounts=[]`，不是 404。
- 为避免与既有会员钱包和版本中心迁移冲突，支付商户商业化、应收账款、JSAPI 支付尝试三份迁移在集成分支依次使用 `V027__payment_merchant_commercialization.sql`、`V028__receivables_system.sql`、`V029__wechat_jsapi_payment_attempt.sql`。
- 本地集成和 JAR 构建不代表线上已发布；生产环境必须部署本次生成的 JAR 并让 Flyway 成功执行 V027~V029 后，才可验证该路由和挂账数据能力。

## 门店销售产品明细与日报菜品排行多店数据隔离（v1.2.304）

- **背景与问题**：
  在多商户/多门店运营场景下，门店后台日报（`GET /admin/report/daily`）的“热销菜品排行榜”（`topDishes` / `dishRanking`）以及相关菜品销售统计在底层通过 `OrderMapper.xml` 的 `statisticsDishSales` 进行聚合统计。
  因 Java 端传入 Map 参数键名使用了下划线格式 `dishParams.put("shop_id", shopId)`，而 MyBatis 动态 SQL `<if test="shopId != null">` 仅对驼峰键 `shopId` 生效，导致 MyBatis 动态 SQL 中 `AND o.shop_id = #{shopId}` 判定失败被静默略过，从而在多门店环境下聚合了全平台所有门店的菜品销量，混入了非本店数据。
- **加固与修复方案**：
  1. **Java 服务层双键注入**：
     - `AdminReportController`（`buildStandardDailyReport` 与 `dishRanking`）在组装菜品统计参数 Map 时，同步注入 `shopId` 与 `shop_id`，确保无论上游是驼峰还是下划线命名规范均能精准传递门店上下文。
     - 同时显式覆盖 `dishRanking` 接口，在入参带 `shopId` 或管理员受限门店范围时，注入过滤参数，防止横向越权查阅他店菜品排行。
  2. **MyBatis 映射层双兼容容错守卫**：
     - 在 `OrderMapper.xml` 中对所有涉及门店维度的 Map 查询进行防御性双键支持：
       - `statisticsDishSales`（菜品销售排行与明细统计）
       - `statisticsCategorySales`（分类销售统计）
       - `statisticsOrderSummary`（订单汇总统计）
       - `listDishDowDemandStats` / `listDishActualQtyForShopDay` / `countSuccessOrdersForShopDay` / `sumAllDishQtyForShopDay`（智能备料需求预测与备料模型统计）
       - `list` / `getTotal` / `countByTimeRange`（订单列表与时间范围订单统计）
     - 采用如下安全条件判定模式：
       ```xml
       <if test="shopId != null">
           AND o.shop_id = #{shopId}
       </if>
       <if test="shopId == null and shop_id != null">
           AND o.shop_id = #{shop_id}
       </if>
       ```
  3. **数据隔离成效**：
     - 单店店长与门店管理员查阅营业日报与菜品排行时，数据严格约束在当前门店范围内，彻底杜绝多门店菜品排行混入。
     - 超级管理员跨店报表与全链统计不受影响（未传 `shopId`/`shop_id` 时正常统计全平台）。

## 跨平台版本更新控制中心升级（v1.2.302）

- **端点**：`GET /admin/app/version`（查询 APP/客户端版本策略与升级决断）
- **适用平台**：`windows`（收银桌面端）、`desktop`、`android`（移动管理端/商米POS）、`ios`（苹果移动端）、`pos_sunmi`。
- **设计目标**：
  1. **平台全面支持**：彻底解除旧版本仅允许 `android`/`ios` 的限制，全面支持 Windows 收银端、桌面端、Android 手机/POS 以及 iOS 移动端版本管理。
  2. **服务端升级决断引擎**：客户端上报当前版本号（`current_version`）或构建号（`version_code`），由服务端基于精确语义化版本比较（`SemVer`）统一裁决是否升级（`hasUpdate`）及升级级别（`upgradeType: NONE / OPTIONAL / FORCE`）。
  3. **分平台安装模式自适应**：
     - **Windows / POS 桌面端**：默认下发 `silent`（静默下载、后台 SHA-256 校验并静默安装），无需人工干预收银终端。
     - **Android 移动端**：默认下发 `interactive`（弹窗提示并调用系统 PackageInstaller 交互安装）。
     - **iOS 移动端**：强制下发 `store_redirect`（跳转苹果 App Store 官方下载页）。
  4. **包体完整性与灰度控制**：
     - 新增 `sha256` 散列校验码与 `file_size` 字节数，杜绝客户端遭遇网络劫持或下载残损安装包。
     - 支持 `gray_shop_ids` 灰度门店列表与通用兜底策略，支持指定分店先行灰度试运行。
- **请求参数**：
  - `platform`（string, 必填）：`android`、`ios`、`windows`、`desktop`、`pos_sunmi` 等（支持大小写及 `win`/`win32`/`win64`/`apple` 别名自动归一）。
  - `channel`（string, 可选）：渠道标识。Windows 默认 `pos`，移动端默认 `mobile`；Windows 未找到自定义渠道时自动安全回退至 `pos`。
  - `current_version` / `currentVersion`（string, 可选）：客户端当前语义化版本号，如 `2.0.0`。
  - `version_code` / `versionCode`（integer, 可选）：客户端当前内部构建版本代码，如 `200`。
  - `shop_id` / `shopId`（integer, 可选，或通过请求头 `X-Shop-Id`）：当前终端绑定的门店 ID，用于灰度版本准入判定。
- **响应结构（`data`）**：
  - `platform`（string）：归一化平台标识。
  - `channel`（string）：生效渠道标识。
  - `latest`（string）：最新发布版本号。
  - `versionCode`（integer）：最新版本代码构建号。
  - `minSupported`（string）：最低支持版本号。
  - `forceUpdate`（boolean）：策略配置是否为强更。
  - `hasUpdate`（boolean）：服务端决断结果，是否需要更新。
  - `upgradeType`（string）：升级级别（`NONE` 无需更新 / `OPTIONAL` 提示更新 / `FORCE` 强制更新）。
  - `installMode`（string）：安装执行模式（`silent` 静默安装 / `interactive` 交互安装 / `store_redirect` 跳转应用市场）。
  - `packageType`（string）：安装包类型（`full` 全量包 / `wgt` 补丁 / `exe` / `msi` / `apk`）。
  - `fileSize`（integer, 可空）：安装包字节大小。
  - `sha256`（string, 可空）：安装包 SHA-256 完整性哈希校验值。
  - `releaseNotes`（string）：版本更新说明。
  - `downloadUrl`（string）：安装包下载地址或 App Store 链接。
- **向下兼容说明**：老版本客户端调用未携带 `current_version` 时，保持老接口行为（`hasUpdate=true`，按策略 `force_update` 决断 `upgradeType`），老客户端无缝兼容。

### 超级管理员专属版本管理与发布控制（v1.2.303）

- **权限约束**：以下发版与策略管控端点**必须拥有精确权限码 `admin:super`（超级管理员）**，非超管调用直接返回 HTTP 403 `{"code": 403, "msg": "无权限：admin:super"}`。
- **端点列表**：
  1. `GET /admin/app/versions`：获取全平台客户端版本策略列表，返回全量策略数组。
  2. `POST /admin/app/version/save`：发布或修改版本策略。
     - 请求体：`platform`（必填）、`channel`（可选，默认 pos/mobile）、`latest`（必填，SemVer 规范）、`version_code`（构建号）、`min_supported`（最低兼容版本）、`force_update`（0/1）、`package_type`（full/patch）、`install_mode`（silent/interactive/store_redirect）、`file_size`、`sha256`、`gray_shop_ids`（逗号分隔的门店 ID 字符串，如 `1,2`）、`release_notes`、`download_url`、`enabled`（0/1）。
     - 服务端强校验 SemVer 规范及平台合法性，自动幂等插入或更新策略。
  3. `POST /admin/app/version/toggle-enabled`：启用/停用特定策略。
     - 参数：`id`（long, 必填）、`enabled`（0 或 1）。
  4. `DELETE /admin/app/version/{id}`：删除特定版本策略。


## 结构化套餐全链路门店隔离与继承契约（v1.2.332 / WI-070）

- **端点**：
  - `GET /admin/combo/getByDishId`（管理端查询套餐定义，支持门店隔离与总部模板回退）
  - `POST /admin/combo/save`（管理端保存套餐定义，支持门店隔离保存与防跨店覆盖）
  - `GET /dish/getAllDish`（C端/收银端按门店获取菜单并挂载门店专属套餐定义）
  - `GET /combo/detail`（C端/收银端套餐选规格详情）
- **变更背景与痛点消除**：
  - 过去 `t_combo` 缺少 `shop_id` 字段且具有全局唯一索引 `uk_combo_dish (dish_id)`；
  - 门店后台新建菜品若同名会复用 `dish_id`；
  - 保存套餐时执行全局 `deleteById` 硬删除，导致同名套餐在不同门店配置时发生相互覆盖与数据踩踏，甚至引发跨店子菜不存在导致下单失败；
- **契约行为规范**：
  1. **数据模型升级**：`t_combo` 增加 `shop_id INT NOT NULL DEFAULT 0`，复合唯一索引变更为 `uk_combo_dish_shop (dish_id, shop_id)`。`shop_id = 0` 代表总部通用模板，`shop_id > 0` 代表门店专属套餐；
  2. **两级回退查询**：
     - 当传入门店上下文（`shopId > 0` 或 `X-Shop-Id` 头）时，`GET /admin/combo/getByDishId` 与 `GET /combo/detail` 优先读取当前门店专属套餐；
     - 若当前门店尚未自定义该套餐，无缝回退继承总部模板（`shop_id = 0`）；
  3. **门店独立保存与防跨店覆盖**：
     - `POST /admin/combo/save` 接收 `shopId`（或自动由 `X-Shop-Id` 头解析）；
     - 仅删除并重写当前目标门店自身 `(dish_id, shop_id)` 的套餐记录及其子项，**严禁物理删除其他门店或总部的套餐记录**；
     - 门店管理员越权操作非授权门店时由 `AdminShopScopeGuard` 拦截并返回 `code=4003`；
  4. **点餐与下单端门店闭环**：
     - 小程序与收银端点餐页（`GET /dish/getAllDish`）根据解析后的门店 `shop_id` 挂载门店专属套餐；
     - 下单与加菜展开套餐行时按订单 `shop_id` 解析套餐及子菜。

## 日结与营收报表支付渠道纳入挂账（应收账款）渠道（v1.2.331）

- **端点**：
  - `GET /admin/daily/context`（日结上下文与实时汇总）
  - `GET /admin/daily/pre-check`（日结预检，`preview.channels`）
  - `POST /admin/daily/close`（正式执行日结，持久化 `channel_breakdown_json`）
  - `GET /admin/daily/byChannel`（按支付渠道统计营收金额）
  - `GET /admin/daily/income`（结算日营收详情）
- **变更背景与痛点**：
  - 餐饮营业场景中，部分客户消费采用“挂账”（签单/应收账款）结算。
  - 之前挂账订单未写入即时资金流水 `t_payment_ledger`（因挂账代表应收债权产生，未发生即时资金实收），但日结接口的渠道汇总（`channels`、`channel_details`、`preview.channels`、`byChannel`）此前仅从 `t_payment_ledger` 中抽取渠道。
  - 导致日结中的支付渠道明细中缺失“挂账”渠道，造成各支付渠道汇总金额与当日净销售额（`net_sales`）不平（差额恰好为挂账订单金额）。
- **规则与财务不变性**：
  1. **销售额口径（`net_sales_fen` / `total_sales_fen`）**：
     - 反映营业日内的全部销售产出（含微信、支付宝、现金、会员余额及挂账消费）。
     - 所有支付与结算渠道汇总（微信 + 支付宝 + 现金 + 会员余额 + 挂账）与 `net_sales` 保持严格勾稽平账。
     - 日结渠道明细中统一包含挂账渠道：`code: "receivable"`, `label: "挂账"`, `amount_fen: 挂账实收净额`, `success_count: 挂账笔数`。
  2. **实收资金口径（`total_collections_fen`）**：
     - 反映当日实际收到的资金总额（资金流水净额 + 挂账实际回款金额 + 会员储值实付本金）。
     - 挂账消费代表尚未收回现金的应收款，严格禁止计入当日实收资金（仅在后续通过应收款回款接口 `ReceivableService.collect` 回款时计入回款当日资金实收），杜绝现金实收虚增与重复入账。
  3. **历史已日结快照兼容**：
     - `GET /admin/daily/context` 读取历史已日结快照时，若该快照存在挂账消费（`receivable_charged_fen > 0`）且快照 JSON 中历史未包含挂账渠道，接口动态补充挂账渠道明细与渠道金额，保证前端展示完整。

## 会员接口全链路门店隔离（v1.2.330）

- **端点**：
  - `POST /admin/order/getUserInfo`（管理端/收银端会员列表与统计分页）
  - `POST /admin/order/getAllUser`（管理端用户列表分页）
  - `POST /admin/member/list`、`GET /admin/member/list`（收银端与运营端会员列表统一别名）
  - `GET /admin/member/stats`（会员看板统计数据）
  - `GET /admin/member/consumption`（会员消费流水记录）
  - `GET /admin/member/profile`（会员画像与消费统计）
  - `GET /admin/member/persona-tags`（会员大数据智能画像标签推荐）
  - `GET /admin/user/sevenDays`、`GET /admin/user/lastMonth`、`GET /admin/user/thisMonth`、`GET /admin/user/scope`、`POST /admin/user/scope`（按时间周期统计用户）
- **变更背景与痛点**：
  - 之前会员列表（`getUserInfo`、`getAllUser`）与统计接口默认全量拉取全连锁所有会员，缺乏门店维度的筛选与数据隔离。
  - 门店收银台与单店运营后台只能查看本店相关会员，不能跨店泄露全平台顾客隐私。
- **门店会员权威判定口径**：
  - 会员（`phone IS NOT NULL AND TRIM(phone) != ''`）属于指定门店（`shopId`）当且仅当满足以下任一条件：
    1. 在本店有消费订单（`t_order.shop_id = :shopId`，匹配 `openid` 或 `pay_openid`）；
    2. 在本店有充值记录（`t_member_recharge.shop_id = :shopId`，匹配 `user_id` 或 `openid`）；
    3. 在本店拥有专属储值钱包（`t_shop_member_wallet.shop_id = :shopId`，匹配 `user_id`）；
    4. 1号店（主店/总店）兼容历史未标记门店的旧数据（`shop_id IS NULL`）。
- **隔离与防护机制**：
  1. **会员查询与列表分页**（`getUserInfo`、`getAllUser`、`/admin/member/list`）：
     - 支持请求体或参数传 `shopId`，或自请求头 `X-Shop-Id` 自动解析目标门店。
     - 底层 Mapper（`userStatsWhere`、`userListLightWhere`）及 Service（`applyShopMemberFilter`）通过多表联合子查询严格过滤本店会员。
     - 指定门店查询时，会员消费统计（`consume_amount`/`last_consume_time`）自动限定本店范围。
  2. **会员看板与时段统计**（`stats`、`sevenDays` 等）：
     - `GET /admin/member/stats` 统计本店去重会员总数（`memberCount`）及今日新增属于本店的会员数（`todayNewCount`）。
     - `sevenDays`、`lastMonth`、`thisMonth`、`scope` 统计接口均支持 `shopId` 门店过滤。
  3. **越权防护与总部透传**：
     - 单店账号跨店查询受 `AdminShopScopeGuard` 强制校验，非本店 ID 返回 `code=4003`。
     - 总部超级管理员可显式传入 `allShops=true` 进行全连锁全量查询。

## 会员接口仅返回绑定手机号的有效会员（v1.2.301）

- **端点**：
  - `POST /admin/order/getUserInfo`（管理端用户/会员列表分页）
  - `POST /admin/order/getAllUser`（管理端所有用户/会员列表分页）
  - `POST /admin/order/getOneUserInfo`（按 openid 查询单个用户/会员详情）
  - `GET /admin/member/stats`（会员看板统计数据）
  - `GET /admin/user/sevenDays`、`GET /admin/user/lastMonth`、`GET /admin/user/thisMonth`、`GET /admin/user/scope`、`POST /admin/user/scope`（按时间周期统计用户）
  - `GET /admin/report/dashboard`（运营总看板中的今日新增会员统计）
- **变更背景与口径定义**：
  - **业务痛点**：微信小程序访客首次扫码进入系统仅凭 `openid` 记录到 `t_user`，未完成微信手机号授权/绑定的用户属于匿名访客，不应作为正式会员呈现在会员列表及统计中。
  - **有效会员权威判定口径**：`phone IS NOT NULL AND TRIM(phone) != ''`。
- **调整说明**：
  1. **用户/会员列表过滤**（`getUserInfo`、`getAllUser`）：
     - 查询逻辑与 Mapper（`userStatsWhere`、`userListLightWhere`、`getAllUsers`、`pageUserList`）强制追加 `u.phone IS NOT NULL AND TRIM(u.phone) <> ''` 过滤条件。
     - 过滤未绑定手机号的访客记录，保证返回列表及分页总数 `total` 均为绑定手机号的有效会员。
  2. **单个用户详情查询**（`getOneUserInfo`）：
     - 当传入 openid 对应的记录未绑定手机号或手机号为空时，拒绝作为会员返回，明确返回 `code=500, msg="用户未注册或非有效会员（未绑定手机号）"`。
  3. **会员看板统计**（`GET /admin/member/stats`）：
     - 全部门店/总部视角：会员总数 `memberCount`、今日新增会员数 `todayNewCount`、储值总额与积分总额均仅统计有效会员（绑定手机号）。
     - 门店视角：本店到店会员数与今日到店会员数增加子查询约束，仅统计具有有效手机号的会员订单。
  4. **时间周期用户统计与报表**：
     - `selectSevenDaysUser`、`selectLastMonthUser`、`selectThisMonthUser`、`selectScopeUser` 及报表中的新增会员统计统一收敛为绑定手机号的有效会员。

## 会员充值记录返回接口补全会员手机号（v1.2.300）

- **端点**：
  - `GET /admin/member/recharge/list`（管理端会员充值流水列表）
  - `GET /admin/report/recharge/list`（运营报表端充值流水列表）
  - `POST /order/rechargeHistory`（C 端小程序会员充值记录）
- **变更背景与实现机制**：
  - **业务需求**：会员充值记录返回接口必须返回会员手机号。
  - **数据层扩展**：`MemberRecharge` 实体扩展 `@TableField(exist = false) private String phone;`，作为视图层字段输出，不影响底层物理表。
  - **批量补全机制**：在 `IMemberRechargeService` 中新增 `attachMemberPhones(List<MemberRecharge> records)` 方法。获取充值记录分页数据后，聚合流水的 `user_id` 与 `openid` 批量回表 `t_user` 获取会员手机号，并补全至记录的 `phone` 字段中返回。

## 今日概览看板充值金额口径修正（v1.2.299）

- **端点**：`GET /admin/report/dashboard`
- **口径调整与字段定义**：
  - **业务调整**：今日概览看板数据返回中的充值金额只算本金。
  - **字段口径说明**：
    - `todayMemberRechargeAmount`：**当前营业日成功充值实付本金合计**（严格取 `recharge_amount` 汇总，不再包含赠送金）。
    - `todayMemberRechargePrincipal`：当前营业日成功充值实付本金合计（`recharge_amount` 汇总）。
    - `todayMemberRechargeGift`：当前营业日成功充值赠送金额合计（`gift_amount` 汇总）。
    - `todayMemberRechargeTotal`：当前营业日成功充值入账总额合计（`total_amount` 汇总，含本金+赠送额）。
    - `todayMemberRechargeSuccessCount`：当前营业日成功充值流水笔数。

## 多门店会员隔离与跨店储值清算架构（v1.2.298）

### 阶段一：多门店边界隔离与审计加固
1. **后台会员人工充值（`POST /admin/member/recharge`）**：
   - 权限拦截与越权防护：使用 `adminShopScopeGuard.resolveTargetShopId` 进行门店数据范围校验。单店管理员若传入其他门店 ID 或请求头不一致，直接阻断（`code=4003`）；充值必须明确归属门店。
   - 资产记账：成功充值后，同步记录全局钱包与对应门店分店钱包（`t_shop_member_wallet`），并记录审计日志。
2. **后台扣减余额（`POST /admin/member/balance/deduct`）**：
   - 扣减原因必填：必须传 `reason`（或 `remark`），未传或为空直接阻断（`code=500, msg="扣减原因不能为空"`）。
   - 门店边界强校验：必须携带有效门店上下文（`X-Shop-Id` 或 `shop_id`），非总部管理员跨店直接返回 `code=4003`。
   - 跨店余额规则约束：若当前门店关闭跨店余额使用，强校验顾客在该门店的可用储值余额是否充足，不足阻断。
   - 负向充值审计流水闭环：扣减成功后调用 `memberRechargeService.recordAdminSuccess` 写入负数充值流水（`amount.negate()`），包含操作员、门店 ID、用户 ID、openid 及扣减原因。
3. **后台手动加积分（`POST /admin/order/addPoints`）**：
   - 门店上下文约束：必须明确归属门店（通过请求头 `X-Shop-Id` 或请求体 `shop_id` / `shopId`），缺失返回 `code=4001, msg="必须在指定门店上下文下执行加积分操作"`。
   - 安全审计日志：记录包含 `adminId`、`shopId`、`openid`、`points` 的安全日志。
4. **用户列表与统计隔离（`POST /admin/order/getUserInfo`）**：
   - 支持 `storeOnly=true` 参数；门店角色管理员访问时自动生效 `storeOnly=true` 与 `includeStats=true`。
   - 数据边界：仅展示在当前门店产生消费记录的会员及当前门店维度的累计消费金额。
5. **会员统计数据隔离（`GET /admin/member/stats`）**：
   - 支持参数 `shopId` 与 `allShops`。
   - 门店维度统计：按当前门店统计会员总数（去重消费顾客）、今日新增会员数、门店专属会员储值余额总和（来自 `t_shop_member_wallet`）、门店订单产生积分总和。

### 阶段二：单店与连锁共存跨店余额与清算对账架构
1. **门店跨店储值余额开关配置**：
   - `GET /admin/config/member-balance-cross-shop`：查询当前门店是否开启跨店使用会员余额（`enabled: boolean`，默认连锁模式 `true`）。
   - `PUT /admin/config/member-balance-cross-shop`：更新跨店配置（请求体 `{ "enabled": true/false, "shop_id": 1 }`）。开启为连锁模式，关闭为单店独立模式。
2. **结账与消费强拦截（收银端、小程序 C 端、支付门面）**：
   - 涉及流程：`CashierCheckoutService.checkout`、`OrderController.payByBalance`、`PaymentFacadeService.payByBalance`。
   - 单店模式强拦截：若门店跨店余额关闭（单店模式），系统核查顾客在本店的储值钱包余额（`ShopMemberWallet`）。若本店储值不足，直接阻断支付并返回友好错误：`code=500, msg="本店会员储值余额不足（您在其他门店的充值余额不可跨店使用）"`。
   - 跨店连锁模式扣减与资金清算：优先扣减当前消费门店本地的储值钱包；不足部分按充值时间先后顺序跨店扣减其他门店储值钱包，并写入跨店对账清算记录（`t_member_cross_shop_clearing`）。
3. **跨店结算清算报表（`GET /admin/report/member/cross-shop-clearing`）**：
   - 查询跨店储值消费与资金结算流水。
   - 请求参数：`startTime`、`endTime`、`shopId`（当前店）、`sourceShopId`（原充值店）、`consumeShopId`（实际消费店）、`page`、`pageSize`。
   - 响应数据：包含流水明细列表（消费订单号、用户 ID、充值源门店、消费门店、本金、赠送金、合计金额、清算状态）以及按门店汇总的跨店结算统计矩阵（各店代收/代付清算对账汇总）。

## 收银台修改订单用餐人数接口（v1.2.297）

- **业务背景与目标**：
  - 允许收银员在结账前后根据现场实际就餐人数修正订单人数（`t_order.number_of_diners`），确保后台客单价、人均消费（人均 = 净营收 / 总就餐人数）等经营分析数据精确。
- **接口端点**：
  - `POST /cashier/order/updateDiners`（收银机端首选）
  - `POST /admin/order/updateDiners`（运营管理端代理同等能力）
- **权限与上下文**：
  - 需要登录凭据（`Authorization: Bearer <token>`）及当前门店上下文（`X-Shop-Id`）。
  - 要求权限码 `cashier:operate`（或管理端 `order:operate`）。
  - 支持收银端幂等机制（携带请求头 `X-Client-Request-Id`）。
- **请求参数**：
  - `orderNo` / `order_no`（字符串，与 `orderId` 二选一）：订单编号。
  - `orderId` / `order_id` / `id`（整数，与 `orderNo` 二选一）：订单主键 ID。
  - `number_of_diners`（整数，兼容别名 `numberOfDiners`、`diners`、`numberOfPeople`、`number_of_people`）：修改后的就餐人数，必须为 `1 ~ 999` 之间正整数。
- **业务状态校验守卫**：
  1. **未结账订单（`unsettled`）**：随时允许修改。
  2. **已结账订单（`success`）**：允许在当日营业日内修正。但在执行前强校验订单所属营业日是否已完成日结封账（`DailyCloseSnapshot` 处于 `CLOSED` 或已生成 `DailyStat`）。若已封账，强行阻断：`code=40936, msg="该订单所属营业日(yyyy-MM-dd)已完成日结封账，禁止修改用餐人数"`，保护封账数据不可变。
  3. **已作废/已关闭订单（`cancelled` / `closed`）**：直接阻断：`code=4003, msg="已作废或已关闭订单不允许修改用餐人数"`。
  4. **越权门店校验**：订单不存在或不属于当前门店返回 `code=404, msg="订单不存在或不属于当前门店"`。
- **审计日志**：
  - 写入操作审计日志：`logOrder(orderNo, "update_diners", "admin_id", operatorId)` 及 `@AuditLog(action="cashier_update_diners")`。
- **响应格式**：
  ```json
  {
    "code": 0,
    "msg": "修改用餐人数成功",
    "order_no": "ORD20261016001",
    "number_of_diners": 4,
    "previous_diners": "2"
  }
  ```

## 收银端套餐商业化规则豁免说明（v1.2.308）

- **收银端开单与加菜豁免套餐限制**：
  - 收银机端开单（`POST /cashier/order/quickOrder`）与加菜（`POST /cashier/order/addDishes`）全面豁免套餐商业化运营规则限制（单单限购、单人周期限购、可用星期、可用时段、用餐方式限制及活动生效起止日期），仅保留套餐存在且未停用校验（`status != 0`）。
  - C 端顾客通过微信小程序自助点餐（`POST /order/create`、`POST /order/addDishes`）依然严格校验全部套餐商业化限制。

## 商业化营业与收银闭环业务逻辑审计优化（v1.2.296）

- **未营业状态入口强拦截**：
  - C 端顾客入口：`POST /order/create` 与 `POST /order/addDishes` 在门店未营业（`ordering_open == 0`）时，服务端强校验拦截，返回 `code=4003, msg="门店已打烊，暂不接单"`。
  - 收银端开单入口：`POST /cashier/order/quickOrder` 与 `POST /cashier/order/addDishes` 在门店未营业时拦截，返回 `code=4003, msg="门店暂未营业，请先开启营业"`。支持特权覆盖（`force=1` 且操作人具备 `admin:manage` 权限放行）。
- **打烊与日结先后因果解耦**：
  - 打烊（`POST /order/ChangeBusiness`，`bus=0`）：解耦对今日营业日“必须先完成日结”的死锁校验，允许门店内已有用餐桌台继续消费结账，为日结预检（要求 0 开台、0 未结单、0 未交钱箱）创造清台条件。
  - 开启营业（`bus=1`）：在启用 `settle_required=1` 时，前置校验前一营业日（若存在历史订单）是否已完成日结封账。未完成时阻断开业：`code=4001, msg="前一营业日(yyyy-MM-dd)尚未日结，请先完成日结再开始营业"`（`admin:manage` 可通过 `force=1` 紧急放行并审计）。
- **当班钱箱现金收银强校验**：
  - 收银台结算（`POST /cashier/order/checkout`、`POST /cashier/table/checkout`）在门店开启 `shift_required=1` 且结算中包含现金（`cash_amount > 0`）时，强制校验当前终端具备有效且处于开启状态的钱箱会话（`drawerSessionId`）。
  - 若无活动开班钱箱，拦截：`code=4002, msg="当前钱箱未开班，请先完成开班后再进行现金收银"`，杜绝无账钱箱私收现金漏洞。
- **在线微信 Native 支付与收银台结算互斥**：
  - 收银台在执行手工结算（现金、刷卡、会员等）前，自动排查订单名下是否存在处于 `ACTIVE` 状态且未过期的微信 Native 动态二维码支付尝试。
  - 若存在活动二维码，拦截：`code=40935, msg="该订单正在进行微信扫码支付中，请先在收银端关闭支付二维码或确认顾客未付款"`，防范收银员现场收现金同时顾客手机完成微信扣款的双重收款事故。
- **已日结订单不可变（禁止反结账）**：
  - 反结账（`POST /cashier/order/uncheckout`）在加载订单后，定位其所属的营业日（依据门店结算时间窗口）；
  - 查询若该营业日已经生成不可变日结快照（`DailyCloseSnapshot` 处于 `CLOSED`）或已生成日结统计（`DailyStat`），强行拦截反结账：`code=40936, msg="该订单所属营业日已完成日结封账，禁止反结账"`，保护财务账簿不可篡改。

## 微信支付活动键释放与重复创建修复（v1.2.295）

- 修复 `t_wechat_native_payment_attempt` 与 `t_wechat_micropay_attempt` 实体中的 `active_key` 字段因 MyBatis-Plus 默认更新策略忽略 null，导致关单、支付成功或被微信拒绝后，数据库中 `active_key` 唯一键锁未能置为 `NULL` 的问题。
- `active_key` 显式声明 `@TableField(updateStrategy = FieldStrategy.IGNORED)`，确保执行 `updateById` 时可以将 `active_key` 正确更新为 `NULL`。
- `POST /cashier/payment/wechat/native/orders` 与关单接口增加终端状态自愈：当观察到历史记录已处于 `CLOSED/PAYERROR/REVOKED` 等终端状态时，不重复发起向微信关单的冗余请求，直接调用 `closeLocal` 自愈清空遗留的 `active_key`，彻底解决收银端重新发起 Native 支付报 `code=40931`（该订单正在创建支付二维码，请稍后查询）的阻塞问题。
- 附带迁移脚本 `src/main/resources/db/migration/V024__clean_terminal_active_keys.sql` 用于清理历史已结束状态遗留的非空 `active_key`。
## 日结订单与流水异常解释（v1.2.302 / WI-026）

- `GET /admin/daily/pre-check` 的硬阻断 `ORDER_LEDGER_MISMATCH` 现在会直接返回异常订单及原因，不再要求调用方仅凭两组渠道金额自行推断。
- 阻断项新增 `reason_summary`，按原因码统计全部异常订单；`details` 仍最多返回 50 笔，并在原有 `order_no`、`expected_by_channel_fen`、`ledger_by_channel_fen` 基础上兼容增加：
  - `order_id`、`shop_id`、`payment_method`；
  - `reason_codes` 与可直接展示的中文 `reason`；
  - `expected_total_fen`、`ledger_total_fen`、`difference_fen`；
  - `channel_differences[]`，包含 `channel/reason_code/reason/expected_fen/ledger_fen/difference_fen`。
- `difference_fen` 口径固定为“成功资金流水净额 - 订单实收投影”：负数表示流水不足，正数表示流水超额。原因码包括 `LEDGER_MISSING`、`ORDER_PROJECTION_MISSING`、`TOTAL_AMOUNT_SHORT`、`TOTAL_AMOUNT_EXCESS`、`CHANNEL_LEDGER_MISSING`、`UNEXPECTED_LEDGER_CHANNEL`、`CHANNEL_AMOUNT_SHORT`、`CHANNEL_AMOUNT_EXCESS`。
- 预检仍为只读；只核对成功非挂账订单。存在任一异常时 `can_settle=false`，且 `precheck_token/precheck_expires_at` 均为 `null`。

## 订单与权威资金流水闭环（v1.2.301 / WI-025）

- 所有成功结算入口统一为“锁定订单 → 写入/精确核验 `t_payment_ledger` → 更新订单资金投影”，余额钱包扣减、订单更新与流水写入处于同一事务；后台成功结账委托收银结算服务，不再维护第二套入账逻辑。
- 现金、余额本金、赠送金和微信退款均先写负向 `REFUND`，通过 `original_ledger_id` 关联原 `PAYMENT`，再更新钱包及订单；同一幂等号的订单、渠道、金额、原流水或三方退款号不一致时拒绝重放。
- 反结账只为原支付尚未冲正的余额写负向 `REVERSAL`。旧支付全额冲正后可重新结账生成新一代 `PAYMENT`，重复反结账不会超额冲正。
- `GET /cashier/shift/current`、交班统计、日结预览和支付成功后置处理均不再通过查询补造高可信流水。历史补录仅允许显式迁移使用。
- `GET /admin/daily/pre-check` 新增硬阻断 `ORDER_LEDGER_MISMATCH`：逐单按渠道比较订单当前实收投影与成功 `PAYMENT/REFUND/REVERSAL/ADJUSTMENT` 净额；存在缺失、金额或渠道差异时 `can_settle=false` 且不签发 `precheck_token`。
- `GET /admin/reconciliation/overview` 按门店营业窗口中的 `pay_time`（历史空值回退 `order_time`）统计，排除挂账销售；只要存在内部未匹配、渠道未匹配、金额差异、第一层不平或未关闭差异单，综合状态即为 `DISCREPANCY`。退款账单统一为负向金额，同一订单多笔同类型交易逐笔匹配，不互相覆盖。

## 权威资金流水优先（v1.2.300 / WI-024）

- `t_payment_ledger` 是订单实收、交班和日结统计的权威资金事实；`t_order` 的支付状态和渠道金额是业务投影，不能先于权威流水提交，也不能覆盖已有的另一笔成功资金流水。
- 微信成功回调 `POST /order/pay/notify` 完成尝试、金额、门店、商户、付款人和交易号校验后，在同一事务中先以 `WECHAT_{transaction_id}` 写入/校验成功 `PAYMENT` 流水，再更新订单结清状态。流水失败或订单更新失败会整体回滚并向微信返回 `FAIL`，由微信重试；相同交易精确幂等，不同交易明确冲突。
- 收银手工结账 `POST /cashier/order/checkout` 在订单锁内先收敛活动 JSAPI 交易：微信已支付时禁止手工结账，`NOTPAY` 时先关单，未知状态时 fail closed。随后先写支付流水、再更新订单；若已有不同成功流水、请求/渠道/金额/第三方交易号不一致或流水落库失败，事务整体回滚。
- 因此支付回调和收银手工结账竞争时，只能有一个资金事实获胜；交班与日结不会看到“订单已结清但无流水”的中间成功状态，也不会由收银员把微信实收改写成其他渠道。

## 小程序微信结算一致性（v1.2.299 / WI-024）

- 点餐单 `POST /order/getPrepayId` 现在把每次 JSAPI 微信交易持久化到 `t_wechat_jsapi_payment_attempt`，固化门店、订单、`outTradeNo`、金额分、付款 openid 和商户配置版本。同订单同金额同用户且未过期时复用原 `prepay_id`，不会重复创建微信交易。
- 当订单金额、付款用户或路由商户变化时，服务端先查微信权威状态；只有确认 `NOTPAY` 并关单成功，或已是不可支付终态，才允许创建新交易。`CREATING/UNKNOWN`、查单失败、关单失败或已支付均 fail closed，禁止重复支付。
- 退菜、改数量、改价/赠菜、手动优惠和加菜会在金额写入事务内执行同一闸门：旧单 `NOTPAY` 必须先关闭；微信已支付则拒绝直接改单并要求走支付后退款；状态不确定时不修改订单。
- 回调按支付尝试严格校验 `out_trade_no`、金额、门店、商户号/AppID、付款 openid 和微信 `transaction_id`。历史无尝试记录的兼容回调也必须与订单当前净应付完全一致，不再把少付金额自动写成优惠；已支付订单只有相同 `transaction_id` 才视为幂等，另一笔交易标记冲突并进入对账处理。
- 成功响应继续保留 `prepay_id` 和 `payParams`，新增可选 `paymentAttemptId`、`outTradeNo`、`amountFen`、`expiresAt`、`reused`。客户端遇到 `40931/40934/50331` 时必须丢弃缓存 payParams、刷新订单并稍后重试，不得直接再次调起旧支付参数。

部署前执行 `V029__wechat_jsapi_payment_attempt.sql`。充值单继续使用独立充值流水，点餐单才进入本次支付尝试闭环。

## 商业化挂账与应收账款（v1.2.298 / WI-023）

“挂账”现在是独立的应收账款业务，不再与 `/cashier/order/hang` 的临时挂单混用。挂账成功后订单进入 `success`，支付方式为 `挂账`，但现金、微信、支付宝、余额等实付字段全部为 0，且不生成虚假 `PaymentLedger`。销售额在订单所属营业日确认；回款只在真实收到款项的营业日计入 `receivable_summary.collected_fen` 和 `total_collections_fen`。

- 授信账户：`GET/POST /admin/receivables/accounts`、`GET/PUT/DELETE /admin/receivables/accounts/{id}`、`POST /admin/receivables/accounts/{id}/status`、`POST /admin/receivables/accounts/{id}/close`。账户支持 `SHOP` 门店范围和 `MERCHANT` 商户范围，范围创建后不可修改；状态为 `ACTIVE/SUSPENDED/CLOSED`；含未清余额或未结应收时禁止删除/关闭，额度不可降到未清余额以下；无任何历史交易时物理删除，有已结历史交易时注销关闭以留存审计流水。
- 收银挂账：`GET /cashier/receivables/eligible-accounts` 查询可用账户；`POST /cashier/receivables/charges` 提交 `orderNo/accountId/requestId/note`。金额只按服务端订单净应付计算，客户端不可传金额；额度不足、账户停用、跨门店、订单已结或已有活动应收均拒绝。
- 应收与回款：收银端和管理端均可查询应收并调用 `POST .../claims/{id}/collections`。请求包含 `amountFen/channel/requestId/note/drawerSessionId`；支持部分回款，禁止超额回款。`channel=CASH` 必须提供当前门店钱箱会话，并同步登记现金入账事件。
- 财务处置：`POST /admin/receivables/claims/{id}/reverse` 只允许撤销从未回款的应收，成功后恢复订单未结状态；`POST /admin/receivables/claims/{id}/write-off` 将剩余余额核销为坏账。两者均要求 `requestId/reason`，并写不可变流水。
- 退款隔离：既有 `POST /admin/order/refund` 遇到 `payment_method=挂账` 返回业务码 `409`，不会误发微信退款或伪造支付退款；未回款整单取消应使用应收撤销，已回款订单必须先按应收财务流程核对处理。
- 财务查询：`GET /admin/receivables/accounts/{id}/statement` 返回客户流水；`GET /admin/receivables/aging` 返回未到期、1–30、31–60、61–90、90+ 天账龄余额。
- 权限分为 `receivable:view`、`receivable:manage`、`receivable:merchant_manage`、`receivable:charge`、`receivable:collect`、`receivable:writeoff`；`MERCHANT` 跨店共享账户额外要求总部/老板权限 `receivable:merchant_manage`，门店店长只能管理本店 `SHOP` 账户。所有接口必须携带登录令牌和 `X-Shop-Id`，服务端还会按操作动作二次校验权限及门店归属。

部署前执行 `V028__receivables_system.sql`。日结快照新增 `cutoff_receivable_ledger_id`、`receivable_charged_fen`、`receivable_collected_fen`、`receivable_writeoff_fen`、`receivable_outstanding_fen`、`total_collections_fen`；预检令牌水位包含 `receivable_ledger_id`，预检后发生应收流水会返回 `409 WATERMARK_CHANGED`。

## 收银个人收款码金额自愈与零元单保护（v1.2.299）

- `POST /pay/offline-collect/temp-qrcode` 收银出码模式下，当客户端传 `amount_fen <= 0` 或未携带有效分摊金额时，服务端先校验订单归属与未结状态，自动从持久化订单提取实际净应付金额（`sett_amount + service_fee - discount_amount - refund_amount - pay_amount_gift`）进行出码金额自愈，避免客户端计算快照瞬断或金额字段差异直接抛 400 阻断收款。
- 当订单在库内待付金额确实为 ¥0.00 时，返回明确友好的业务错误：`400: "订单待收金额为 ¥0.00，无需生成收款码"`。
- 收银端在进入离线扫码弹窗前增加待收金额前置校验，零元单不再触发无效出码请求。

## 收银微信支付与个人收款码开关隔离修复（v1.2.297 / WI-022）

- `POST /pay/offline-collect/temp-qrcode` 的 `channel=wechat` 现在只校验个人微信收款码渠道 `offline_wechat_qr`（配置源 `clients.cashier.channelStates.wechat_qr.enabled` / `cashier_wechat_qr_enabled`），不再误读微信商户支付渠道 `online_wechat`。
- 因此关闭“微信支付（商户直连）”不会再阻止已开启的“微信收款码（个人码）”出码；反向亦成立：只开启商户微信支付不能绕过个人码开关。
- `channel=alipay` 同样只校验 `offline_alipay_qr`；两类个人码仍共同受 `clients.cashier.enabled` 收银支付总开关约束。接口路径、请求体、成功响应和权限不变。

## 微信 Native 关单后重新下单修复（v1.2.296 / WI-021）

- 修复 `POST /cashier/payment/wechat/native/orders/{orderNo}/close` 成功后，旧支付尝试的 `active_key` 未实际写为数据库 `NULL`，导致再次调用 `POST /cashier/payment/wechat/native/orders` 命中唯一索引并返回 `40931` 的问题。
- 关单、查单收敛、支付成功、明确拒绝和成功通知等 Native 终态现在都会可靠释放活动键；同一订单随后可生成新的 `outTradeNo/codeUrl`。
- `CREATING/UNKNOWN` 仍保留活动键并继续阻断重复出码；请求、响应、权限和错误码结构不变。

## 支付商户商业化管理（v1.2.295 / WI-020）

- 商户配置新增 `status=ACTIVE|RETIRED` 与单调递增的 `credentialVersion`。`DELETE /admin/payment/merchants/{id}` 现在执行可恢复退役，返回 `retired=true、physicallyDeleted=false`；`POST /admin/payment/merchants/{id}/restore` 恢复商户。退役不会删除历史交易所需凭据。
- 已存在配置的 `channel/merchantKey` 作为稳定身份不可原地修改；变更商户实例键时应新建配置并退役旧配置。
- 新增 `GET/PUT /admin/payment/merchant-policy`，按当前门店读写 `allowGlobalFallback`。默认 `false`，即支付运行时只解析订单所属门店的商户；仅显式开启后才可回退总部 `shop_id=0` 模板。
- `merchantKey` 不再限制为 `default/small_amount`；`1/2` 继续兼容。`routingRuleJson` 支持 `amount_and_dining`、`minPaidYuan`、`maxPaidYuan`、`diningTypes`、`targetMerchantKey`、`defaultMerchantKey`，按 `sortOrder` 首个匹配规则路由。
- JSAPI、Native、MICROPAY 创建交易时固化 `merchantConfigId/merchantKey/merchantConfigVersion`；查单、关单、撤销、回调校验和退款优先解析该版本。配置更新前保存加密历史快照，避免在途交易漂移到新密钥。
- 未配置 `payment.config-master-key`/`PAYMENT_CONFIG_MASTER_KEY` 时，新增或更改 APIv2/APIv3 密钥将 fail closed；仅 `debug` profile 显式允许 `plain:` 兼容写入。部署前执行 `V027__payment_merchant_commercialization.sql`。

## 微信 Native 下单错误分类与诊断（v1.2.294 / WI-019）

- `POST /cashier/payment/wechat/native/orders` 不再把所有微信调用失败折叠为 `50331`。微信明确返回 HTTP 4xx 时，本地支付尝试收敛为 `CLOSED/PAYERROR` 并释放活动占用，返回 `code=40231`、安全化 `msg` 以及可选 `wechatCode/requestId`；收银端可在修正商户配置或订单参数后重试。
- 微信 5xx、网络/超时、响应验签失败或其他无法确认是否已受理的异常仍返回 `code=50331`，支付尝试保持 `UNKNOWN`，客户端必须先主动查单，严禁直接重复收款。
- 服务端以 `[wx-native] create rejected|uncertain|unexpected` 记录结构化诊断，只包含门店、订单、商户单号、HTTP 状态、微信错误码和 Request-ID，不记录 Authorization、签名或响应体。

## 微信 Native APIv3 同步响应可信校验（v1.2.293 / WI-018）

- Native 创建二维码、主动查单和关单继续复用既有门店微信商户配置：`mchId`、商户 API 证书序列号及商户私钥来自同一次 `shopId + merchantId` 解析，不新增或切换商户凭据。
- 三类微信 APIv3 同步响应均验证 `Wechatpay-Serial`、`Wechatpay-Timestamp`、`Wechatpay-Nonce` 和 `Wechatpay-Signature`；平台公钥 ID 必须与配置一致，响应时间戳与服务器时间偏差不得超过 5 分钟。
- 平台公钥缺失、商户证书序列号明确不匹配、商户证书已过期、签名头缺失或验签失败时，不接受 `code_url`、交易状态或关单成功。创建/查询/关单接口分别沿用原有 `50331`、`50332`、`50333` 不确定结果语义，客户端应先查单，不得据此重复收款。

## 收银台微信付款码支付二期（v1.2.291 / WI-016）

- `POST /cashier/payment/wechat/micropay/orders`：收银员扫描顾客微信付款码后提交 `orderNo`、`authCode` 和可选 `terminalId`。金额严格取服务端订单净应付。付款码必须为 18 位数字且前缀为 10–15；它只用于本次微信请求，不落库、不进入响应或日志。
- `GET /cashier/payment/wechat/micropay/orders/{orderNo}`：主动查询微信权威状态。`SUCCESS` 会复用现有幂等支付入账、台账、打印、桌台、KDS 和配送链路；`USERPAYING/UNKNOWN` 仍不可改用其他渠道或重复扫码。
- `POST /cashier/payment/wechat/micropay/orders/{orderNo}/reverse`：交易创建至少 15 秒后，先查单再撤销。查单已经成功则直接入账且绝不撤销；撤销结果未知时继续查单。
- 三个接口要求当前门店和 `cashier:operate`。同一门店订单只允许一个活动付款码交易，客户端不得自行生成或替换 `outTradeNo`。
- 商户配置新增 `apiV2Key`（32 位，服务端加密保存）和 `clientCertP12Ref`（服务器 `.p12/.pfx` 文件路径，默认口令为商户号）。二期不复用 APIv3 密钥；缺少任一项返回商户配置不完整。
- 微信 V2 请求统一使用 `HMAC-SHA256`；通信成功响应必须验签后才能读取业务结果。部署前执行 `V023__wechat_micropay.sql`。

请求示例：

```json
{"orderNo":"ORD202610150001","authCode":"123456789012345678","terminalId":"POS-01"}
```

支付中响应示例：

```json
{"code":0,"orderNo":"ORD202610150001","outTradeNo":"ORD202610150001_123","amountFen":3800,"tradeState":"USERPAYING","status":"USERPAYING"}
```

典型业务码：`40031` 付款码格式无效；`40941` 已有待确认交易；`40942` 微信成功但本地入账需人工核对；`40943` 已支付不可撤销；`40944` 未满 15 秒；`40241` 微信明确拒绝；`50341/50342/50343` 支付、查单或撤销结果暂不确定。

## 收银台微信 Native 动态码一期（v1.2.290 / WI-015）

### 1. 业务概述与渠道设计
- **收银端增加微信支付（Native 动态码）**：收银机可直接向微信统一下单并生成展示动态支付二维码，顾客使用微信扫码即付。
- **独立开关控制**：独立使用收银端微信支付开关（`clients.cashier.channels.wechat` / `cashierWechatEnabled`），仅当门店收银端微信开启且微信商户配置就绪时可用；**完全不受小程序端微信支付开关影响**。
- **保留原有微信收款码渠道**：完整保留原有的微信个人/静态收款码渠道（`clients.cashier.channels.wechat_qr` / `cashierWechatQrEnabled`，旧 code `offline_wechat_qr`），收银员手动核实到账与 Native 动态扫码通道互不干扰、独立配置并存。
- **金额完全由服务端计算**：支付金额严格由服务端依据订单净应付金额（`netRevenueFen`）计算得出，客户端请求体无法指定金额，彻底杜绝客户端篡改金额风险。
- **防并发与防重复收款**：
  - 数据库级别防并发：`t_wechat_native_payment_attempt` 表引入 `active_key` (`shop_id:order_no`) 唯一索引，拦截并发重复出码；
  - 动态复用机制：同一订单存在金额一致且未过期的 `ACTIVE` 支付尝试时，直接复用既有动态码与支付单，避免频繁向微信下单；
  - 并发幂等复用：并发请求观察到 `CREATING` 或唯一键竞争时，会短暂有界等待并复用胜出请求生成的有效二维码，竞争请求不会再次调用微信下单；等待超时或结果仍不确定时返回 `code=40931`；
  - 未知状态拦截：上一笔尝试处于 `UNKNOWN` 或等待窗口后仍处于 `CREATING` 时，拒绝重新出码并返回 `code=40931`；微信下单异常时不确定结果置为 `UNKNOWN` 并返回 `code=50331`，强制收银端必须先发起主动查单，严禁未知状态下重新出码导致重复收款。
- **严密安全校验**：微信支付异步回调与主动查单共用业务字段校验逻辑，严格校验 `out_trade_no`、实付金额与应付金额、交易类型（`NATIVE`/`JSAPI`）、商户号 `mchid` 以及 `appid`；Native 创建、查单和关单的 APIv3 同步响应还必须通过平台公钥 ID、五分钟时间窗口及 RSA-SHA256 签名校验后才可进入业务处理。
- **回调与主动查单共用幂等入账**：底层统一调用 `WechatPaymentSuccessService.apply(...)`，在数据库行锁与单号互斥锁保护下幂等入账；即使微信回调丢失或延迟，收银端主动查单亦可立即补偿入账。
- **全面复用既有履约与账务流程**：订单支付入账后，自动复用既有系统副作用：
  - 自动记录不可变支付台账（`PaymentLedger`）；
  - 触发打印调度（结账单、前台小票、厨房小票）；
  - 堂食订单自动更新桌台状态并完成清台；
  - 联动 KDS 厨显流转与外卖配送调度；
  - 退款继续复用既有微信退款接口（`/admin/order/refund`）；
  - 财务对账继续复用既有渠道对账单导入与核对流程。

### 2. 接口契约明细

#### (1) 创建或复用 Native 支付二维码
- **端点**：`POST /cashier/payment/wechat/native/orders`
- **权限与认证**：Bearer Token，`cashier:operate` 权限，请求头携带 `X-Shop-Id`（或 `X-Shop-Code`）
- **请求体**：
  ```json
  {
    "orderNo": "ORD202610150001",
    "terminalId": "POS-01"
  }
  ```
  *注：`order_no` 与 `orderNo`、`terminal_id` 与 `terminalId` 自动兼容兼容别名；客户端不得传金额。*
- **成功响应（HTTP 200，code=0）**：
  ```json
  {
    "code": 0,
    "paymentId": 10086,
    "orderNo": "ORD202610150001",
    "outTradeNo": "ORD202610150001_1729000000000",
    "codeUrl": "weixin://wxpay/bizpayurl?pr=...",
    "amountFen": 3800,
    "expiresAt": "2026-10-15T07:35:00.000+08:00",
    "tradeState": "NOTPAY",
    "reused": false
  }
  ```
- **典型错误响应**：
  - `code=401`：缺少门店上下文；
  - `code=40931`：上一笔微信下单结果尚未确认或正在并发创建，请先查询支付状态；
  - `code=40934`：订单已支付，禁止重复收款；
  - `code=40231`：微信明确拒绝本次下单；响应可含 `wechatCode`、`requestId`，修正配置或参数后可重试；
  - `code=50331`：微信下单结果暂不确定，请先查询支付状态，勿重复收款；
  - `code=50011` / `code=50012`：收银端微信支付未开启或商户未配置完整；
  - `code=500`：订单不存在、并台从单需主桌结账、订单状态不允许支付或应付金额 <= 0。

同一订单被重复或并发提交时，如果首个请求已在短暂等待窗口内生成二维码，后到请求也会返回 `code=0`、`reused=true` 及相同的 `codeUrl`；收银端应按正常二维码展示。请求进行中仍建议禁用重复点击。

#### (2) 主动查单并补偿回调丢失
- **端点**：`GET /cashier/payment/wechat/native/orders/{orderNo}`
- **权限与认证**：Bearer Token，`cashier:operate` 权限，请求头携带 `X-Shop-Id`（或 `X-Shop-Code`）
- **路径参数**：`orderNo`（订单编号）
- **成功响应（HTTP 200，code=0）**：
  ```json
  {
    "code": 0,
    "paymentId": 10086,
    "orderNo": "ORD202610150001",
    "outTradeNo": "ORD202610150001_1729000000000",
    "amountFen": 3800,
    "tradeState": "SUCCESS",
    "status": "SUCCESS",
    "transactionId": "4200002123202610150000000001"
  }
  ```
  *注：若微信交易状态为 `SUCCESS`，服务端自动完成本地订单入账、支付台账写入、桌台清台与小票打印调度，补偿异步回调丢失。*
- **典型错误响应**：
  - `code=401`：缺少门店上下文；
  - `code=40431`：未找到该订单的微信扫码支付记录；
  - `code=40932`：查单入账处理冲突或校验失败（如实付金额不匹配等）；
  - `code=50332`：微信查单暂时失败，请稍后重试；
  - `code=500`：订单不存在或不属于当前门店。

#### (3) 关闭未支付订单尝试
- **端点**：`POST /cashier/payment/wechat/native/orders/{orderNo}/close`
- **权限与认证**：Bearer Token，`cashier:operate` 权限，请求头携带 `X-Shop-Id`（或 `X-Shop-Code`）
- **路径参数**：`orderNo`（订单编号）
- **成功响应（HTTP 200，code=0）**：
  - 成功关闭活动尝试：
    ```json
    {
      "code": 0,
      "closed": true,
      "outTradeNo": "ORD202610150001_1729000000000"
    }
    ```
  - 本地无活动尝试幂等返回：
    ```json
    {
      "code": 0,
      "closed": true,
      "idempotent": true
    }
    ```
- **典型错误响应**：
  - `code=401`：缺少门店上下文；
  - `code=40933`：订单已支付，不能关单；
  - `code=50333`：微信关单失败，请先查单确认支付状态；
  - `code=500`：订单不存在或不属于当前门店。

### 3. 数据表与迁移
- 部署前执行 `src/main/resources/db/migration/V022__wechat_native_payment_attempt.sql`；
- 核心表 `t_wechat_native_payment_attempt`，`active_key` (`shop_id:order_no`) 承担跨进程并发防重。

## 日结预检提示可作废打包外卖单与一键全部作废契约（v1.2.289 / WI-014）

- **背景与解决问题**：
  - 日结预检（`GET /admin/daily/pre-check`）时，若存在打包或外卖顾客跑单/未结账订单，因没有桌台清台流程，会一直作为 `OPEN_ORDERS` 阻断日结；
  - 收银员过去需逐笔翻找订单撤销，操作繁琐且易影响打烊关账；
  - 本次在日结预检中增强智能识别超过 30 分钟未支付的打包/外卖单，并在阻断项中提供结构化提示；同时提供一键全部作废端点，实现库存释放、KDS 作废、配送单取消与意向清理全闭环。
- **接口清单**：
  - `GET /admin/daily/pre-check`：
    - 查询参数：`stat_date`（可选，营业日），`minutes`（可选，超时分钟阈值，默认 30）；
    - 响应顶层新增 `voidable_stale_pack_takeout` 结构；
    - 阻断项 `OPEN_ORDERS` 结构体内增加 `voidable_pack_takeout` 聚合统计与明细；
    - 响应示例：
      ```json
      {
        "code": 0,
        "data": {
          "can_settle": false,
          "stat_date": "2026-10-13",
          "blockers": [
            {
              "code": "OPEN_ORDERS",
              "message": "当前营业日仍有 3 笔未完成或未结账订单，请结账或撤单（其中含 2 笔超过 30 分钟未支付的打包/外卖单，可一键全部作废）",
              "count": 3,
              "voidable_pack_takeout": {
                "count": 2,
                "amount": 76.0,
                "threshold_minutes": 30,
                "can_one_click_void": true,
                "orders": [
                  {
                    "id": 101,
                    "order_no": "ORD-101",
                    "order_time": "2026-10-13 18:20:00",
                    "sett_amount": 38.0,
                    "payable_amount": 38.0,
                    "dineInOrTakeOut": "打包",
                    "age_minutes": 45
                  }
                ]
              }
            }
          ],
          "voidable_stale_pack_takeout": {
            "count": 2,
            "amount": 76.0,
            "threshold_minutes": 30,
            "can_one_click_void": true,
            "orders": [...]
          }
        }
      }
      ```
  - `POST /admin/daily/void-stale-takeout-orders`：
    - 权限要求：`daily:settle|order:operate`；
    - 请求体（可选）：
      ```json
      {
        "stat_date": "2026-10-13",
        "minutes": 30
      }
      ```
    - 响应示例：
      ```json
      {
        "code": 0,
        "msg": "操作成功",
        "data": {
          "voided_count": 2,
          "voided_amount": 76.0,
          "threshold_minutes": 30,
          "voided_order_nos": ["ORD-101", "ORD-102"]
        }
      }
      ```
- **业务一致性与安全保证**：
  - 严禁误伤堂食（`dine_in`）：仅就餐方式属于打包、自提、外卖的订单方可入选；
  - 严禁误伤已支付/已退款订单：必须 `transac_status = 'unsettled'`；
  - 严格 30 分钟阈值防护：未满超时时长的打包/外卖单绝不作废；
  - 事务级原子副作用联动：
    1. 订单 `transac_status` 与 `order_receiving` 置为 `cancelled`；
    2. 回退占用菜品库存（`dishShopStockService.restoreForDetail`）；
    3. 同步取消关联外卖配送单（`takeoutDeliveryService.markCancelledIfPresent`）；
    4. 通知 KDS 厨显屏幕作废工单（`kdsOrderHook.afterOrderCancelled`）；
    5. 清理关联的收款意向占用（`collectionIntentService.cancelAllForOrder`）；
    6. 写入特权操作审计日志（`securityAuditService.recordPrivilegedAction`，action 为 `BATCH_VOID_STALE_TAKEOUT`）。

## 强制结账支持 admin:manage 权限契约（v1.2.288 / WI-013）

- **背景与解决问题**：
  - 当扫码出码出现 `CONFIRMED` 确认到账但订单仍为 `unsettled`（如异常中断、出码冲突锁死）时，常规结账或重新出码会被阻断（“该订单已有其他收款会话确认到账”）。
  - 引入特权强制结账机制，允许持有 `admin:manage` 权限的管理员、店长或通过审批授权的收银员强制结账并原子清理冲突意向。
- **接口清单**：
  - `POST /cashier/order/checkout`：支持请求体参数 `force: true`（或 `force_checkout`、`forceCheckout`）。
  - `POST /cashier/table/checkout`：透传 `force: true` 批量强制结账整桌订单。
  - `POST /admin/order/checkout`：支持实体参数 `force: true`（及 `approvalToken`）。
  - `POST /cashier/order/force-checkout`：收银端专用端点，内置 `force: true`，权限映射 `admin:manage`。
  - `POST /admin/order/force-checkout`：管理端专用端点，内置 `force: true`，权限映射 `admin:manage`。
- **权限与多模式授权**：
  - 必须持有 `admin:manage` 权限（或拥有超管角色 `super_admin` 豁免）；
  - 普通收银员支持现场弹窗输入主管账号密码（`SensitiveOperationAuthorizationService`）或提供有效审批令牌 `approvalToken`（`ApprovalService`）完成核验并放行；
  - 校验失败直接返回 HTTP 403 `{"code": 403, "msg": "强制结账需要具备 admin:manage 权限"}`。
- **业务收敛与特权审计**：
  - `force=true` 时放行意向一致性与占用校验；
  - 订单更新成功后，原子调用 `completeAllForOrder(shopId, orderNo)` 将订单名下所有 `PENDING` 与 `CONFIRMED` 意向标记为 `COMPLETED`，彻底解除冲突；
  - 记录特权安全审计日志（`securityAuditService.recordPrivilegedAction`，action 为 `FORCE_CHECKOUT` / `ADMIN_FORCE_CHECKOUT`）；
  - 成功响应中回显 `"forced": true` 标识。

## 桌台金额绑定订单实际金额契约（v1.2.287）

- **接口**：`GET /admin/table/status`。
- **金额真源**：桌台待结账金额只汇总当前桌全部未结订单的持久化实际净应付金额：`sett_amount + service_fee - discount_amount - refund_amount - pay_amount_gift`，最低为 0。
- **一致性保证**：订单明细 `goods_list` 仅用于展示及赠送/退款行审计，不再按明细二次重算或覆盖订单的 `sett_amount`、`service_fee`；套餐历史子行、重复明细和服务费配置变化均不得使桌台金额偏离订单金额。
- **并台语义**：并台存在多笔未结订单时，对每笔订单实际净应付金额求和。
- **审计字段**：`amountAudit.calculation_source` / `amountAudits[].calculation_source` 固定为 `persisted_order_amounts`。
- **兼容性**：请求参数与响应结构不变；仅修正金额及审计来源语义。

## 加菜保持订单首单时间契约（v1.2.286）

- **接口**：`POST /order/addDishes`、`POST /cashier/order/addDishes`。
- **时间语义**：`t_order.order_time` 永远表示订单首次创建时间；成功加菜只追加订单明细并更新金额、费用、优惠及加菜轮次，禁止把 `order_time` 刷新为加菜时刻。
- **下游影响**：账单排序、最近 3 小时账单、营业日归属、运营统计及 KDS 首单时间继续基于稳定的首次下单时间。
- **兼容性**：请求字段、响应字段、权限、库存扣减、自动接单和 KDS 事件均不变，客户端无需调整。

## 运营后台门店菜单拖拽排序契约（多门店确定性修复）

- **接口**：`POST /admin/category/sort`
- **请求体**：`{"id": 被拖拽类目ID, "targetIndex": 拖拽后的目标位置（1-based 显示位置）}`
  - 传 `0` 等价于移到首位；越界自动收敛到首/末位；`targetIndex` 与当前位置一致时直接成功不落库。
- **门店上下文**：必须携带 `X-Shop-Id` 或 `X-Shop-Code`；服务端只信任拦截器解析且鉴权后的当前门店。
- **分类排序语义**：
  - 分类主数据仍共用 `t_category`，当前店顺序写入 `t_category_shop.sorting_override`，不再改写全局 `t_category.sorting`；
  - 生效键为 `(ifnull(t_category_shop.sorting_override, t_category.sorting), t_category.id)`；重复/NULL 历史值由 id 稳定打破；
  - 拖拽后为当前店全部分类写入连续 `1..n`，不同门店互不影响。
- **菜品排序接口**：`POST /admin/dish/sort`，请求体同样为 `id + targetIndex`；`targetIndex` 是当前门店、该菜品**生效分类内**的 1-based 位置。仅重排该分类的 `t_dish_shop.sorting_override`，不修改其他分类、其他门店或 `t_dish.sorting`。
- **并发/原子性**：两个接口均先锁定当前 `t_shop` 行，在同一事务内完成全量重排；同店并发串行，不同店互不阻塞，任一写失败则整体回滚。
- **响应**：`code=0` 成功；`code=4001` 缺门店上下文；`code=4003` 门店无效；`code=500` 参数/资源/更新错误。
- **前端配合**：`/admin/category/listAll` 与菜单列表已返回门店生效顺序，直接按当前分类数组或当前分类内菜品数组的下标+1 传 `targetIndex`。
- **数据库前置**：执行 `docs/db_migration_category_shop_sorting.sql`。

## POS 权限中心升级与策略审批协同契约（v1.2.278 / POS Access Control v2）

### 审批上下文严格绑定 v2（WI-059）

- `POST /cashier/access/authorize` 与 `POST /cashier/access/qr/create` 新增可选 `bindingVersion`；省略时为兼容 v1，响应含 `bindingVersion: 1`、`legacyBinding: true`。
- 新客户端应发送 `bindingVersion: 2`、稳定 `terminalId`、真实且非 `N/A`/`ID:` 占位的资源类型/ID，以及本次动作的精确金额；订单类敏感操作统一使用 `bizType: ORDER`，动作由 `permission` 表达。非金额动作签发与核销两端均不传金额。
- 重试敏感操作时必须携带同一个 `X-Terminal-Id`（或该接口支持的 `terminalId` 请求字段），并保持资源和金额上下文不变。
- v2 核销严格比较权限动作、资源类型/ID、金额、登录操作人、门店和终端。任一字段缺失或不一致都返回原敏感操作的 `40321`，且令牌保持 `APPROVED`、不会被误消费。
- 金额使用十进制数值相等语义，`10.0` 与 `10.00` 相等；不再使用“审批金额 + 50 元”的容差。
- 服务端兼容历史 `binding_version` 空值/1；兼容命中记录 `approval_legacy_binding` 安全日志。v1 的强制关闭日期由后续客户端采用率审计决定。
- 管理端审批流水响应增加 `bindingVersion` 与 `legacyBinding`，用于统计迁移采用率；不返回令牌哈希或明文。
- 数据库升级：Flyway `V037__approval_binding_version.sql`（WI-060 修正了与既有 V036 的版本冲突）。
- 前端迁移契约：`docs/work-items/WI-059/CONTRACT_HANDOFF.md`。

### 动作级审批权限与频率限制（WI-061）

- 现场授权和二维码 `AGREE` / `REJECT` 统一要求目标业务权限追加 `:approve`。当前敏感动作分别为：
  - `order:operate:refund:approve`
  - `order:operate:changePrice:approve`
  - `order:operate:discount:approve`
- `access:approve`、`refund:approve`、`order:operate`、`admin:manage` 等宽泛权限不再作为运行时替代；只有 `admin:super` 保留旁路，但仍受凭据和频率限制。
- Flyway `V040__approval_permission_and_rate_limit.sql` 新增动作审批权限、对既有审批/管理员角色做加法迁移，并建立跨实例共享的 `t_access_approval_rate_limit`。普通收银/动作执行角色不会因迁移自动获得审批权。
- `/cashier/access/authorize`：同门店/操作人 10 次/60秒，超限阻断 300 秒；同门店/授权账号的 PIN/密码连续失败 5 次，阻断 900 秒，成功验证后清零失败窗口。
- `/cashier/access/qr/create`：同门店/操作人 10 次/60秒，超限阻断 300 秒。
- `/admin/access/qr/confirm`：同门店/审批人 20 次/60秒，超限阻断 300 秒。二维码状态轮询不计入限流。
- 超限统一返回 HTTP 429：
  ```json
  {
    "code": 429,
    "error": "ACCESS_APPROVAL_RATE_LIMITED",
    "error_code": "ACCESS_APPROVAL_RATE_LIMITED",
    "msg": "请求过于频繁，请稍后重试",
    "data": {
      "retryAfterSeconds": 300,
      "rateLimitScope": "ONSITE_AUTHORIZE"
    }
  }
  ```
- 审批成功/详情响应增加 `requiredApprovalPermission`。二维码权限不足返回 403，`data.requiredApprovalPermission` 指明所需权限。
- 限流键仅保存复合上下文的 SHA-256，不保存原始账号、PIN、密码或审批令牌；拒绝写入安全审计。
- 前端改造：`docs/work-items/WI-061/FRONTEND_ADAPTATION_GUIDE.md`。

- **背景与升级目标**：
  - 在既有 RBAC 基础架构上无侵入增量升级，建立**统一访问决策引擎（AccessDecisionService）**；
  - 覆盖员工全生命周期管理（启用、停用、锁定、离职），配合权限版本号（`permission_version`）与强制下线时间（`force_logout_at`）实现敏感权限变更与账号停用的**秒级即时失效**；
  - 引入动态业务策略控制（金额上限 `MAX_AMOUNT`、最低折扣率 `MIN_DISCOUNT_RATE`）与显式覆盖（`EFFECT_DENY` / `EFFECT_ALLOW`）；
  - 提供现场收银店长现场凭证授权机制（密码或6位PIN码验证后签发120秒短期一次性 `approvalToken`，CAS 原子核销，防重放与跨店越权）；
  - 建立职责分离 (SoD) 冲突防护网，防止高风险权限组合违规分配。

- **新增与升级接口清单**：
  1. **员工状态变更**：`PUT /admin/access/employees/{adminId}/status`
     - 权限：`access:manage`
     - 请求体：`{"status": "ACTIVE" | "DISABLED" | "RESIGNED"}`
     - 效果：变更 `t_admin.account_status`；停用或离职时自动更新 `force_logout_at` 并递增 `token_version`，强制已登录客户端会话失效。
     - **更新未生效保护（审计修复）**：`updateById` 影响行数为 0 时不再静默返回成功——回查 DB，若已是目标状态视为幂等成功（并发/重复提交），否则返回 HTTP 500 `ACCESS_STATUS_UPDATE_FAILED`「员工状态更新未生效」。
     - **前置迁移**：`t_admin` 的 `account_status` / `permission_version` / `force_logout_at` 列必须存在，缺失时先执行幂等脚本 **`docs/db_migration_admin_account_status.sql`**（`token_version` 见 `db_migration_admin_token_version.sql`）。
  2. **强制员工下线**：`POST /admin/access/employees/{adminId}/force-logout`
     - 权限：`access:manage`
     - 效果：立即刷新 `force_logout_at` 与 `token_version`，使已签发的 JWT 无法通过网关校验。
  3. **查询最终有效权限**：`GET /admin/access/employees/{adminId}/effective-permissions?shopId={shopId}`
     - 权限：`access:view` 或 `access:manage`
     - 响应：返回当前员工账号状态、版本号、所属角色、基础权限集合以及显式覆盖规则列表（`overrides`）。
  4. **带业务记录禁止删除**：`DELETE /admin/access/employees/{adminId}?confirm=true`
     - 规则：若员工在订单（`t_order`）、当班（`t_shift`）、操作日志（`t_operation_log`）或审批流水（`t_access_approval`）中存在任何历史业务记录，返回 HTTP 409 `ACCESS_EMPLOYEE_HAS_RECORDS` 禁止删除，推荐使用停用或离职状态。
  5. **职责分离 (SoD) 冲突预检**：`POST /admin/access/conflicts/check`
     - 请求体：`{"permissionCodes": ["cashier:cashbox:open", "report:financial:view"]}`
     - 响应：返回命中的冲突规则列表及级别（HARD / SOFT）。
  6. **权限策略管理 (CRUD & 绑定)**：
     - `GET /admin/access/policies?permissionCode={code}`
     - `POST /admin/access/policies`：创建策略（支持 `MAX_AMOUNT`, `MIN_DISCOUNT_RATE` 等，配置规则存为 JSON）
     - `PUT /admin/access/policies/{id}`：更新策略
     - `DELETE /admin/access/policies/{id}`：删除策略
     - `POST /admin/access/policies/assign`：绑定角色策略（`{"roleId": 3, "policyId": 100, "shopId": 1}`）
  7. **审批记录流水分页与详情**：
     - `GET /admin/access/approvals?shopId=1&bizType=ORDER_REFUND&status=CONSUMED&page=1&pageSize=20`
     - `GET /admin/access/approvals/{id}`
  8. **统一权限决策解释**：`POST /admin/access/evaluate`
     - 请求体：`{"userId": 2, "shopId": 1, "permission": "order:operate:refund", "context": {"amount": 100.0, "approvalToken": "..."}}`
     - 响应：`{"outcome": "ALLOW", "allow": true, "permissionGranted": true, "shopInScope": true, "policyPassed": true, "approvalRequired": false, "reasonCode": "APPROVED_OVERRIDE", "matchedRoles": [...], "matchedPolicies": [...]}`
  9. **收银端店长现场凭证授权**：`POST /cashier/access/authorize`
     - 权限：`cashier:operate`（需门店上下文 `X-Shop-Id`）
     - 请求体：
       ```json
       {
         "authorizerAccount": "MGR001",
         "credential": "PIN_OR_PASSWORD",
         "authMethod": "PIN",
         "permission": "order:operate:refund",
         "bizType": "ORDER",
         "bizId": "20261006123456",
         "amount": 88.00,
         "reason": "顾客菜品退款超额授权"
       }
       ```
     - 响应：
       ```json
       {
         "code": 0,
         "approvalToken": "appr_...",
         "approvalNo": "AP_1_...",
         "expireSeconds": 120,
         "authorizerName": "张店长"
       }
       ```
  10. **收银端退款集成审批 Token**：`POST /cashier/order/refund`
      - 支持传入 `approvalToken`；超额触发策略时优先核销该 Token，核销成功后放行退款并记审批流水。
  11. **收银端动态二维码扫码授权（店长手机端确认，方案A）**：
      - **背景与痛点**：收银员在收银机（PC或手机收银端）操作敏感业务时，避免店长现场按键盘输入密码/PIN导致被旁人偷窥，支持收银端展示动态二维码，店长使用移动端/手机后台扫码核验后在自己手机上点确认。
      - **接口一：收银端生成授权二维码** `POST /cashier/access/qr/create`
        - 权限：`cashier:operate`（Header 需带 `X-Shop-Id`）
        - 请求体：
          ```json
          {
            "permission": "order:operate:refund",
            "bizType": "ORDER",
            "bizId": "20261006123456",
            "amount": 120.00,
            "reason": "顾客大额退款申请",
            "requestId": "REQ_QR_1001",
            "terminalId": "POS_01"
          }
          ```
        - 响应：
          ```json
          {
            "code": 0,
            "data": {
              "approvalCode": "QAP_1_1791297711724_7505",
              "qrPayload": "bbq://approval?code=QAP_1_1791297711724_7505",
              "status": "PENDING",
              "expiresAt": "2026-10-06T22:43:51.000+08:00",
              "expireSeconds": 120
            }
          }
          ```
      - **接口二：收银端轮询审批结果** `GET /cashier/access/qr/status?approvalCode=QAP_1_...`
        - 权限：`cashier:operate`
        - 响应：
          ```json
          {
            "code": 0,
            "data": {
              "approvalCode": "QAP_1_...",
              "status": "APPROVED",
              "approvalToken": "3fa85f64...",
              "authorizerId": 5,
              "authorizerName": "张店长",
              "expiresAt": "2026-10-06T22:43:51.000+08:00"
            }
          }
          ```
          *(注：status 为 PENDING 时持续轮询，超过 120 秒自动变为 EXPIRED，店长拒绝时为 REJECTED，APPROVED 时获取 approvalToken 并自动带入业务操作接口完成原子核销。数据库仅保存 SHA-256 哈希与 AES-256-GCM 短期加密信封；各实例使用同一个 `APPROVAL_TOKEN_ENVELOPE_KEY` 安全提取，核销后自动清空信封。密钥缺失、密文篡改或哈希不一致时返回 503 且不泄露令牌。)*
      - **接口三：店长手机端扫码查阅业务详情** `GET /admin/access/qr/details?approvalCode=QAP_1_...`
        - 权限：登录态店长；查看时校验门店管辖范围，确认/驳回时必须具有响应 `requiredApprovalPermission` 指定的动作级审批权限（`admin:super` 除外）
        - 响应：
          ```json
          {
            "code": 0,
            "data": {
              "approvalCode": "QAP_1_...",
              "shopId": 1,
              "permission": "order:operate:refund",
              "bizType": "ORDER",
              "bizId": "20261006123456",
              "amount": 120.00,
              "reason": "顾客大额退款申请",
              "operatorId": 10,
              "operatorName": "小李(收银员)",
              "operatorWorkNo": "CASHIER01",
              "expiresAt": "2026-10-06T22:43:51.000+08:00"
            }
          }
          ```
      - **接口四：店长手机端确认/驳回审批** `POST /admin/access/qr/confirm`
        - 权限：登录态店长
        - 请求体：
          ```json
          {
            "approvalCode": "QAP_1_...",
            "action": "AGREE",
            "rejectReason": ""
          }
          ```
        - 响应：
          ```json
          {
            "code": 0,
            "data": {
              "approvalCode": "QAP_1_...",
              "status": "APPROVED",
              "authorizerId": 5,
              "authorizerName": "张店长"
            }
          }
          ```
  12. **订单强制删除支持审批 Token**：`DELETE /order/delete/{id}`
      - 权限：`order:delete`（仅 `super_admin`，B 端 JWT 认证，无需 `X-Shop-Id`，可按订单主键跨门店删除）
      - 授权：**审批令牌优先、现场账号密码兜底**
        - 携带 `approvalToken`（由 `POST /cashier/access/authorize` 或扫码授权签发，120 秒有效、单次消费）时，
          服务端按门店、操作者、权限（`order:delete`）、订单号及终端（请求头 `X-Terminal-Id` 优先，请求体 `terminalId` 兜底）强绑定原子核销（CAS），核销失败返回业务码 `40321`「授权令牌无效、已过期或不匹配当前业务」；
          针对 `order:delete` 销毁型操作，服务端自适应兼容金额校验（若审批申请携带账单金额，核销时自适应对齐请求体 `amount` 或订单当前净营业额，避免因金额比对失配）；
        - 未携带令牌时请求体必须提供 `authorization`（`account`+`password`），授权员工须为 `super_admin` 且具备 `order:delete` 与订单所属门店范围，现场授权不签发或复用令牌。
      - 请求体示例（令牌模式）：
        ```json
        {
          "approvalToken": "3fa85f64...",
          "terminalId": "cashier-1790850256711580",
          "amount": 58.00
        }
        ```
      - 请求体示例（账号密码兜底模式）：
        ```json
        { "authorization": { "account": "MGR001", "password": "..." } }
        ```

## 堂食同桌加菜与桌台订单协同契约（v1.2.277）

- **背景与问题定位**：
  - 在小程序堂食多顾客就餐场景中，用户 A 下单后（`transac_status = 'unsettled'`, `dineInOrTakeOut = '堂食'`），同桌就餐的用户 B 打开小程序扫码或加菜：
    - `POST /order/addDishes` 因历史严格 openid 强校验拦截，提示 `403 无权给该订单加菜`；
    - `GET /order/get`（按桌号查当前未结账单）与 `GET /order/getOrder`（按单号查加菜后详情）因仅允许本人 openid 查看，拦截返回 `403` 或 `未找到相关订单`；
    - `GET /order/table-info/{tableNumber}` 因空桌或同桌点单未能正确关联桌台未结账堂食单而返回 403。
- **协同与安全边界规则**：
  1. **放行范围**：仅对**同门店**（`shop_id` 匹配）、处于**未结账状态**（`transac_status = 'unsettled'`）的**堂食订单**（`dineInOrTakeOut = '堂食'`）放行同桌同伴（提供同桌号）加菜与桌台点单状态查询；
  2. **加菜权限（`POST /order/addDishes`）**：
     - 请求人 `effectiveOpenid` 匹配原单创建者，放行；
     - 原单为未结账堂食单，且请求中提供的桌号与原单桌号一致（或未显式传桌号自动继承原单桌号），放行；
     - 加菜日志 `logOrder` 的操作人记录为实际操作人 `effectiveOpenid`，便于审计追溯；
     - 打包、外卖或已结账订单严禁跨用户加菜；
  3. **桌台订单查询（`GET /order/get`）**：
     - 若订单为未结账堂食订单，同桌同伴放行查询桌台实时点单菜品列表，避免同桌重复点单；
     - 已结账/已取消等历史账单仅限归属用户本人查看；
  4. **订单详情查询（`GET /order/getOrder`）**：
     - 本人订单放行；
     - 同门店未结账堂食订单放行；
     - 已结账订单若当前用户在日志中具有加菜记录（`action = 'add_dish'`），放行；其余返回 `403 无权查看该订单`；
  5. **桌台信息查询（`GET /order/table-info/{tableNumber}`）**：
     - 优先匹配当前用户的未结账订单；若无则匹配该桌台上同伴的未结账堂食订单；若均无则匹配当前用户最近历史单；仅在无未结账单且存在其他陌生人历史单时返回 403。

## 统一出票与补打调度接口契约（v1.2.276 / Unified Print Dispatch）

- **背景与需求目标**：
  - 前端各端（收银机、移动管理端、前台等）此前需要根据不同场景（后厨、结账单、整单、交接班、传菜等）调用不同的打印接口，参数各异且逻辑碎片化；
  - 统一打印接口：前端无论何种业务场景、无论是否补打，均统一调用单一接口即可出票；对于最常见的补打厨房小票，前端仅需传入订单号即可全自动推导并打印出票。
- **接口路径与鉴权**：
  - **收银机出票调度**：`POST /cashier/print/dispatch`（权限：`cashier:operate`，支持收银机 Token 与 X-Shop-Id 上下文）；
  - **管理端出票调度**：`POST /admin/printing/dispatch`（权限：`printing:manage`，需管理员登录与 X-Shop-Id 上下文）；
  - **向后兼容性**：保留旧版 `POST /cashier/print/kitchen`，内部直接委托统一出票调度服务。
- **请求参数模型（`UnifiedPrintRequest`）**：
  - `order_no`（String，可选，支持 `orderNo` / `order_sn`）：订单流水号；
  - `order_id`（Long，可选，支持 `orderId` / `id`）：订单数据库主键；
  - `scenario`（String，可选）：出票场景编码。可选值：`kitchen`（厨房小票）、`checkout`（结账单）、`pre_checkout`（预结单）、`full_order`（前台整单）、`packing`（打包单）、`takeout`（外卖单）、`expedite`（传菜单）、`refund`（退款单）、`shift`（交接班报表）、`label`（标签/杯贴）、`test`（测试小票）；**若不传且提供订单信息，后端全自动智能推导为 `kitchen`（厨房小票）**；
  - `is_reprint`（Boolean，可选，默认 `true`）：是否为补打单据。为 `true` 时，小票自动印上【补打】醒目标识、操作人与补打时间；
  - `cid_list`（List<String>，可选，支持 `cidList` / `cids`）：后厨分类过滤列表，指定时仅针对包含对应分类菜品拆单出票；
  - `shift_id`（Long，可选，支持 `shiftId`）：交接班记录 ID（针对交接班小票场景，未传时默认取当前门店最新活跃班次）；
  - `device_id`（Long，可选，支持 `deviceId`）：定向出票设备 ID，指定时覆盖出票规则直接发往该设备；
  - `template_id`（Long，可选，支持 `templateId`）：定向模板 ID，指定时覆盖默认模板；
  - `copies`（Integer，可选，1-9）：单据出票联数覆盖；
  - `reason`（String，可选）：补打原因/说明；
  - `custom_content`（String，可选）：自定义小票文本内容；
  - `idempotency_key`（String，可选）：幂等防重键。
- **极简调用示例（补打后厨小票）**：
  ```json
  POST /cashier/print/dispatch
  {
    "order_no": "2026100512300001"
  }
  ```
- **响应体模型（`UnifiedPrintResponse`）**：
  ```json
  {
    "code": 200,
    "msg": "成功下发 1 个打印任务",
    "data": {
      "order_no": "2026100512300001",
      "scenario": "kitchen",
      "scenarioName": "厨房小票",
      "is_reprint": true,
      "job_count": 1,
      "success_count": 1,
      "failed_count": 0,
      "summary": "成功下发 1 个打印任务",
      "jobs": [
        {
          "job_id": 10502,
          "device_id": 3,
          "device_name": "后厨档口打印机",
          "transport": "CLOUD",
          "status": "SENT",
          "success": true,
          "error": null
        }
      ]
    }
  }
  ```
- **核心业务逻辑与防御机制**：
  1. **极简极智**：只需传订单号或订单ID，自动补齐订单信息、菜品明细（过滤已退菜行，仅保留 NORMAL 菜品）、桌号、就餐方式、外卖配送地址及门店上下文；
  2. **门店数据隔离（Shop Scope Guard）**：跨店订单严格拦截并抛出 `403 SHOP_SCOPE_MISMATCH`，防越权打印；
  3. **补打防篡改水印**：补打单据自动解析真实操作人姓名（优先员工真实姓名，次之用户名）与补打时间，并在小票抬头与模板变量中注入 `【补打】` 醒目标识；
  4. **全场景出票内核统一**：基于底层 `PrintDispatcherService` 驱动，支持云打印（飞鹅云服务端直发）与端侧打印（本地驱动/网络/蓝牙/USB通过收银机代理轮询消费），统一流水追踪与任务审计；
  5. **结账单状态强校验（Checkout Status Enforcement）**：
     - **业务规则**：结账单打印必须订单结账后才能打印，未结账订单只能打印预结单；
     - 当请求打印结账单（`scenario = checkout`，含旧别名 `receipt`/`bill`）且关联订单时，强校验订单支付状态 `order.getTransac_status() == "success"`；
     - 若订单尚未结账，统一调度服务及底层出票引擎严格拦截出票，抛出 HTTP 400 业务异常，错误码 `ORDER_NOT_CHECKED_OUT`，错误信息：`"订单尚未结账，不能打印结账单，未结账订单只能打印预结单"`；
     - 未结账订单核对账单请传 `scenario: pre_checkout` 打印预结单（小票抬头为 `【预结单(非结账凭据)】`，不展示实付渠道），调度引擎已支持预结单自动回退匹配前台结账小票机出票规则。

## 员工账号管理体系升级、工号登录与全局操作人真实姓名展示契约（v1.2.275）

- **背景与需求目标**：
  - 优化完善管理账号体系，采用员工工号进行登录与身份标识；
  - 员工实体扩展员工姓名（`real_name`）、岗位（`job_title`）、工号（`work_no`）；
  - 全局所有涉及“操作人”的展示场景统一以员工真实姓名展示（回退至用户名），涵盖审计日志、操作日志、订单日志、日结报表、当班交班、钱箱会话及订单详情等。
- **契约行为规范**：
  - **工号登录（`POST /adminLogin`）**：
    - 入参新增可选 `workNo`（工号），优先通过 `work_no` 查找管理员；
    - 向后兼容历史客户端传参 `userName`（先尝试按工号匹配，未命中再按 `userName` 匹配）；
    - 响应体与当前权限接口（`GET /admin/me/permissions`）同步返回 `workNo`、`realName`、`jobTitle`、`displayName`（优先姓名，次之用户名）、`name`；
  - **管理端与收银端员工档案管理 CRUD 闭环**：
    - `POST /admin/administrator/create`：支持传入 `workNo`、`realName`、`jobTitle`，若提供工号则严格校验全局唯一性；支持同时传入 `shopIds` 完成门店绑定；
    - `PUT /admin/administrator/{id}`：新增更新管理员/员工基础资料接口，支持维护工号（唯一性校验）、真实姓名、岗位，以及可选重置密码；
    - `DELETE /admin/administrator/{id}` 与 `DELETE /admin/access/employees/{adminId}`：删除员工/管理员账号接口，具备防删自身安全校验、级联清理角色及门店关联，并写入权限审计日志；
    - `GET /admin/administrator/list` 与 `GET /admin/access/employees`：列表项统一包含 `workNo`、`realName`、`jobTitle`、`displayName`、`name`，并支持按用户名/工号/姓名/岗位多字段模糊搜索；
  - **全局操作人统一显示为真实姓名**：
    - **当班与钱箱会话（Drawer Session / Cashier Shift）**：
      - `POST /cashier/shift/start`、`POST /cashier/shift/handover`、`GET /cashier/shift/current`：返回项 `operator_name`、`opened_by_name`、`closed_by_name` 及 `Shift.admin_name` 统一填充员工真实姓名；
      - `DrawerSessionServiceImpl.getShiftSummaryReport`、`getWorkbench`、`listCashEvents`：开班人、交班人、审批人及动作操作人统一解析为员工真实姓名；
    - **日结与商业 Z 报表（Daily Close / Z-Report）**：
      - `DailyCloseServiceImpl.settle` 与 `generateZReport`：快照与返回结构体中的 `operator_name`、`reviewer_name`、`reopened_by_name` 全部由 `AdminNameResolver` 统一解析为真实姓名；
      - 钱箱汇总（`drawer_summary.sessions[]`）及调整项（`adjustments[]`）中的操作人统一以姓名输出；热敏小票打印文本格式补充展示操作人姓名；
    - **日志审计（Logs）**：
      - `GET /admin/logs`（`AdminLogService`）与 `GET /admin/log/operation`（`AdminOperationLogController`）：`adminName` 与 `operator_name` 批量联查回填真实姓名；
      - `GET /admin/order/log/{orderId}`（`AdminOrderLogController`）：订单操作日志自动回填 `operator_name` 为员工真实姓名；
      - `GET /admin/order/list`（`AdminOrderController`）：订单列表按需批量回填 `order_admin_name`（开单人真实姓名）。

## 换台与并台业务缺陷修复及收银整桌结账契约（v1.2.273）

- **背景与痛点消除**：
  - **缺陷 1 (高)**：此前 `GET /order/table-info/{tableNumber}` 无差别获取该桌最新订单，在多单并台后，先点餐顾客扫码或刷新时因获取到其他顾客订单而触发 `403 无权查看该桌订单`；
  - **缺陷 2 (高)**：换台/并台操作缺少向打印机下发【变动通知小票】，后厨与传菜员无法获知桌号变更，容易造成送错桌；
  - **缺陷 3 (中)**：收银端此前仅支持单笔订单逐笔结账，缺乏整桌所有未结订单一键结账能力；
  - **缺陷 4 (中/低)**：换台 `transfer` 当源桌所有未结单均被移走变为空闲时，遗漏清理历史已结账单的接单状态；并台清理源桌时也存在类似遗漏。
- **契约行为规范**：
  - **C 端扫码桌台详情精准匹配（`GET /order/table-info/{tableNumber}`）**：
    - 接口自动从认证上下文解析顾客 `openid`；
    - 优先查找当前桌属于该用户的未结账订单（`transac_status = 'unsettled'`）；若无未结账单则匹配该用户的历史最近订单；
    - 仅当该桌存在其他顾客订单且当前用户在该桌无任何订单时返回 `403`；空桌或无订单时返回 `500`（未找到该台号订单），杜绝误报权限拒绝；
  - **换台/并台物理小票派发**：
    - 换台与并台在事务提交后（`AfterCommitExecutor`）异步派发变动通知小票至后厨制作打印机（`kitchen`）和前台/传菜打印机（`expedite`）；
    - 小票内容含操作类型、原桌号、新桌号、关联订单号、操作时间与醒目提示，未配置打印机时安全跳过；
  - **收银整桌批量结账（`POST /cashier/table/checkout`）**：
    - 入参：`tableNumber`（桌号，必填）、`paymentMethod`（支付方式，默认 `cash`）、`cashAmount`（现金实收，用于找零）；
    - 自动锁定并遍历该桌所有未结订单，复用权威结账核心逐笔完成财务入账、优惠券核销与出票，现金支付时自动对末笔单完成找零结算；
    - 响应：返回 `tableNumber`、`settledOrders`、`totalAmount`、`cashAmount`、`changeAmount` 及最新 `table` 状态；
  - **源桌历史单接单状态结清**：
    - 换台当源桌所有未结单移走变为空闲时、以及并台清源桌时，统一调用 `operationMapper.finishSettledOrdersOnTable` 确保已结单归档置为 `off_order`；
  - **并台从单禁止单独结账、仅支持主桌统一结账（v1.2.274）**：
    - 并台后源桌所有未结订单作为从单并入目标主桌，`t_order.master_order_no` 字段记录主单号；
    - 从单禁止通过任何单笔结账入口买单（包括收银单单结账 `POST /cashier/order/checkout`、管理端结账 `POST /admin/order/checkout`、C 端微信预支付 `POST /order/getPrepayId`、C 端余额支付 `POST /order/payByBalance`），均统一拦截并返回：`该订单为并台从单，不支持单独结账，请通过主桌统一结账`；
    - 主单在桌台仍有未结从单时同样禁止单独结账，拦截提示：`该桌台存在并台从单，不支持单笔结账，请通过主桌统一结账`；
    - 结算唯一合法路径为通过主桌统一结账（`POST /cashier/table/checkout`，传入主桌台号批量完成整桌结算）；
    - 若订单通过换台（`POST /cashier/table/transfer`）移至新桌，自动解除并清空 `master_order_no`。

## 收入渠道拆分微信/支付宝收款码契约（v1.2.272）

- 日结预览、Z 报表及交班报告的结构化 `channels[]` 新增稳定渠道代码 `wechat_qr`（微信收款码）和 `alipay_qr`（支付宝收款码）；普通线上渠道继续使用 `wechat` 和 `alipay`。
- 渠道判断优先读取订单或支付记录的 `payment_method`：`微信收款码`/`微信收款码自动` 归入 `wechat_qr`，`支付宝收款码`/`支付宝收款码自动` 归入 `alipay_qr`。因此历史账本即使仅记录通用 `WECHAT`/`ALIPAY`，报表也会按关联订单的收款方式正确拆分。
- 新收银结账和历史账本回填分别写入 `WECHAT_QR`/`ALIPAY_QR`，普通微信/支付宝仍写入 `WECHAT`/`ALIPAY`；影子核验继续按微信、支付宝渠道族合计，避免拆分后产生虚假差异。
- `GET /admin/daily/income` 与 `GET /admin/daily/byChannel` 的 Map 键使用稳定中文渠道名，新增 `微信收款码`、`支付宝收款码`；手动和自动收款码合并到同一渠道。
- `GET /admin/report/dashboard` 的 `data.businessDay.revenueByPayChannel` 渠道由原五类升级为七类，新增 `wechat_qr`（微信收款码）与 `alipay_qr`（支付宝收款码）；底层按订单 `payment_method` 精准拆分收款码与普通线上支付金额，完美支撑收银端当班工作台「今日支付渠道概览」完整展示各渠道实收。

## 管理端订单列表默认时间范围对齐营业日契约（v1.2.271）

- **背景与痛点消除**：
  - 调用 `POST /admin/order/list` 查询订单列表时，若前端未传入 `startTime` 和 `endTime` 参数，过去代码默认取“昨日 00:00:00 至今”，导致夜间跨天营业（如营业至凌晨 02:00/03:00）或早班查看时，与今日指标 `todayCount` 以及门店营业日结算窗口口径不一致；
  - 门店业务统一以 `settle_time` 为班次分界线，应与财务日结、今日单量对齐为相同的营业日窗口。
- **契约行为规范**：
  - **默认时间窗口**：当请求体未传入 `startTime` 与 `endTime`（或为空白）时，统一按 `[D settle_time, D+1天 settle_time)` 范围获取：
    - 若当前时间在 `settle_time` 之前，营业日 `D` 归属前一天，窗口为 `[前一日 settle_time, 今日 settle_time)`；
    - 若当前时间在 `settle_time` 之后，营业日 `D` 归属当天，窗口为 `[今日 settle_time, 次日 settle_time)`；
  - **门店 settle_time 解析与兜底**：自动优先读取当前请求门店的 `settle_time` 配置；未配置或未绑定门店时安全兜底默认 `04:00`；
  - **单测覆盖与防退化**：通过 `OrderListTimeRangeResolverTest` 与 `AdminOrderControllerTodayUnsettledTest` 全面验证凌晨、日间、自定义结算时间及 Controller 层默认下发逻辑。

## 日结预检修复 Order 字段名与未结订单检查缺陷契约（v1.2.270）

- **背景与缺陷根因**：
  - 调用 `GET /admin/daily/pre-check?stat_date=YYYY-MM-DD` 执行日结预检时，服务端报 HTTP 500 `DAILY_PRECHECK_FAILED`（日结预检失败）；
  - 根因：`DailyCloseServiceImpl.precheck` 第 2 步检查未结账订单时，`QueryWrapper<Order>` 误在 `t_order` 上查询不存在的列 `order_status`（`.in("order_status", 1, 2)`）；
  - MySQL 执行时抛出 `Unknown column 'order_status' in 'where clause'`（`BadSqlGrammarException`），导致日结预检报错中断。
- **契约行为规范**：
  - **状态列修正**：标准统一使用 `t_order.transac_status = 'unsettled'` 判定未结账订单，与收银及后台统计口径完全一致，移除对不存在的 `order_status` 列的查询；
  - **商户号匹配规范**：`merchantId` 统一对齐实体类 String 规格使用字符串 `"1"` 传参；
  - **单测覆盖与防退化**：通过 `ArgumentCaptor` 强校验 SQL 片段不包含 `order_status` 且包含 `transac_status` 与 `merchantId`。

## 日结预检修复 PaymentLedger 字段名缺陷契约（v1.2.269）

- **背景与缺陷根因**：
  - 调用 `GET /admin/daily/pre-check?stat_date=YYYY-MM-DD` 执行日结预检时，服务端报 HTTP 500 `DAILY_PRECHECK_FAILED`（日结预检失败）；
  - 根因：`DailyCloseServiceImpl.precheck` 第 3 步检查待确认（PENDING）支付/退款流水时，`QueryWrapper<PaymentLedger>` 误将时间列写为不存在的 `transac_time`（`ge("transac_time", win[0]).lt("transac_time", win[1])`）；
  - MySQL 执行时抛出 `Unknown column 'transac_time' in 'where clause'`（`BadSqlGrammarException`），导致预检直接中断报错。
- **契约行为规范**：
  - **列名修正**：统一将 PENDING 流水时间范围过滤修正为不可变账本标准时间列 `occurred_at`（`occurred_at >= win[0] AND occurred_at < win[1]`）；
  - **可观测性增强**：在 `AdminDailyController` 中引入 Logger，在预检与关账捕获非业务未知异常时输出完整堆栈，并向前端返回详细异常原因，避免问题被黑盒掩盖。

## 历史订单账本回填与双写影子切读契约（v1.2.268 / POS-SDC-501 ~ POS-SDC-503）

- **背景与痛点消除**：
  - 在升级不可变支付台账（`t_payment_ledger`）后，历史存量订单缺少对应的结构化资金流水，导致交班历史、日结历史及渠道对账如果直接切读新账本会出现历史数据断崖；
  - 过去旧代码在渠道明细查询（`GET /admin/daily/byChannel`）中直接读取孤立的 `t_payment` 表，而收银结账事务从未向该表写入数据，造成渠道统计长期失真；
  - 缺乏平滑切换与影子核验机制，直接切流存在财务风险。
- **历史订单账本回填（`POST /admin/migration/ledger/backfill`，POS-SDC-501）**：
  - **幂等补齐与数据源标注**：
    - 对已结历史订单进行幂等扫描，根据渠道列（`pay_amount_cash/wechat/alipay/balance/gift`）拆解并批量插入 `t_payment_ledger`；
    - 强制标记 `source = 'BACKFILLED_ORDER'`，不得伪装成原生支付事件；
    - 无法证明操作人与收银机终端时保持 `operator_id = null`, `terminal_id = 'UNKNOWN'`；
    - 针对已存在台账流水的订单自动跳过（`skipped_orders`），支持多次重复执行。
  - **恒等式与可信等级校验**：
    - 核验 $\sum \text{channels} = \text{OrderNetRevenue.netRevenueFen(order)}$：
      - 恒等式吻合：标注 `trust_level = 'TRUST_HIGH'`；
      - 恒等式不吻合：标注 `trust_level = 'TRUST_SUSPECT'`，自动收集进入 `anomalies` 异常单清单，杜绝静默抹平。
  - **干跑演练（Dry-Run）与 SHA-256 防篡改审计**：
    - 支持 `dry_run = true` 仅扫描、复算恒等式并输出演练报告，不执行物理入库；
    - 回填执行生成 SHA-256 防篡改摘要哈希并落库 `t_ledger_backfill_log`。
- **双写影子验证（`GET /admin/migration/ledger/shadow-verify`，POS-SDC-502）**：
  - 对指定营业日进行旧订单口径（`t_order`）与新台账口径（`t_payment_ledger`）对碰：
    - 逐笔对比订单应付净额与台账流水实收净额；
    - 分渠道（现金、微信、支付宝、会员余额、赠送金）对比差额；
    - 当净差额为 0 且无单据级不一致时，输出 `ready_for_cutover = true`。
- **数据读源平滑切读与回退（`GET /admin/migration/ledger/status`、`POST /admin/migration/ledger/cutover`，POS-SDC-502）**：
  - 支持按门店维度通过 `t_system_config`（`finance.ledger.read_source`）原子切换读源：
    - `PAYMENT_LEDGER`：标准商业级不可变支付台账（默认）；
    - `LEGACY_ORDER`：历史兼容订单只读回退模式。
  - 回退机制：若发现异常，仅切换配置读源，绝不物理删除新账本数据。
- **旧路径退役（POS-SDC-503）**：
  - `GET /admin/daily/byChannel` 全面弃用旧 `t_payment` 孤立表读取，默认切换至 `t_payment_ledger` 实时流水聚合；仅在显式配置 `LEGACY_ORDER` 时提供只读回退兼容。

## 渠道对账单导入与三层差异处理单契约（v1.2.267 / POS-SDC-401 ~ POS-SDC-402）

- **背景与痛点消除**：
  - 过去系统对账仅限于内部订单与流水比较，未打通微信支付/支付宝官方商户对账单或 POS 第三方对账单的导入与勾兑，导致外部手续费扣除、跨日到账延迟、漏记单等情况无法自动化识别；
  - 过去若未导入外部对账单，系统页面可能静默显示“已平”，违反了严格商业审计原则；
  - 过去发现账实不符时无标准化差异工单跟踪，缺少责任人指定、流转状态机与平账结案凭证。
- **渠道对账单安全导入（`POST /admin/reconciliation/import`，POS-SDC-401）**：
  - **多渠道格式支持**：
    - 支持微信支付商户对账单（CSV，自动过滤 `#` 汇总尾部行，智能剥离以反引号 `` ` `` 开头的文本包装，提取交易状态、应收/实收/退款及手续费）；
    - 支持支付宝商户对账单（CSV/JSON）；
    - 支持通用 POS 标准 CSV 对账单（包含交易时间、渠道、商户单号、渠道流水号、金额、类型、手续费）。
  - **SHA-256 哈希防重导入**：
    - 对导入内容计算 SHA-256 摘要（`sha256_hash`），同一门店内同哈希文件禁止重复导入，返回 HTTP 409 冲突。
  - **解析与审计落库**：
    - 批次落库 `t_channel_statement_batch`，记录渠道、文件名、哈希、总笔数、成功笔数、错误笔数、手续费总额等；
    - 明细落库 `t_channel_statement_entry`，保存标准化条目（`channel_entry_no`、`trade_time`、`order_no`、`channel_trade_no`、`entry_type`、`amount_fen`、`fee_fen` 等）。
- **三层全景差异检测（`GET /admin/reconciliation/overview`，POS-SDC-402）**：
  - **未导入外部账单硬性门禁（Crucial Core Rule）**：
    - 若指定营业日未导入任何渠道对账单，`has_channel_statement = false`，`summary_status = UNIMPORTED`，**绝不可显示或声明“已对平”**。
  - **三层核对结构**：
    - **第 1 层：订单 vs 内部支付台账（`layer1_order_vs_ledger`）**：核对 `t_order` 应收实收与 `t_payment_ledger` 内部台账流水是否一致（`is_balanced`、`diff_amount_fen`）；
    - **第 2 层：内部台账 vs 渠道对账单（`layer2_ledger_vs_channel`）**：双向对比内部台账流水与外部渠道账单条目，识别漏单（内部有渠道无 / 渠道有内部无）、金额不符及时间差；
    - **第 3 层：渠道账单 vs 净到账结算（`layer3_channel_vs_settlement`）**：核对渠道账单交易总额扣减平台手续费（`total_fee_fen`）后与银行/资金户实际到账净额（`net_payout_fen`）是否相符。
- **差异处理单状态机流转与平账（`GET /admin/reconciliation/cases`、`POST /admin/reconciliation/cases/{id}/resolve`，POS-SDC-402）**：
  - **差异案件状态机**：`OPEN`（待处理） -> `INVESTIGATING`（调查中） -> `ADJUSTED`（已调账） / `WRITTEN_OFF`（已坏账核销） / `CLOSED`（已结案）；
  - **差异类型标识**：
    - `INTERNAL_MISSING`：内部漏单（渠道有单但系统无记录）；
    - `CHANNEL_MISSING`：渠道漏单（系统有单但渠道无记录）；
    - `AMOUNT_MISMATCH`：金额不符（单号匹配但金额差异）；
    - `TIMING_DIFFERENCE`：跨日时差（跨午夜或结算窗口记账）；
    - `ORDER_LEDGER_MISMATCH`：内部订单与台账差异。
  - **审计平账留痕**：
    - 处理时记录责任人（`responsible_person`）、处理说明（`resolution_note`）、操作人（`resolved_by`）与处理时间（`resolved_at`），形成完整可溯源闭环。

## UI061 账单管理中心与全景详情服务契约（2026-10-25）

### 1. 电子发票开具二维码生成接口 (`POST /admin/order/invoice/qrcode`，权限 `order:operate`)
- **业务场景**：收银员在账单详情顶栏点击「🧾 电子发票」，向税控服务申请生成本次交易的开票流水号及顾客自助扫码开票二维码。
- **请求参数**：
  - `orderNo`: 订单号（必填）
  - `tableNumber`: 桌台号（可选）
  - `invoiceAmount`: 申请开票金额（可选，不可超过订单实付金额）
  - `taxRate`: 税率（可选，默认 0.06）
- **响应数据**：
  - `orderNo`: 订单号
  - `invoiceStatus`: 开票状态（`PENDING_SCAN`）
  - `invoiceQrUrl`: 二维码 URL（含订单号与单次防伪凭证）
  - `invoiceAmount`: 最终开票金额
  - `taxRate`: 税率
  - `expireMinutes`: 有效期（默认 1440 分钟 / 24小时）
  - `notice`: 顾客扫码开票提示文案

### 2. 全流程细粒度审计日志追踪接口 (`GET /admin/order/audit-timeline/{orderNo}`，权限 `order:view`)
- **业务场景**：用于账单全景详情面板底部的「全流程审计追踪条」，展示该单生命周期的全部核心节点。
- **路径参数**：`orderNo` 订单号
- **响应数据**：
  - `orderNo`: 订单号
  - `events`: 按时间升序排序的事件列表，包含：
    - `time`: 节点时间戳（`yyyy-MM-dd HH:mm:ss`）
    - `action`: 动作类型码（`CREATE_ORDER`/`ADD_DISH`/`KITCHEN_PRINT`/`PAY_SUCCESS`/`CASH_DRAWER_OPEN`/`REFUND`/`UNCHECKOUT`）
    - `description`: 描述说明（例如开台人数/桌号、后厨出票菜品数、入账渠道/实收金额/商户流水号、钱箱开启脉冲触发、退款或反结账原因）
    - `operator`: 操作人（收银员姓名、KDS引擎、外设驱动或店长）

### 2.1 财务开票申请分页列表接口 (`GET /admin/order/invoice/list`，权限 `order:view|order:invoice:view`)
- **业务场景**：财务人员在工作台查看开票申请列表，支持默认筛选待开票（`TITLE_SUBMITTED`）记录，支持按订单号、抬头名称、手机号模糊搜索与日期范围筛选。
- **请求参数**：
  - `page`: 当前页码（默认 1）
  - `limit`: 每页条数（默认 10）
  - `status`: 开票状态（可选：`TITLE_SUBMITTED`、`SUCCESS`、`REJECTED`、`PENDING_SCAN`）
  - `keyword`: 搜索关键词（支持订单号、发票抬头、手机号模糊匹配）
  - `startDate` / `endDate`: 申请日期范围
  - `shopId` / `shop_id`（可选，亦支持 `X-Shop-Id` 请求头）：目标门店 ID；未传时总部账号汇总查询全部门店开票数据
- **响应数据**：
  - `total`: 记录总数
  - `page` / `limit`: 分页信息
  - `list`: 申请列表明细（含订单号、金额、所属门店纳税主体名称 `shop_name`、门店编码 `shop_code`、门店地址 `shop_address`、所属官方电子税局门户 `tax_bureau_name` 及入口 URL `tax_bureau_url`、抬头、完整税号、联系方式、状态、微信卡包插卡状态 `card_insert_status`、卡包说明 `card_insert_msg`、发票号等）
  - `metrics`: 关键指标统计（`countWaiting`, `countSuccess`, `countRejected`, `countPendingScan`）

### 2.2 财务开票申请驳回接口 (`POST /admin/order/invoice/reject`，权限 `order:operate|order:invoice:operate`)
- **业务场景**：财务核对发现发票税号或抬头信息有误时，录入驳回原因并将状态流转至 `REJECTED`。顾客端 H5 将展示驳回原因并支持重新修改提交。
- **请求参数**：
  - `orderNo`: 订单编号（必填）
  - `rejectReason`: 驳回原因说明（必填，例如税号位数不符等）
- **响应数据**：
  - `code`: 200
  - `msg`: "开票申请已驳回"

### 2.3 财务手动重试发票推送到用户微信卡包接口 (`POST /admin/order/invoice/insert-card`，权限 `order:operate|order:invoice:operate`)
- **业务场景**：财务确认开票后，系统自动通过微信支付 APIv3 新税控电子发票通道（`POST /v3/new-tax-control-fapiao/fapiao-applications/{id}/insert-cards`）插卡交付至顾客微信卡包。若遇网络超时或商户电子发票权限问题导致插卡未成，财务可在工作台单笔点击重试推送到用户微信卡包。
- **请求参数**：
  - `orderNo`: 订单编号（必填）
- **响应数据**：
  - `code`: 200
  - `msg`: "已成功推送到微信卡包"
  - `cardStatus`: "SUCCESS" 或 "FAILED"
  - `cardMsg`: 卡包处理结果说明

### 3. 会员大数据画像智能标签推荐接口 (`GET /admin/member/persona-tags`，权限 `user:view`)
- **业务场景**：用于账单详情右侧会员画像卡片的 Chip 标签组。
- **请求参数**：`phone`（手机号，可选）、`memberId`（会员ID，可选）、`orderShopScope`（门店范围，默认 `accessible`）
- **响应数据**：
  - `memberId`: 会员 ID
  - `phone`: 会员手机号
  - `tags`: 结构化 Chip 标签列表：
    - `label`: 标签文本（如 `🔥 高频熟客 (月均4+次)`、`🥩 偏好招牌油边(精选微辣)`、`🍺 必点特醇鲜啤(1L)`、`🪑 偏爱A区散座靠窗`、`⏱️ 常在18:00~19:30就餐`、`⚡ 无忌口/出餐速度敏感`）
    - `type`: 标签分类类型（`frequency`/`taste`/`drink`/`seat`/`time`/`behavior`）

## 商业级日结快照、前置检查阻断器与 Z 报表契约（v1.2.266 / POS-SDC-301 ~ POS-SDC-304）

### WI-069 日结页面统一上下文聚合接口与参数别名兼容（2026-10-25）

- **统一上下文接口 `GET /admin/daily/context`（权限 `daily:settle|report:view`）**：
  - 单次调用返回日结工作台所需全部数据，彻底消除以往前端分散并发调用 `pre-check`、`summary`、`byChannel` 导致的参数不一致、多重网络延迟与数据不对称问题。
  - 请求参数：`stat_date`（目标结算日，可选）、`date`（别名，可选）、`minutes`（超时未支付外卖阈值分钟数，默认 30）。
  - 若目标营业日已结（已归档快照）：
    - 返回 `is_already_settled: true`、`can_settle: false`、`can_reopen`（仅最后一张快照营业日为 true）。
    - 财务总览 `summary` 来自历史快照固化数据；渠道实收 `channels`（Map）与 `channel_details`（结构化 List）自动解析自快照中保存的不可变渠道 JSON；
    - 关联返回 `existing_snapshot_no`、`settled_at`、`closed_at` 以及日结后调整单列表 `adjustments`。
  - 若目标营业日未结：
    - 返回 `is_already_settled: false`；
    - 实时运行预检阻断逻辑，返回 `can_settle`、`blockers`、`warnings`、`precheck_token`、`precheck_expires_at`、`watermarks`、`voidable_stale_pack_takeout`；
    - 实时聚合返回权威统一财务 `summary`（销售额、折扣、退款、净额、原材料成本、钱箱长短款等）与多渠道分布 `channels`、`channel_details`。
- **全系列日结接口参数别名双向兼容**：
  - 日结端点 `GET /admin/daily/context`、`GET /admin/daily/pre-check`、`GET /admin/daily/summary`、`GET /admin/daily/byChannel`、`GET /admin/daily/income`、`GET /admin/daily/grossProfit` 现已全面统一支持 `stat_date` 与 `date` 双向互通别名（解析优先级：`stat_date` > `date`）。
  - 无论前端传 `date` 还是 `stat_date`，服务端均能准确落入同一个营业日窗口，防止因传参名不一致导致部分接口回退到“当前班次”引发的数据失真。

### WI-067 日结严格时序与历史补结（2026-10-25）

- 门店一旦存在首张日结快照，服务端以该日为序列锚点，逐日查找最早的缺失或 `REOPENED` 营业日；未传 `stat_date` 的 `GET /admin/daily/pre-check` 自动返回该日，禁止直接跳到当前营业日。
- 预检响应新增 `current_business_day`、`next_close_business_day`、`pending_day_count`、`has_previous_unclosed_day`。显式请求非最早待结日或未来营业日时，返回 HTTP 409 `DAILY_CLOSE_OUT_OF_SEQUENCE`，`data` 包含 `expected_business_day/requested_business_day/current_business_day`；`force=true` 不能绕过时序。
- `POST /admin/daily/settle` 在串行化事务内再次校验时序。首次启用且门店尚无任何快照时，允许首个显式日期作为兼容锚点，避免强制追溯系统上线前全部历史。
- 钱箱、订单、支付、充值、应收及预检水位均按目标营业窗口校验；后续营业日产生的数据不会阻断前一日补结。
- `POST /admin/daily/reopen` 只允许重开最后一个快照营业日；否则返回 HTTP 409 `DAILY_REOPEN_OUT_OF_SEQUENCE`。`REOPENED` 日再次日结时更新原快照行并保留重开审计字段，不插入同一门店/营业日的重复快照。
- `POST /admin/daily/void-stale-takeout-orders` 复用同一时序约束；`GET /admin/daily/z-report` 未传日期时默认展示最早待结营业日，显式历史日期仍可查询。

### WI-068 历史 Z 报表日结状态时序（2026-10-25）

- `GET /admin/daily/z-reports` 不再只返回已有 `CLOSED` 快照，而是从门店首张快照营业日起至当前权威营业日，按日期倒序连续返回；缺失日期标记为 `PENDING`，重开快照标记为 `REOPENED`。
- 每项新增 `close_state`、`can_close`、`is_next_close_business_day`。只有服务端权威 `next_close_business_day` 对应的未结项 `can_close=true`；前端可用该项 `business_day` 进入日结页，后续 pre-check/settle 仍会强制校验时序。
- 响应顶层新增 `current_business_day`、`next_close_business_day`、`pending_day_count`。未结项没有快照，`id/snapshot_no/closed_at` 等快照字段可以为 `null`，不得伪造财务数据。
- `cursor` 继续是客户端不可解释的 long 型不透明游标；新响应以 `yyyyMMdd` 编码本页最后营业日，请求时作为排他上界。迁移期间后端仍接受旧快照 ID 游标；客户端必须只原样回传 `next_cursor`。

### UI013 当班/日结协调增量（2026-10-04）

- `GET /admin/daily/pre-check` 只有 `can_settle=true` 时返回 `precheck_token` 与带时区的 `precheck_expires_at`；token 有效期 5 分钟，绑定操作人、门店、营业日与支付/现金/订单三水位。
- `POST /admin/daily/settle` 重新校验上述信息；过期/无效返回 HTTP 409 `PRECHECK_EXPIRED`，水位变化返回 HTTP 409 `WATERMARK_CHANGED`，不同幂等键重复日结返回 HTTP 409 `DAILY_ALREADY_SETTLED`。业务异常响应同时提供兼容字段 `error` 与规范字段 `error_code`。
- `preview` 的权威金额字段为 `gross_sales_fen/discount_amount_fen/refund_amount_fen/net_sales_fen/cash_variance_fen`；`channels[]` 固定为 `code/label/success_count/refund_count/net_amount_fen`。`/admin/daily/byChannel` 保留旧 Map 用于兼容，UI013 以 `preview.channels` 为唯一权威源。
- `GET /cashier/shift/current` 的历史 `previewExpected` 参数不再生效；未交班时，班次报告和现金流水均以 409 `SHIFT_NOT_CLOSED` 拒绝，防止推导 `expected_cash`/`variance`。
- 新增 `GET /cashier/shift/workbench`、`GET /cashier/shift/reports`、`GET /cashier/shift/{sessionId}/cash-events`、`GET /admin/daily/z-reports`；历史列表使用 `cursor/limit` 分页，`limit` 范围 1~100，`items` 元素包含 `operator_id` 与 `operator_name`（员工真实姓名）。
- 班次报告增加 `operator_name/terminal_name/drawer_name/duration_seconds/channels/audit_events/integrity/approval_status/approved_by_name/approved_at`；Z 报表增加顶层 `watermarks`，`drawer_summary.sessions` 使用固定整数分 schema。
- 开班、交班、现金动作与日结支持 `idempotency_key`（兼容旧 `request_id`）；财务写入响应增加 `trace_id`、`business_no`、`server_time`。

### WI-006 会员充值纳入当班与日结（2026-10-09）

- 后台人工充值若存在当前操作员的活动班次，服务端自动记录 `operator_id` 与 `drawer_session_id`；客户端不能自行指定归属。无活动班次时充值仍成功并进入门店日结，但不会被猜测分配给个人班次。
- `GET /cashier/shift/current`、`POST /cashier/shift/handover` 返回的报告、`GET /cashier/shift/report/{sessionId}` 与历史交班报告新增 `member_recharge_summary`：`success_count`、`principal_fen`、`gift_fen`、`credited_total_fen`；`GET /cashier/shift/workbench` 在 `current_shift.member_recharge_summary` 返回同口径数据。个人班次只统计显式归属该钱箱会话的成功人工充值。
- 日结 `pre-check.preview`、`settle.snapshot`、X/Z 报表和历史 Z 报表纳入门店营业窗口内 `status=success` 的充值。`member_recharge_fen`/`principal_fen` 是实际收取本金；赠送额单列，不计营业实收；`total_collections_fen = net_sales_fen + principal_fen`。
- 日结预检凭据除支付、现金、订单水位外，还绑定 `member_recharge_id` 与成功充值数量。预检后充值创单成功或待支付转成功时，关账返回 `409 WATERMARK_CHANGED`，要求重新预检。

- **背景与痛点消除**：
  - 过去日结对账（`POST /admin/daily/settle`）仅计算汇总数字并插入 `t_daily_stat`，没有捕获日结时点的静态快照与流水截止水位线，日结后历史订单若发生退款冲正或补单，会导致日结统计和订单流水账实不符、静默漂移；
  - 过去日结关账缺少前置阻断检查，收银员钱箱未交班平账、桌台尚有未结订单或支付挂单时即可执行日结，导致跨营业日悬挂死单与账务混乱；
  - 过去日结没有标准化商业 Z 报表输出，无法提供包含不可变资金流水恒等式、多渠道实收、长短款明细及热敏小票排版的权威关账凭证。
- **日结前置检查阻断器（`GET /admin/daily/pre-check`，POS-SDC-301）**：
  - **机器可读阻断器（Blockers）**：
    - `IN_BUSINESS_HOURS`：当前处于门店营业时段（基于门店配置的营业时间 `open_time` 与打烊时间 `close_time` 判定，支持跨天时段），严格禁止在营业时段进行日结关账，必须打烊后再执行；
    - `OPEN_DRAWER_SESSIONS`：存在未 CLOSED 的终端钱箱会话，必须先交班关箱；
    - `OPEN_ORDERS`：存在未完成结账的桌台挂单，必须先结账或清台；
    - `PENDING_PAYMENTS`：存在处理中的支付中流水，必须先确认或取消；
    - `UNAPPROVED_CASH_VARIANCES`：钱箱交班存在超额长短款但未经店长密码审批授权。
    - 阻断时 `ready = false`，禁止提交日结。
  - **软性警告与预检凭据（Warnings & Token）**：
    - `MINOR_CASH_VARIANCE`：钱箱交班存在小额长短款差异，日结时强制提示并需店长授权；
    - 预检通过后签发 5 分钟有效期的单次 `precheck_token`，并在响应中提供指标预览（`metrics_preview`）。
- **原子日结快照与三水位线（`POST /admin/daily/settle`，POS-SDC-302）**：
  - **营业时段硬阻断防线**：结算请求执行时若当前处于营业时段，强行阻断并抛出 HTTP 400 `DAILY_CLOSE_BLOCKED`（"当前处于门店营业时段（XX ~ XX），禁止进行日结关账，请在打烊后再执行日结"）；
  - **单事务强一致持久化**：验证 `precheck_token`、校验警告/差异授权、拉取三水位线并持久化 `t_daily_close_snapshot`：
    - `cutoff_ledger_id`：截止支付台账最大主键 ID；
    - `cutoff_movement_id`：截止现金流水账本最大主键 ID；
    - `cutoff_order_id`：截止订单最大主键 ID；
  - **SHA-256 数据防篡改哈希**：将营业日、门店 ID、三水位线、销售总额、净销售额计算摘要签名落库 `integrity_hash`；
  - **幂等安全重入**：若指定营业日已日结，直接返回已有快照与 `dailyStat`，置 `idempotent = true`，严禁产生重复快照。
- **日结后差额调整与店长授权重开（POS-SDC-303）**：
  - **日结后调整（`POST /admin/daily/adjustments`、`GET /admin/daily/adjustments`）**：
    - 严禁篡改原 `t_daily_close_snapshot` 快照数据；
    - 事后退款冲正或财务补录以独立调整单写入 `t_daily_adjustment`，记录关联 snapshot_id、金额（分）、调整类型、关联单据、调整原因及授权人；
    - 查询时动态聚合原快照净销售额与累计调整金额，输出调整后有效净额 `adjusted_net_sales_fen`。
  - **店长授权重开日结（`POST /admin/daily/reopen`）**：
    - 当必须推翻日结时，强制校验店长二级密码；
    - 校验成功后将快照状态从 `CLOSED` 标记为 `REOPENED`，解除日结封锁，并在操作审计日志中记录重开流水。
- **商用级 Z 报表与小票排版（`GET /admin/daily/z-report`，POS-SDC-304）**：
  - 全景复算并输出关账数据：
    - **销售与营收摘要（Sales Summary）**：总销售额、折扣折让、退款金额、净销售额、订单总笔数；
    - **多渠道实收明细（Channel Breakdown）**：现金、微信、支付宝、会员余额（本金/赠送）、挂账等各渠道笔数与实收金额；
    - **钱箱现金流水恒等式（Cash Summary）**：开班备用金 + 现金实收 - 现金退款 + 加钞 - 支出 - 投库 = 系统应有现金 vs 实盘现金；
    - **长短款与日结后调整明细（Variances & Adjustments）**；
    - **热敏小票排版文本（print_text）**：格式化 58mm/80mm 字符排版，支持前台收银机一键打印与重打。

## 终端钱箱会话状态机、现金流水账本与盲盘交班契约（v1.2.265 / POS-SDC-201 ~ POS-SDC-204）

- **背景与痛点消除**：
  - 过去钱箱现金仅在班次 `t_shift` 记录 `start_cash` 与 `end_cash`，中间发生的现金收款、现金退款、加钞、支出、投库没有明细流水，无法溯源长短款差异；
  - 过去交班界面直接展示系统金额与差额，违反了商业餐饮防内盗规范的“盲盘（Blind Count）”制度；
  - 过去长短款没有任何审批授权机制，收银员随意填写差额即可完成交班。
- **钱箱会话状态机（`t_drawer_session`）**：
  - 会话状态机流转：`OPEN` -> `CLOSING` -> `CLOSED`（支持异常恢复 `REOPENED`）；
  - 数据库层物理唯一防并发约束：虚拟生成列 `active_slot = (CASE WHEN state IN ('OPEN', 'CLOSING') THEN 1 ELSE NULL END) STORED`，配合唯一索引 `uk_active_drawer (shop_id, terminal_id, drawer_code, active_slot)`，在 DB 层确保同一终端钱箱在同一时刻有且仅有一个活动会话；
  - 乐观锁保护：更新会话时校验 `version`，防止并发覆盖。
- **不可变现金事件流水台账（`t_cash_movement`）**：
  - 每笔现金变动落库不可变明细，类型包括：
    - `OPENING_FLOAT`：开班备用金
    - `CASH_SALE`：现金结算收款（收银结账事务内自动入账，不可篡改）
    - `CASH_REFUND`：现金退款（反结账/退款事务内自动冲减，不可篡改）
    - `CASH_IN`：零钱加钞（人工补充备用金）
    - `CASH_OUT`：现金支出（门店零星采购/杂费，受当前钱箱余额校验保护，防止透支）
    - `CASH_DROP`：大钞投库（将大额现钞转移至保险柜）
    - `COUNT`：交班盲盘实数记录
    - `ADJUSTMENT`：长短款差异调整记录
  - 现金系统应有金额恒等式：
    $$\text{ExpectedCash} = \text{Float} + \text{Sales} - \text{Refunds} + \text{CashIn} - \text{CashOut} - \text{CashDrop} + \text{PriorAdjustments}$$
- **盲盘交班与长短款审批防线（`POST /cashier/shift/handover`）**：
  - **盲盘合规性**：`GET /cashier/shift/current` 严禁向普通收银员暴露 `expected_cash`，收银端界面不得显示系统金额，收银员必须凭实物盘点输入盲盘现金；
  - **50元长短款审批门禁**：
    - 差异绝对值 $\le 50$ 元（$|\text{Variance}| \le 5000\text{分}$）时，允许直接交班平账并记录差异；
    - 差异绝对值 $> 50$ 元时，服务端强制抛错拦截，必须由店长密码二次验证授权，并传入 `approved_by`、`variance_reason_code`（`SHORTAGE`/`OVERAGE`/`SYSTEM_CALC`/`OTHER`）和 `variance_note`；
- **交班综合报表与小票重打（`GET /cashier/shift/report/{sessionId}`）**：
  - 自动从 `t_cash_movement` 与 `t_payment_ledger` 聚合多渠道实收、现金流转全流程公式，并包含操作人与店长审批人信息，支持多次查询、小票重打与财务审计。

## 商业级收银结算台账与防重审计契约（v1.2.264 / POS-SDC-101 ~ POS-SDC-104）

- **背景与痛点消除**：
  - 过去收银结账时仅更新订单表 `t_order` 中的实收列（如 `pay_amount_cash` 等），底层未落库结构化支付台账明细，导致交接班统计（`shiftStats`）与日结对账长期存在数据源缺失或账实不符风险；
  - 过去反结账时仅将订单状态重置并清空实收列，历史支付记录彻底丢失，无法追溯收银员撤回动作与资金冲正明细。
- **不可变支付台账模型（`t_payment_ledger`）**：
  - 每笔结算落库一条或多条不可变台账明细，字段包含：`ledger_no`（业务流水号）、`request_id`（客户端请求幂等防重键）、`shop_id`、`order_id`、`order_no`、`terminal_id`（收银机/手持机终端标识）、`drawer_session_id`（钱箱会话ID）、`employee_shift_id`（员工班次ID）、`operator_id`（操作员/收银员ID）、`entry_type`（`PAYMENT` 支付 / `REFUND` 退款 / `REVERSAL` 冲正）、`channel`（`CASH` / `WECHAT` / `ALIPAY` / `BALANCE_PRINCIPAL` / `GIFT` / `OTHER`）、`amount_fen`（金额分，支付为正，退款与冲正为负）、`status`（`SUCCEEDED` / `FAILED` / `PENDING`）、`provider_transaction_id`（第三方渠道流水号）、`original_ledger_id`（原支付流水ID，冲正/退款时关联）、`occurred_at`（支付发生时间）、`business_day`（营业日 YYYY-MM-DD）。
  - 物理唯一索引保护：`uk_payment_ledger_req (shop_id, request_id, entry_type, channel)`，杜绝网络重发或并发双击产生资金重入账。
  - 对同一门店、同一订单，成功 `PAYMENT` 是权威资金事实；只有完全相同的 `request_id`、渠道分项、金额与第三方交易号才允许幂等重放。另一笔成功资金事实或任一字段不一致均拒绝覆盖。
- **支付回调优先入账（`POST /order/pay/notify`）**：
  - 微信回调先以 `transaction_id` 派生幂等请求号并写入/精确校验权威支付台账，再更新订单支付状态和实收投影；两步处于同一事务，任何失败均回滚并让微信重试。
- **结账原子入账与恒等式强制校验（`POST /cashier/order/checkout`）**：
  - 结账请求支持传入 `request_id`, `terminal_id`, `drawer_session_id`, `employee_shift_id`, `operator_id`, `business_day`；
  - 手工结账先收敛订单上的活动 JSAPI 交易，再落权威支付台账，最后更新订单；已有微信成功或不同成功流水时拒绝手工覆盖；
  - 自动识别多渠道支付分项（现金、微信、支付宝、会员余额本金、赠送金等），校验数学恒等式：
    $$\sum \text{channelAmountsFen} = \text{OrderNetRevenue.netRevenueFen(order)}$$
    若分项合计与订单应付金额不相等，抛出 `IllegalStateException` 触发完整数据库事务回滚，确保财务账账相符。
- **反结账不可变冲正（`POST /cashier/order/unCheckout`）**：
  - 禁止物理删除历史结账台账；
  - 反结账时自动查询该订单原 `PAYMENT` 成功台账，逐笔生成等额相反（负金额）的 `REVERSAL` 冲正台账，关联 `original_ledger_id`，形成完整的借贷冲销资金链，且具备幂等保护（同一支付记录不可重复冲正）。


## 个人收款回调支付方式增加“自动”标识契约（v1.2.263）

- **背景与区分诉求**：
  - 过去个人微信收款回调（以及反向出码补偿结账）在复用 `CashierCheckoutService` 结账时，写入的支付方式固定为 `微信收款码`（支付宝为 `支付宝收款码`）；
  - 这导致在收银订单列表、对账小票、数据统计以及订单明细中，无法直观区分该订单是由收银员手动点击结账，还是由手机监听回调/反向出码匹配自动完成结账。
- **契约行为规范**：
  - **回调支付方式调整**：`PersonalPaymentWebhookService` 在触发自动结账时，写入的支付方式由 `微信收款码` 升级为 `微信收款码自动`（支付宝对应为 `支付宝收款码自动`）；
  - **渠道目录与能力兼容**：
    - `PaymentChannelCatalog` 增加常量 `NAME_WECHAT_QR_AUTO = "微信收款码自动"` 与 `NAME_ALIPAY_QR_AUTO = "支付宝收款码自动"`；
    - `PaymentChannelCatalog.normalizePaymentMethod` 支持对 `微信收款码自动`、`微信收款码(自动)`、`offline_wechat_qr_auto` 等进行标准化规范；
    - `PaymentChannelCatalog.codeFromPaymentMethod` 统一将自动收款码映射到对应底层渠道代码 `offline_wechat_qr` / `offline_alipay_qr`，确保门店支付能力校验与报表渠道类型（`offline`）无缝兼容；
    - `PaymentCapabilityMatcher` 与 `PaymentCapabilityService` 确保自动支付方式在门店开启收银收款码能力时正常放行；
    - `OrderPayChannelAmounts` 自动将包含“微信”/“支付宝”的自动收款码金额精确归集入对应渠道列（`pay_amount_wechat` / `pay_amount_alipay`）；
    - 打印引擎与订单详情直观输出 `微信收款码自动`，完美支撑收银台与管理后台区分手动/自动结账。

## 待结账金额仅统计 merchantId="1" 契约（v1.2.262）

- **背景与口径对齐**：
  - 餐饮点餐系统的财务、报表与已结指标（包括 `countByTimeRange`、`aggregateCurrentBusinessDayPaidOrderMetrics`、日结对账 `businessDayOrderQuery`、数据分析 `AnalyticsMapper`）均已统一过滤 `merchantId = '1'`；
  - 待结账统计查询统一对齐商户口径，排除历史测试数据或非主商户号未结单据的干扰。
- **契约行为规范**：
  - **`GET /admin/order/todayUnsettledAmount`**：查询待结账订单时，强制限定 `merchantId = '1'` 且 `transac_status = 'unsettled'`，与当日订单量和已结营收口径完全一致；
  - **`GET /admin/report/dashboard`（`todayUnpaidAmount` 聚合）**：计算看板当天未支付金额时，同步限定 `merchantId = '1'` 且 `transac_status = 'unsettled'`，消除数据错位。

## 门店新建菜品自动关联总库已有菜品契约（v1.2.260）

- **背景与痛点消除**：
  - 过去门店上下文（`X-Shop-Id` / `X-Shop-Code`）在后台新建菜品时，若输入的菜品在总菜品库（`t_dish`）中已存在，接口过去会直接向 `t_dish` 插入重复记录，不仅污染全局模板库，且若历史存在门店下架或关联异常，还会出现“新建后在门店界面依旧无法显示”的问题；
- **契约行为规范**：
  - **自动关联（防重复插入）**：`POST /admin/dish/save` 在门店上下文下新建菜品（`id` 为空）时，服务端自动按菜品名称 `TRIM(name)` 检索 `t_dish`。若总库已存在同名菜品，直接复用其主键 ID，不再向 `t_dish` 插入重复行；
  - **门店覆盖保留**：复用总部菜品的同时，提取本次请求中的单价、规格、分类、单位、图片、排序、出餐时长等，全部写入当前门店专属的 `t_dish_shop` 覆盖列中；
  - **强制上架自愈**：强制设置 `t_dish_shop.onsale_override = 1`，并将库存与售罄状态重新对齐，确保新建后在门店端、收银台与 C 端小程序即时上架可见；
  - **即时通知**：广播 `dish_catalog_changed`（`action="save_new"`，携带复用后的菜品 ID），通知客户端即刻更新菜单缓存。
  - **门店分类显式绑定与数据库约束**：`type_id_override`（门店分类）为**显式绑定字段**——新建挂载或保存门店菜品时未传 `typeId` 自动回填总部有效分类（`t_dish.typeId` 存在于 `t_category` 时），存量行由迁移回填，之后每行必有分类；同时受数据库外键 **`fk_dish_shop_category`**（→ `t_category.id`，ON DELETE RESTRICT）与 **NOT NULL** 约束，保存的 `typeId` 不存在时数据库拒绝写入；删除被门店菜品引用的类目由逻辑层与数据库外键双重拦截。迁移见 **`docs/db_migration_dish_shop_category_fk.sql`**（脏数据清洗+外键）与 **`docs/db_migration_dish_shop_category_bind.sql`**（存量回填+NOT NULL，均幂等）。

## 桌台管理增删接口防护契约（v1.2.261）

- **新建桌台（`POST /admin/table/add`）**：
  - 校验桌号 `number` 非空，去除两端空格；
  - 支持传入 `area_code`（区域编码，如 hall, box, patio）与 `area_name`（区域名称，如 大厅散座, 特色包厢, 露天外摆）；
  - 校验同门店内桌号防重，重复时返回友好提示；
  - 微信小程序二维码生成失败时容错（如未配置 AppId 或网络离线），不阻断桌台新建成功。
- **修改桌台（`POST /admin/table/update`）**：
  - 入参：`id`（桌台 ID，必填）、`number`（可选新桌号）、`area_code`（可选新区域编码）、`area_name`（可选新区域名称）；
  - 校验桌台 ID 必填且属于当前门店；
  - 若修改桌号，校验在同门店内新桌号不与其他桌台重复；
  - 支持按区域编码自动填充对应的区域名称。
- **删除桌台（`GET /admin/table/delete?id=...`）**：
  - 校验桌台 ID 必填且属于当前门店；
  - 校验桌台使用状态：若处于就餐中或未清台（`status != 0`），禁止删除并返回 500 明确提示，防止破坏未结账订单与就餐数据一致性。
- **获取桌台微信小程序码（`GET /admin/table/qrcode`）**：
  - 入参：`number`（桌号）或 `id`（桌台主键 ID）；
  - 属于当前门店的桌台，优先从本地文件系统读取已持久化的微信小程序码（菊花码，`image/png`）；
  - 若未生成则现场通过微信接口自动申请生成、持久化入库并返回图片二进制流；图片加载及免密场景免 JWT（已纳入 WebAppConfigurer EXCLUDE_PATHS）。


## 收银端数据报表接口与时间窗口算法标准化契约（v1.2.258 / BUG007）

- **标准营业日模型**：
  - 营业日 D 定义为 `[D settle_time, D+1天 settle_time)`；
  - 查询单日报表（`/admin/report/daily` 等）输入日期 D 即代表营业日 D 的全量 24 小时经营周期；
  - 查询多日区间报表（`/admin/report/weekly`, `/monthly`, `/shopProfit` 等）输入 `[startDate, endDate]` 对应窗口 `[startDate settle_time, endDate+1天 settle_time)`，彻底消除 24 小时历史错位；
  - `settle_time` 必须由门店配置；缺失或格式非法时返回 `SETTLE_TIME_NOT_CONFIGURED`，不在报表层静默兜底。
- **财务实收与订单统计口径**：
  - 营业额、实收净额、退款及渠道收入以支付完成时间 `pay_time` 为准；仅兼容历史异常记录，在 `pay_time IS NULL` 时回退 `order_time`；
  - 总部未指定单店上下文时，各门店必须分别按自身 `settle_time` 聚合后求和，禁止套用任意一家门店的窗口；
  - 收银端只提交营业日（日报 `date`、周报 `startDate/endDate`、月报 `year/month`），不得提交或自行推算 `startTime/endTime`。
  - `/cashier/order/search` 强制绑定当前收银员上下文门店 `shop_id` 过滤并支持 `cashierId`；
  - `/cashier/order/today` 自 v1.2.285 起默认收紧为未结账订单及最近 3 小时订单；仅 `admin:super` 可显式查询最多 31 天的自定义时间范围。

## KDS 云端权威、云端直连优先与收银代理容灾 V2 契约（KDS-CA-1.3 / v1.2.259+）

架构边界以 `docs/KDS_ARCHITECTURE.md`（KDS-CA-1.3）为准：云端是唯一业务权威；KDS 正常优先直连云端（Cloud-first），收银端作为可选边缘代理与容灾节点（仅在传输异常并经人工确认后接管）；严格模式下收银代理不可达时返回 503，严禁伪造 STALE 成功响应。所有 HTTP 接口严格要求 Header `X-Kds-Device-Token`，退役 URL query token（`?device_token=` 返回 401）。

### 1. 全量冷启动快照
`GET /kds/v2/bootstrap`
- **鉴权**：请求头 `X-Kds-Device-Token`（强制 Header-only，URL query token 返回 401）
- **纯读化与一致性保障（T03）**：
  - 接口为**纯只读**请求，无写 SQL（无 UPDATE/INSERT）；
  - 自动归档上一营业日遗留未划工单交由后台定时任务（`KdsArchiveJob`）异步沉降；
  - 活动订单缺票自愈补偿交由后台异步有界自愈 worker 批量处理，杜绝客户端请求热路径出现逐订单 N+1 `selectCount` 查询与写入锁竞争；
  - `event_seq`（快照序列游标）在所有读取一致性边界内生成。
- **营业班次窗口隔离与订单生命周期防护（D033）**：
  - 强制绑定门店当前活动营业班次起点 `bizDayStart`（按 `t_shop.settle_time` 默认 05:00 计算完整 24 小时运营窗口），查询在制工单强制追加 `created_at >= bizDayStart`，彻底物理隔离前日及历史老工单，杜绝厨师打烊关机未在屏幕点划菜的遗留工单在次日开机冷启动时跨天流回今日生产在制队列（待配、待制作、待传菜）。
  - 订单生命周期防护：过滤已取消（`transac_status = 'cancelled'`）订单；对已结账清台（`order_receiving = 'off_order'`）但未在 KDS 划菜的工单，强制置入 `doneLines`（`workflow_queue = DONE`，`prep_remaining = 0, cook_remaining = 0, ready_remaining = 0`），绝不进入待配/待烤/待传队列。
- **返回字段**：
  - `protocol_version`: 固定整数 `2`
  - `event_seq`: 当前服务端权威事件序列号（整数 $\ge 0$）
  - `shop_id`: 门店 ID
  - `device`: 设备信息及有效权限集合 `permissions.visible_queues` 与 `allowed_commands`
  - `queues`: 包含 `pending_prep`、`pending_cook`、`ready_serve`、`done` 四个队列，每个明细行包含严苛的 22 个必填规范字段（`detail_id`, `order_id`, `dish_id`, `dish_name`, `order_no`, `line_quantity`, `refunded_quantity`, `prep_remaining`, `cook_remaining`, `ready_remaining`, `local_revision`, `order_revision`, `created_at_ms`, `fulfillment_bucket`, `table_number`, `specification`, `unit`, `remark`, `held`, `rushed`, `lacked`, `removed`），严格遵守 `prep_remaining <= cook_remaining <= ready_remaining <= line_quantity - refunded_quantity`
  - `queue_counts`: 各队列汇总数量字典
  - `fixed_catalog`: 门店菜品固定排序
  - `config`: 包含 `sla_minutes`, `archive_hours` 等
  - `stats`: 当日厨显汇总数据

### 2. 统一命令调度入口
`POST /kds/v2/commands`
- **鉴权**：请求头 `X-Kds-Device-Token`
- **设备权限边界**：命令的 `target.from_queue` 必须属于设备已绑定的 `workflows`（`prep` / `cook` / `serve`），越权返回 HTTP 403、`code=4030`，且不执行业务变更。
- **POS 命令隔离**：设备入口拒绝 `pos_add_dishes` / `addDishes` / `pos_refund_dish` / `refundDish`；加菜、退菜等财务操作必须走管理端/收银端授权入口。
- **请求体**：
  - `command_id`: 客户端生成全局唯一 UUID（幂等键）
  - `command_type`: 支持 `advance_item`, `advance_order`, `rush_item`, `revoke_item`, `lack_item`, `refund_item`, `hold_item`, `release_item` 等；`revoke_item` 支持 `done → ready_serve`，5 秒快捷撤回结束后仍可从已完成看板手动回撤未清理的菜品；成功回撤会同步将该已完成订单恢复为 `order_receiving=rec_order` 并清除 `off_time`，保证重载后仍进入待传菜队列
  - `detail_id`, `order_id`, `quantity` 等操作参数
- **返回**：`KdsV2CommandResponse`（含 `duplicate`, `event_seq`, `patches[]`, `queue_counts`）
- **稳定拒绝**：确定性的参数错误（HTTP 400）和版本冲突（HTTP 409）会在业务事务回滚后，以同一 `(shop_id, command_id)` 和规范请求指纹写入 `REJECTED` 终态。相同请求重放返回原始 `http_status/code/message`；5xx、超时和存储异常不会被误记为业务拒绝。

### 2.1 命令幂等结果查证
`GET /kds/v2/commands/{commandId}`
- **鉴权**：请求头 `X-Kds-Device-Token`
- **路径参数**：`commandId`（客户端指令 UUID）
- **说明**：用于网络超时/状态不明时查询已落盘命令的最终执行结果，不产生二次业务副作用
- **返回**：`status=NOT_FOUND|EXECUTING|APPLIED|REJECTED`；`APPLIED/REJECTED` 的 `result` 是首次落盘的稳定结果，查证不执行第二次业务修改；若命令已分批归档至冷表，同样透明查证并返回 `archived: true`。

### 2.2 双模工作流配置
`POST /kds/v2/config`
- **鉴权**：请求头 `X-Kds-Device-Token`。
- **当前语义**：设备 token 仅代表 KDS 运行身份，不具备门店级配置管理权限；本端点固定返回 HTTP 403、`code=4030`。
- **管理路径**：`enable_prep_workflow` / `prep_enabled` 等门店 KDS 配置必须通过受管理员 JWT 和门店上下文保护的 `POST /admin/kds/config/save` 修改。


### 3. 增量事件追赶（主同步路径）
`GET /kds/v2/changes?after_seq=xxx`
- **鉴权**：请求头 `X-Kds-Device-Token`
- **治理原则（T007）**：作为三端主同步与恢复路径；只要客户端事件游标在热表保留窗口内，断线重连与轮询均通过该端点增量追赶，无需全量重拉。
- **返回**：`protocol_version=2`, `event_seq`, `snapshot_required`（若落后窗口超过保留范围或冷启动则通知重拉快照）, `events[]`

### 4. 营业时段历史与已完成订单（冷启动/缺口恢复）
`GET /kds/v2/business-day/orders?after_id=xxx&limit=200`
- **鉴权**：请求头 `X-Kds-Device-Token`
- **治理原则（T007）**：完整快照仅用于冷启动初始加载、缺口恢复（`snapshot_required=true`）及跨营业日窗口切换，杜绝分钟级定时全量拉取。
- **返回**：当日营业时段内已完成/归档及在制订单列表与明细，支持通过游标稳定分页拉取；在 `idx_order_shop_time` 索引保护下高效执行。

### 4.1 商用度量指标摘要 (T008)
GET /kds/v2/diagnostics/metrics
- **鉴权**：请求头 X-Kds-Device-Token
- **返回**：商用质量指标摘要（命令延迟分布 avg/p95/max、409 冲突率、400 拒绝率、WebSocket 发送/ACK 率、慢消费断链数、快照 vs 增量请求比率）。指标定义与告警阈值见 docs/KDS_OBSERVABILITY_AND_ALERT_THRESHOLDS.md。

### 5. WebSocket 实时广播通道（D034）
`ws://host/ws/kds/v2` / `wss://host/ws/kds/v2`
- **鉴权**：握手 Header `X-Kds-Device-Token` 或 Query `token=<device_token>`
- **广播内容**：标准 `KdsV2EventEnvelope`，包含每次工作流流转或新订单生成的增量 patch、queue_counts 与自增 `event_seq`
- **协议代际严格物理隔离（D034）**：
  - 连接时自动识别协议代际（`/ws/kds/v2` 会话标记为 `kds_protocol_version = 2`，`/ws/kds` 标记为 `1`）；
  - `KdsWebSocketHub` 实施版本过滤广播：`broadcastV2` 仅发送符合 V2 强类型契约的标准 Envelope 报文至 V2 客户端，绝不向 V2 客户端发送 legacy V1 报文，杜绝客户端抛出 `FormatException` 导致红字报错；
  - `broadcastV1` 仅向 V1 老旧客户端投递兼容报文。

### 6. KDS 设备握手与鉴权
- `POST /kds/device/login`：云端权威设备登录，入参支持驼峰与蛇形（`device_code`, `device_name`, `screen_tag`, `screen_tags`, `workflows`, `pairing_code`）。设备必须先由管理端绑定；换发 Token 时必须携带当前有效 `X-Kds-Device-Token`，或提交云端为该设备签发、短时有效且只消费一次的 `pairing_code`。未知、跨店、禁用设备以及只提供 `device_code` 的请求均不得换发凭据。返回同时包含 `data` 与兼容字段 `device`，及 `protocol_version: 2`。
- `GET /kds/device/me`：设备身份核对，请求头 `X-Kds-Device-Token`。返回同时包含 `data` 与兼容字段 `device`，及 `protocol_version: 2`。
- `POST /kds/device/heartbeat`：设备心跳保活，请求头 `X-Kds-Device-Token`。返回包含 `data`（`shop_id`, `server_time_ms`, `protocol_version`）及 `protocol_version: 2`。

### 7. 云端订单生命周期 V2 广播与增量追赶（D034）
- **新订单接单与加菜（`order_accepted` / `order_updated`）**：
  - 顾客小程序下单支付或商户后台接单后，若门店启用 KDS，云端在生成工单的同时，向直连 V2 KDS 广播标准 `KdsV2Envelope`；
  - 包含 22 个必填规范字段的明细行补丁 `patches`、整单全量明细 `order_details`、各队列角标统计 `queue_counts`；
  - 触发 KDS 客户端标准新单提示音（`order_accepted`）；加菜事件类型标记为 `order_updated`；
  - 同步写入门店内存增量事件环形日志（`eventLogByShop`），确保断网重连或每 15 秒轮询 `GET /kds/v2/changes?after_seq=xxx` 能精准追赶该事件。
- **订单取消（`order_cancelled`）**：
  - 订单取消后，全单明细作为 `removed: true` 的 patches 广播并写入增量日志，KDS 屏幕即刻从活动队列清除该订单卡片。
- **菜品退菜（`item_refunded`）**：
  - 顾客或收银退菜后，对应明细作为 `removed: true` 的 patches 广播并写入增量日志，KDS 屏幕即刻扣减或清除对应菜品行。

---

## KDS 营业时段历史回填（收银端专用）

`GET /cashier/kds/delivery/business-day/orders/detail?limit=200&cursor=...`

采用全量补充接口方案：bootstrap 保持在制订单投递语义。收银端启动后调用本接口，将 `data.orders` 按 `orderId/detailId` 幂等写入历史数据，循环传 `data.nextCursor` 至 `data.complete=true`。历史回填不触发新来单提示、打印或制作；之后继续 bootstrap 的事件/ACK 流程，回填接口不改变投递游标。并行写入时不要用历史页覆盖较新的实时进度。

请求使用 Authorization 及 `X-Shop-Id`、`X-Cashier-Device-Code`、`X-Cashier-Authority-Epoch`、`X-Cashier-Lease-Token` 请求头，沿用原租约，不将凭证放在 URL。也支持 `/admin/cashier/kds`、`/api/admin/cashier/kds` 路径前缀，权限为 `cashier:operate`。

响应保留 `businessDayStart/businessDayEnd`（前含后不含）、`orders`、`nextCursor`、`complete`。窗口内全部订单均返回，包含完成、未接单及取消订单。完成依据为厨房状态 40 或接单状态 off_order，结账并不等于完成。订单含 `completed`、`completedAtMs`（没有真实完成时间时为 null）、`archived=false`（历史可见）、`orderStatus=active/completed/cancelled`，原交易状态在 `transactionStatus`。

`details`（兼容别名 `lines`）含 `detailId/dishName/quantity/lineQuantity/workflowQueue/doneLine/readyRemaining/prepRemaining/cookRemaining`。完成单返回 done/1/0；未完成明细使用已同步厨房进度，缺失进度返回 null，不推断为待制作。取消单不可进入生产队列。

原 `/business-day/orders` 已返回 `data.orders/details`，不是仅返回时间窗口；新端点增加用于本地回填的厨房进度字段。营业快照按 `order_time ASC, id ASC` 稳定分页，cursor 为 `order_time:id`（兼容旧版纯 ID），闭店后至次日开店前保留最近一次营业窗口。

Last Updated: 2026-09-30
API Version: v1.2.250
Base Path: /
OpenAPI Specification: `docs/openapi.yaml` (权威契约定义)

## 数据接口统一时间窗口标准（v1.2.245）

1. **严格校验（无兜底）**：
   - 门店必须在 `t_shop.settle_time` 配置结算时间（HH:mm 格式，如 `05:00`）。
   - 若门店未配置或格式非法，所有基于营业窗口的数据接口直接返回 400 错误（`SETTLE_TIME_NOT_CONFIGURED` / `SETTLE_TIME_INVALID`），不再回退到 `close_time` 或默认值 `04:00`。

2. **实时数据接口（当天营业额、今日订单数、实时未结金额、当前日结预览、收银端今日订单等）**：
   - 窗口为当前活动营业班次的完整 24 小时周期：`[班次起始日 settle_time, 班次起始日+1天 settle_time)`。
   - 示例（`settle_time = 05:00`）：
     - 9.11 16:00 查询 → `[9.11 05:00, 9.12 05:00)`
     - 9.12 03:00 查询 → `[9.11 05:00, 9.12 05:00)`
     - 9.12 06:00 查询 → `[9.12 05:00, 9.13 05:00)`
   - 显式传入 `date`（yyyy-MM-dd）时，取指定班次起始日 24 小时：`[date settle_time, date+1天 settle_time)`。
   - `GET /admin/order/salesvolume?period=day` 未传 `date` 时属于实时数据接口：当前班次内每笔成功支付会立即累计到营业额；显式传 `date` 时保留历史结算日语义 `[date-1天 settle_time, date settle_time)`。

3. **已结算数据接口（日报、周报、月报、历史营业额、菜品排行、收银绩效、Analytics 默认报表等）**：
   - 未传 `date` 时，取最近已完成的完整 24 小时结算周期：`[最近结算日-1天 settle_time, 最近结算日 settle_time)`。
   - 示例（`settle_time = 05:00`）：
     - 9.11 16:00 查询 → `[9.10 05:00, 9.11 05:00)`
     - 9.12 03:00 查询 → `[9.10 05:00, 9.11 05:00)`
     - 9.12 06:00 查询 → `[9.11 05:00, 9.12 05:00)`
   - 显式传入指定结算日 `date`（yyyy-MM-dd）时，取 `[date-1天 settle_time, date settle_time)`；指定区间 `[startDate, endDate]` 时，取 `[startDate-1天 settle_time, endDate settle_time)`。

4. **自然日次要规则**：
   - 系统保留自然日 `[00:00:00, 23:59:59]` 维度作为次要规则，适用于明确按自然日历统计的周/月维度及自然日查询模式。

---

# 1. API Principles

- Stable contracts with zero silent breaking changes.
- Multi-store isolation via `X-Shop-Id` header and store scope verification.
- Optimistic locking for concurrent settings updates via `version` field.
- Unified response envelope: `{ "code": 0, "msg": "...", "data": { ... } }` and double-wrapped `{ "device": {...}, "data": {...} }` where required for legacy client compatibility.
- Comprehensive security audit logging for all privileged mutating operations.

---

# 2. Authentication & Authorization

- **Authentication Method**: JWT Bearer Token in `Authorization` header (`Bearer <token>`).
- **Store Scope Context**: Header `X-Shop-Id: <shopId>` passed on all admin requests.
- **Permission Matrix**:
  - `printing:view` — 查看打印设备、出票规则及打印任务流水。
  - `printing:manage` — 新增/编辑/删除打印设备、保存出票规则、触发测试打印、补打任务。
  - `cashier:operate` — 收银端开台、点餐、结账、后厨出票、交接班。

---

# 2.1 菜品出餐时长与 KDS 超时

- `Dish` 新增 `serving_duration_minutes`（正整数分钟）。`POST /admin/dish/save` 新增菜品未传时默认 10，编辑传值时保存，编辑省略时保留原值；传 0 或负数返回 `code != 0`。
- `GET /dish/listAll`、`POST /admin/dish/list`、`POST /admin/dish/hqTemplateList` 的菜品对象均返回该字段。
- KDS 待做明细以 `wait_seconds > serving_duration_minutes * 60` 判定超时；历史订单明细没有 `dish_id` 或菜品无法读取时，回退门店 `t_kds_shop_config.sla_minutes`。
- `GET /kds/order/list`、KDS 总览/工作流看板、烤制看板的明细行返回实际采用的 `serving_duration_minutes`。
- 存量数据库先执行 `docs/db_migration_dish_serving_duration_minutes.sql`。

---

# 2.2 KDS 门店极简登录 (PIN 码与设备自动绑定)

- **接口**：`POST /kds/device/login`（免 JWT 认证或携带已有 `X-Kds-Device-Token` 续登）
- **请求体支持参数**：
  - `shop_id` / `shopId`：门店编号（正整数）。
  - `kds_pin` / `kdsPin`：门店 6 位数字登录 PIN 码（默认 `123456`，可通过 `POST /admin/kds/config/save` 的 `kds_pin` 字段自定义维护）。
  - `device_code`：KDS 硬件设备唯一编码。
  - `device_name`：（可选）档口/设备名称（如：后厨烤制屏）。
  - `screen_tag`：工作看板模式（默认 `workflow_board`）。
  - `workflows`：负责流程数组（`["prep", "cook", "serve"]`）。
- **业务行为**：
  - 服务端校验 PIN 码正确后，若该硬件首次接入，自动为其建立绑定并启用，签发正式长效 `device_token`。
  - 彻底免去在收银后台手动复制输入复杂设备码及生成 5 分钟一次性配对码的痛点流程。
  - 数据库迁移脚本：`docs/db_migration_kds_pin.sql`（`t_kds_shop_config.kds_pin`）。

---

# 3. Unified Printing API Endpoints (统一打印系统接口)

> v1.2.274：标准打印场景新增 `PACKING`（打包单）。打包/自提订单仅在门店配置并启用 `packing` 规则时独立出票，可单独选择设备、模板、份数；未配置时保持现有厨房单/前台单行为。

| 接口方法 | 路径 | 权限 | 说明 |
| :--- | :--- | :--- | :--- |
| **GET** | `/admin/printing/devices` | `printing:view` | 获取打印设备列表（支持 `transport`/`status` 筛选与分页，连接凭据脱敏） |
| **POST** | `/admin/printing/devices` | `printing:manage` | 创建打印设备（支持 CLOUD/LAN/USB/BLUETOOTH，连接配置参数化） |
| **GET** | `/admin/printing/devices/{id}` | `printing:view` | 获取指定设备详情（凭据脱敏保护） |
| **PUT** | `/admin/printing/devices/{id}` | `printing:manage` | 更新打印设备（`version` 乐观锁，冲突返回 409 `PRINTING_VERSION_CONFLICT`） |
| **DELETE** | `/admin/printing/devices/{id}` | `printing:manage` | 删除打印设备（被出票规则引用时返回 400 `PRINT_DEVICE_IN_USE_BY_RULE` 阻断，自动从云平台解绑） |
| **GET** | `/admin/printing/devices/{id}/status` | `printing:view` | 打印设备实时在线状态探活（支持飞鹅云原生状态码 0/1/2 映射与缺纸/开盖识别，结果自动同步入库） |
| **POST** | `/admin/printing/devices/{id}/clear-queue` | `printing:manage` | 清空云打印机待打印队列（调用飞鹅云 `Open_delPrinterSqs`） |
| **POST** | `/admin/printing/preview` | `printing:view` | 打印小票实时预览（按场景、订单、设备规格组装小票数据并返回结构化节点树） |
| **POST** | `/admin/printing/preview/exact` | `printing:view` | 精确预览：强制真实订单（交接班为真实班次），返回与原生打印内容同源的 AST；不发送打印任务 |
| **GET** | `/admin/printing/preview` | `printing:view` | 打印小票实时预览（支持 Query 参数快速预览） |
| **GET** | `/admin/printing/rules` | `printing:view` | 获取当前门店全部场景出票规则 |
| **PUT** | `/admin/printing/rules` | `printing:manage` | 批量保存出票规则（`version` 乐观锁；模板必须属于当前门店或系统模板，规则场景与模板版式可独立组合） |
| **POST** | `/admin/printing/devices/{id}/test` | `printing:manage` | 发送打印自检测试单（支持 order/kitchen/refund/shift/cutter_test） |
| **GET** | `/admin/printing/jobs` | `printing:view` | 查询打印任务流水记录（支持时间、设备、状态筛选与分页；`jobType` 统一为十一类标准小写场景码或合法自定义码，新增 `packing`，历史别名通过 `legacyJobType` 回显） |
| **POST** | `/admin/printing/jobs/{id}/reprint` | `printing:manage` | 打印任务重新派发与补打 |
| **GET** | `/admin/printing/templates/meta` | `printing:view` | 获取小票设计器元数据与参数绑定字典（11大场景，新增打包单 `PACKING`；含区块类型、动态变量定义与示例） |
| **GET** | `/admin/printing/templates` | `printing:view` | 获取当前门店可用小票模板列表（支持 `scenario`/`paperSize` 筛选） |
| **GET** | `/admin/printing/templates/{id}` | `printing:view` | 获取指定模板详情（包含完整排版 JSON DSL 配置） |
| **POST** | `/admin/printing/templates` | `printing:manage` | 新建自定义打印模板（前端可视化设计器保存） |
| **PUT** | `/admin/printing/templates/{id}` | `printing:manage` | 更新自定义打印模板（可同时更新 `scenario`；`version` 乐观锁，冲突返回 409 `PRINTING_VERSION_CONFLICT`） |
| **DELETE** | `/admin/printing/templates/{id}` | `printing:manage` | 删除自定义模板（系统模板/被出票规则引用的模板拦截删除） |
| **POST** | `/admin/printing/templates/{id}/set-default` | `printing:manage` | 设为场景默认出票模板 |

### 3.1 打印设备实时状态探活响应示例 (GET `/admin/printing/devices/{id}/status`)

```json
{
  "code": 0,
  "deviceId": 1,
  "online": true,
  "status": "ONLINE",
  "paperStatus": "NORMAL",
  "coverStatus": "CLOSED",
  "lastPingTime": "2026-08-31T01:10:00+08:00"
}
```

- **飞鹅云状态码映射规则**：
  - `0` / 包含 `"离线"`: `online: false, status: "OFFLINE", paperStatus: "UNKNOWN", coverStatus: "UNKNOWN"`
  - `1` / 包含 `"工作状态正常"` / `"正常"`: `online: true, status: "ONLINE", paperStatus: "NORMAL", coverStatus: "CLOSED"`
  - `2` / 包含 `"工作状态不正常"` / `"异常"`: `online: true, status: "ERROR"`, 并识别 `"缺纸"` 为 `OUT_OF_PAPER`，`"开盖"` 为 `OPEN`。

### 3.2 打印小票实时预览响应示例 (POST `/admin/printing/preview`)

`/admin/printing/preview` 保留设计器样例预览兼容行为；配置验收应调用 `POST /admin/printing/preview/exact`，传入 `scenario`、真实 `orderId`（交接班传 `shiftId`），以及后厨/传菜单需要的 `cidFilter`、`detailId`、`serveQty`。exact 按全部生效规则及设备只读渲染，不发送也不记录打印任务，且不接受模板、统计或退款的人工覆盖。`rawCombinedContent` 是事实源；每张 `tickets` 可追溯到 `ruleId/deviceId/deviceName/templateId/templateCode`。

```json
{
  "code": 0,
  "msg": "预览生成成功",
  "data": {
    "scenario": "ORDER",
    "scenarioName": "前台结账单",
    "paperSize": "58mm",
    "paperWidthMm": 58,
    "paperWidthChars": 32,
    "shopName": "老肥油边王(松源海鲜街)",
    "totalTickets": 1,
    "tickets": [
      {
        "ticketIndex": 0,
        "title": "前台结账单",
        "rawContent": "<CB>老肥油边王(松源海鲜街)<CB><BR><CB>结账单</CB><BR>名称　　　　　 单价  数量  金额<BR>--------------------------------<BR>炭烤羊肉串(10串)   30     2  60.00<BR>...",
        "plainText": "老肥油边王(松源海鲜街)\n结账单\n名称　　　　　 单价  数量  金额\n--------------------------------\n炭烤羊肉串(10串)   30     2  60.00\n...",
        "elements": [
          { "type": "HEADER", "text": "老肥油边王(松源海鲜街)", "align": "CENTER", "bold": true, "size": "DOUBLE" },
          { "type": "HEADER", "text": "结账单", "align": "CENTER", "bold": true, "size": "DOUBLE" },
          { "type": "TABLE_HEADER", "columns": ["名称", "单价", "数量", "金额"] },
          { "type": "DIVIDER", "text": "--------------------------------" },
          { "type": "KEY_VALUE", "key": "原价合计", "value": "128.00元" },
          { "type": "KEY_VALUE", "key": "实付合计", "value": "128.00元", "bold": true },
          { "type": "CUT" }
        ]
      }
    ],
    "rawCombinedContent": "...",
    "renderedAt": "2026-08-31T11:30:00+08:00"
  }
}
```

---

# 4. Cashier & Operational Print Endpoints (业务与收银打印接口)

| 接口方法 | 路径 | 权限 | 说明 |
| :--- | :--- | :--- | :--- |
| **GET** | `/cashier/order/printContent` | `cashier:operate` | 获取收银小票/预结单格式化内容并触发打印 |

| **POST** | `/cashier/order/refund` | 入口 `cashier:operate`；执行 `order:operate:refund` | 已支付订单人工退款；无 execute 权限时支持严格 token、现场密码/PIN 或扫码审批 |
| **POST** | `/cashier/order/refundDish` | 入口 `cashier:operate`；执行 `order:operate:refund` | 退菜；审批与订单、门店、终端严格绑定 |
| **POST** | `/cashier/order/discount` | 入口 `cashier:operate`；执行 `order:operate:discount` | 优惠；审批金额绑定服务端计算后的实际优惠额 |
| **POST** | `/cashier/order/updatePrice` | 入口 `cashier:operate`；执行 `order:operate:changePrice` | 改价或赠送；审批金额绑定新明细总价 |
| **POST** | `/cashier/order/unCheckout` | 入口 `cashier:operate`；执行 `order:operate:reopen` | 反结账；保留日结封账与外部资金阻断 |
| **POST** | `/cashier/print/kitchen` | `cashier:operate` | 收银端触发后厨分单出票（按 `cid_list` 分组） |
| **POST** | `/admin/order/reprint-kitchen` | `order:operate` | 运营后台订单明细手动补打后厨小票 |

高风险订单动作优先使用 `approvalToken`；兼容嵌套字段 `authorization: { account, password }`，服务端会将其转换为严格绑定、120 秒有效且单次核销的 v2 令牌。授权员工可与当前登录收银员不同，且必须具备精确 `<execute>:approve` 权限。订单删除仍沿用独立超管双重校验，不属于本次四类动作迁移。

上述退菜、优惠、改价接口以及收银加菜接口支持可选 `expectedVersion`；成功响应返回新 `revision`，HTTP 409 时应刷新订单，不得继续使用已经取得的旧订单快照。

---

# 5. Backward Compatibility & Deprecated Endpoints (废弃与向下兼容接口)

| 废弃接口 | 废弃版本 | 替代接口 | 兼容策略 |
| :--- | :--- | :--- | :--- |
| `GET/PUT /admin/config/feieyun` | v1.2.132 | `GET/POST/PUT /admin/printing/devices` | 已下线（v1.2.223 移除控制器与全局配置存储），请求返回 404 |
| `GET/PUT /admin/config/feieyun/shop` | v1.2.132 | `GET/POST/PUT /admin/printing/devices` | 已下线（v1.2.223 移除 `t_shop_printer_config` 存储），请求返回 404 |
| `POST /api/feieyun/print` | v1.2.146 | `POST /admin/printing/devices/{id}/test` 或统一调度引擎 | 保持可用；入参改为 `deviceId`，凭据从 `t_printing_device.connection_json` 解析（缺失返回 400） |
| `GET /order/printContent` | v1.2.166 | `GET /cashier/order/printContent` | 返回 410 Gone，引导迁移至收银路由 |

---

# 6. Error Codes Reference (错误码参考)

| 错误码 Code | 业务含义 | HTTP 状态码 |
| :--- | :--- | :--- |
| `PRINTING_VERSION_CONFLICT` | 设备或规则已被他人修改（乐观锁版本冲突） | 409 Conflict |
| `ORDER_VERSION_CONFLICT` | 订单已被其他终端修改；响应 data 含最新订单摘要 | 409 Conflict |
| `ORDER_VERSION_INVALID` | expectedVersion 不是非负整数或两个别名值不一致 | 400 Bad Request |
| `PRINT_DEVICE_NOT_FOUND` | 打印设备不存在或不属于当前门店 | 404 Not Found |
| `PRINT_DEVICE_IN_USE_BY_RULE` | 打印设备被出票规则绑定中，禁止直接删除 | 400 Bad Request |
| `PRINT_DEVICE_CONNECTION_INVALID`| 设备连接参数 JSON 校验失败或缺少必填字段 | 400 Bad Request |
| `PRINT_RULE_INVALID` | 出票规则配置非法（场景不存在或份数不在 1-9 范围） | 400 Bad Request |
| `PRINTING_RULE_TEMPLATE_NOT_FOUND` | 出票规则引用的模板不存在或不属于当前门店 | 400 Bad Request |
| `PRINTING_TEMPLATE_NOT_FOUND` | 未在数据库中配置该场景的小票打印模板（已移除硬编码兜底） | 404 Not Found |
| `PRINTING_CLEAR_QUEUE_UNSUPPORTED`| 仅云打印机支持远程清空排队队列 | 400 Bad Request |
| `PRINTING_CLEAR_QUEUE_FAILED` | 飞鹅云平台清空队列接口调用失败 | 500 Internal Server Error |
| `SHOP_CONTEXT_MISSING` | 请求未携带有效的 `X-Shop-Id` 门店上下文 | 400 Bad Request |

# 7. Operation Audit (全局操作审计日志)

高价值写操作通过 `@AuditLog` 注解 + `AuditLogAspect`（AOP 环绕切面）统一写入 `t_operation_log`，运营端经 `GET /admin/logs` 查询（在线 30 天 / 归档 365 天 / 导出）。

- 记录字段：`module`、`action`、`target_id`（SpEL 从请求参数提取，如订单号）、`admin_id`、`shop_id`、`ip`、`request_snapshot`（参数 JSON，脱敏 + 2000 字符截断）、`before_state`/`after_state`（DiffProvider 捕获）、`result_status`（SUCCESS/FAILED）、`result_code`、`reason`、`trace_id`。
- 埋点范围（两批）：收银下单/加菜/退菜/现金退款/改价/折扣/结账/反结账（`cashier_*`）、运营退菜 `admin_refund_dish`、退款发起 `refund_apply`（微信 + 余额）、退款入账 `refund_settle`（微信回调与补偿查询）。
- 失败语义：审计日志写入失败仅记录 error，不影响业务结果；业务异常时记录 FAILED + 原因后原样抛出。
- 扩展：新增审计点在目标方法加 `@AuditLog(module, action, target, diff)` 注解即可；前后状态实现 `DiffProvider` 并注册为 Bean。

## C007: 配置账号代理停用与请求限额

`/api/zsq/auth/login/config` 及三个 `/auto` 入口返回 HTTP 410，不再使用服务器账号。管理端配送入口和内部服务仍有效。JSON 默认上限 1 MiB（`app.http.max-json-bytes`），超限 HTTP 413；流式请求同样限制。S01/S04/S10 按用户要求保留。

### 收款事件匹配（S05）

自动匹配要求正整数 shop_id 和唯一的同门店/渠道/金额有效意向，按到账时间判断有效期（15 秒容差）。多候选、无门店或无匹配仅入流水，不按订单金额兜底结账。反向出码补偿仅使用相同门店事件，未知门店事件需人工核对。回调签名协议按 S04 排除项保留。

### 错误响应及凭据部署

全局数据库/未分类异常响应仅返回稳定提示和 traceId，不返回底层异常。配送集成错误同样隐藏第三方详情。收款 raw_text 不再记录或保存（历史数据按保留策略清理）。详见 C007-OPERATIONS.md。

### 图片限制

头像只接受有效 JPEG/PNG，最多 5 MiB、800 万像素，重新编码为 PNG；扩展名不作为类型依据。图片原文件最多 10 MiB，缩放前最多 1600 万像素；缩略图缓存 32 MiB、10 分钟，单实例最多并行解码 2 张。HTTP 通用客户端连接/读取超时默认 3/15 秒。

### KDS 流程持久化

设备登录的 workflows 保存至数据库，重启后保留；解绑清除覆盖项。收银 WebSocket 每 5 秒补发持久化游标提示，客户端应容忍重复并按游标补拉。上线前运行 V007 迁移。

### C007 控制器与金额边界
用户资料三接口路径及字段不变，HTTP 与 AI 调用共用 CustomerProfileService；AI 响应解析由 AiToolResponseParser 负责。支付结算在运算前转为十进制，按 HALF_UP 保留两位；转整数分时检查溢出，禁止静默截断。实体与 API 的既有数值字段保持兼容。

### C007 契约核对
S01 保留旧版白名单 openid 兼容（含余额支付），受兼容开关和截止时间控制；有 Token 时仍校验一致性。Cloud KDS heartbeat 必须传设备令牌，body 的 device_code 不用于选择设备，失败为当前业务 code=401。S04 回调签名与 S10 HTTP 打印未修改。日志移除微信 Token 响应、AI 对话正文和用户标识载荷，保留事件与长度等诊断信息。

## C009/T01b 厨房投影任务（2026-09-08）
加菜、接单、退菜、取消、移桌及整单完成的既有投影入口改为持久化任务。加菜在源事务记录，接单门禁不变；自动接单的订单头更新与任务记录共用数据库事务。任务记录失败时相关事务回滚，调用方按现有错误及幂等机制处理。成功响应不保证即时推送，继续按游标补拉；外部打印成功与数据库事务仍不构成分布式原子操作，不自动重打历史票据。接口字段不变。部署先应用docs/db_migration_kds_projection_intent.sql，缺表/索引/非InnoDB启动失败。

## C009/T03 报表与归档受理预算
POST /admin/reports/exports 与 POST /admin/logs/archive-search 的成功响应仍为PENDING。两者共用全局128、每门店4个未完成任务预算；超额返回HTTP429/error=REPORT_JOB_QUOTA_EXCEEDED，不插入新任务。停止后新请求返回HTTP503/error=REPORT_WORKER_CLOSED。已受理任务在本地队列满时仍保留，由5秒恢复扫描补投。执行租约30分钟，进程重启后可接管过期RUNNING；旧执行者不能覆盖新结果。同步日志导出不适用该异步配额。上线先执行docs/db_migration_report_job_recovery.sql，并停止所有旧版后台工作线程。

- C009/T04（经 C012 营业日报统一覆盖）：POST /admin/reports/exports 的 daily/weekly/monthly 均在创建任务前校验日期（yyyy-MM-dd，1000–9998年）、起止顺序、含首尾最多92天；缺少参数为400 REPORT_RANGE_REQUIRED，非法/倒置/超限为400 REPORT_RANGE_INVALID，不落库。daily.date优先于startDate，endDate可省略。仅接受csv；仅统计成功且已接单（rec_order/off_order）订单。CSV 与同步 `/admin/report/daily|weekly|monthly` 均按门店 `settle_time` 的左闭右开营业窗口聚合，以 `pay_time` 归属，只有 `pay_time IS NULL` 时回退 `order_time`；金额保持 Decimal。CSV 尾部追加新增挂账、应收回款、坏账核销与挂账撤销四列，使销售与真实收款可解释；文件以 `.part` 写入、完成后原子发布，默认24小时清理。

- C009/T05：GET /cashier/kds/delivery/bootstrap 不再同步逐单补投影。缺口返回HTTP503/code5030 BOOTSTRAP_PROJECTION_PENDING，后台1线程/16排队门店/每批32单。客户端按租约响应持续RENEW，1–5秒抖动重试首屏；503/部分页面均不可提交最终快照或ACK放行。页面读取无租约行锁，读取后短事务重验epoch/token/有效期。页token仍10分钟有效，过期重新首屏。
- C009/T23：`GET /cashier/order/today` 默认仅返回当前门店全部未结账订单，以及 `order_time` 位于最近 3 小时内的其他订单。可选 `startTime/endTime` 自定义闭区间（支持 `yyyy/MM/dd`、`yyyy-MM-dd` 纯日期或含时分秒，必须成对、不可与 `date` 混用、最大 31 天），但调用者必须具备精确权限码 `admin:super`；旧 `date` 营业班次查询保留为兼容入口，同样仅限 `admin:super`。无权限返回 403，非法范围返回 4002；响应仍为 `list`。`GET /cashier/order/search` 亦同步支持 `yyyy/MM/dd` / `yyyy-MM-dd` 纯日期及时间区间解析。
- D025（2026-09-09，历史兼容链）：云端 → 收银端明细状态事件 `ORDER_LINE_STATUS_CHANGED` 经 `GET /cashier/kds/delivery/events` 下发。该链只用于迁移期兼容；新架构见 `docs/KDS_ARCHITECTURE.md`，字段契约见 `openapi.yaml`。

## D031 数据接口时间窗口统一（2026-09-11）

- **严格校验**：`t_shop.settle_time` 必须配置，未配置直接抛出 400（`SETTLE_TIME_NOT_CONFIGURED`），取消向 `close_time` 和 `04:00` 的默认兜底。
- **实时数据接口**（当天营业额、今日订单数、实时未结金额、当前日结预览等）：使用当前活动营业班次 24 小时窗口 `[班次起始日 settle_time, 班次起始日+1天 settle_time)`；`/cashier/order/today` 自 v1.2.285 起不再属于此默认口径。
- **营业日报接口（C012 当前规则）**：`/admin/report/daily|weekly|monthly` 的日期表示营业日起始标签；单日为 `[D settle_time, D+1 settle_time)`，闭区间日期范围 `[startDate,endDate]` 为 `[startDate settle_time, endDate+1 settle_time)`。其他历史报表接口仍按各自契约解释日期，不得将旧结算日规则套用到这三个接口。
- **自然日保留**：保留自然日 `[00:00:00, 23:59:59]` 维度作为次要规则。
- KDS 实时配送继续按当前活动班次读取运行中订单，不参与已结算报表窗口。

## D032 KDS 双模态设备信息同步（2026-09-13，2026-09-23 安全修订）

- **接口**：`POST /admin/kds/device/bind`
- **扩展入参**：支持 `workflows` / `workflows_json`（List&lt;String&gt;）；任何 `deviceToken` / `device_token` / `token` 字段均被忽略。
- **契约行为**：
  - 该接口只同步设备元数据，不能签发、指定、回传或轮换 KDS Token；
  - 同时将 `workflows` 落库至 `t_kds_device.workflows_json` 并更新内存与多端缓存；
  - KDS Token 只能由云端登录接口签发；云端仅持久化 SHA-256 hash、到期时间和撤销时间，原始 Token 只出现在登录响应中。

## D033 KDS 设备握手协议版本对齐（2026-09-13）

- **接口**：`POST /kds/device/login`、`GET /kds/device/me`、`POST /kds/device/heartbeat`
- **契约调整**：响应对象顶层新增 `protocol_version: 2`（整数），与收银端局域网握手规范同构。
- **背景**：解决 KDS App 客户端使用 `_requireV2()` 强校验导致云端直连/备用通道握手因缺失 `protocol_version` 失败（抛出 `ApiException: /kds/device/login 未返回 protocol_version=2`）的阻断性缺陷。

## D034 KDS 直连订单接单与状态流转 V2 实时广播与增量追赶（2026-09-14）

- **接口**：WebSocket `/ws/kds/v2`、`GET /kds/v2/changes`
- **契约规范**：
  - WebSocket 物理隔离：根据连接 URI 与 `protocol_version` 会话属性严格区分 V1 与 V2 客户端，绝不向 V2 客户端广播 legacy V1 报文，彻底杜绝客户端 `FormatException` 异常。
  - 订单生命周期 V2 广播：新单入厨触发 `order_accepted`，加菜触发 `order_updated`（全单明细视图），退菜触发 `item_refunded`（`removed: true`），整单取消触发 `order_cancelled`（`removed: true`），配置变更触发 `config_changed`。
  - 事务后增量日志：所有 V2 广播在数据库事务提交后原子写入 `eventLogByShop` 环形日志，支持断网重连与轮询增量追赶。

## D035 修复营业时段订单快照错误判定已完成及档口缺失自愈（2026-09-14）

- **接口**：`GET /kds/v2/business-day/orders` 与 `GET /kds/v2/bootstrap`
- **契约调整与修复**：
  1. `GET /kds/v2/business-day/orders`：
     - 修复 `loadBusinessDayDetails` 中对所有订单明细无条件硬编码 `workflow_queue = "done"` 的致命缺陷；
     - 严格联动订单主状态（`off_time`、`order_receiving`、`transac_status`）与底层 `t_kds_ticket` 真实制作状态；
     - 补齐 API 契约 §9.1.1 规范字段：`doneLine` / `done_line`（0 或 1）、`workflowQueue` / `workflow_queue`（未完成为当前制作队列如 `pending_cook`，已完成为 `done`）、`readyRemaining`、`cookRemaining`、`prepRemaining`；
     - 彻底避免未结账新单被误识别为已完成出餐。
  2. `t_kds_station` 档口空表自愈：
     - `KdsStationService.findByScreenTag` 在查无记录且门店档口数为 0 时，自动触发 `initFiveScreens(shopId)` 初始化标准五屏档口，杜绝新单接单因缺失档口导致工单被静默丢弃。
  3. `GET /kds/v2/bootstrap` 工单缺失自愈补偿：
     - 冷启动拉取看板时，自动扫描当前活动营业班次内已接单但工单数为 0 的在制订单，调用 `kdsOrderHook.ensureTicketsForAcceptedOrder` 自动补全缺失工单，使漏建单据恢复至活动在制队列。



### GET /api/v1/kds/orders/canonical
获取规范化 KDS 订单快照 (Canonical Projection)。


### POST /admin/kds/device/proxy-command
已永久停用，返回 `code=410`。收银端不得使用管理员会话与 `actor_device_code` 合成 KDS 身份或重放命令；所有写请求必须携带原始云端 KDS Token，原样转发至 `POST /kds/v2/commands`。云端不可达时由 KDS 本地 outbox 保留原 `command_id`，收银端不接管授权或命令所有权。

## D036 KDS 收银端代理登录与云端权威统一 Token（2026-09-16）

> 2026-09-30 起，实时 LAN 登录已切换为透明转发同一 `POST /kds/device/login`。`/admin/kds/device/proxy-login` 已永久停用并返回 `code=410`。

- **现行 LAN 登录契约**：收银端把 KDS 登录 body（含可选一次性 `pairing_code`）、`X-Kds-Device-Token` 和 request id 完整转发至 `POST /kds/device/login`；收银端不校验设备码、Token、配对码或工作流权限，也不改写云端 401/403 响应。
- **后续请求契约**：LAN 只做受限路径转发；云端校验 KDS Token。代理携带 `X-Shop-Id` 时，云端还必须确认它与 Token 绑定门店一致。

- **接口**：`POST /admin/kds/device/proxy-login`
- **契约行为**：
  - 收银端局域网收到 KDS 登录请求后转发至云端该接口；
  - Bearer、`X-Shop-Id` 与 `cashier:operate|kds:config` 权限验证收银调用方；`X-Cashier-Device-Code` 必须携带但只用于审计和链路定位，不再要求额外配置 cashier authority；
  - `device_code` 必须已绑定当前门店且处于启用状态，未绑定、跨店或禁用设备均返回 `code=4030`；
  - 云端根据 `shop_id` 与 `device_code` 权威签发或复用 `device_token`；显式轮换时旧 Token 立即失效；
  - 请求体中客户端提交的 `device_token`/`token` 一律忽略，客户端不得指定凭据；
-   云端返回包含权威 `device_token` 的完整设备信息；
  - 收银端本地 Token Hash 仅作响应缓存索引和审计元数据，不得作为在线 HTTP/WS 的准入或拒绝依据。

## 外卖与真省钱（ZSQ）配送实际费用与运力渠道契约（2026-10-02）

- **适用接口**：
  - `GET /admin/takeout/delivery/detail`：管理端外卖配送扩展详情
  - `POST /admin/takeout/delivery/list`：管理端外卖配送分页列表
  - `GET /admin/takeout/delivery/tracking` / `GET /order/takeout/zsq/tracking`：骑手定位与履约追踪
- **新增字段**：
  - `t_takeout_delivery` / `TakeoutDelivery`：
    - `zsq_actual_fee`（`decimal(10,2)`）：真省钱实际跑腿扣费（元），从真省钱订单详情接口中 `shopActualCost`（优先）或 `discountLastMoney` 提取。
    - `zsq_delivery_supplier_name`（`varchar(64)`）：实际配送运力渠道名称（如“京东特惠”、“达达快送”、“美团跑腿”等），从真省钱订单详情 `deliverySupplierName` 或操作轨迹日志中提取。
    - `actual_delivery_fee`（`BigDecimal`）：语义别名（非表字段），取自 `zsq_actual_fee`，列表与实体统一返回。
  - `ZsqRiderTrackingResponse`：
    - `actualFee`（`BigDecimal`）：真省钱实际跑腿费用（元）。
    - `deliverySupplierName`（`String`）：真省钱实际配送运力渠道。
- **履约与恢复行为**：
  - 骑手接单、配送或查询轨迹时，字段由后台自动同步并持久化至 `t_takeout_delivery`；
  - 运营端重发配送（`POST /admin/takeout/delivery/zsq/redispatch`）或开启新一轮叫单时，自动清理上一轮的 `zsq_actual_fee` 与 `zsq_delivery_supplier_name`，避免历史数据残留。

## 外卖配送记录列表时间筛选与实际配送费返回契约（2026-10-07 / WI-003）

- **接口**：`POST /admin/takeout/delivery/list`
- **请求参数**：
  - `pageNum`（可选，数字，默认 1）：页码
  - `pageSize`（可选，数字，默认 20，最大 100）：每页条数
  - `dispatch_status`（可选，字符串）：履约状态过滤（`all` 或不传表示全部）
  - `startTime` / `start_time`（可选，字符串）：筛选起始时间（支持 `yyyy-MM-dd HH:mm:ss`、`yyyy-MM-dd HH:mm`、`yyyy-MM-dd`）
  - `endTime` / `end_time`（可选，字符串）：筛选截止时间（格式同上）
- **时间窗口规则（对齐营业日）**：
  - 未传 `startTime` 与 `endTime` 时，默认使用当前活动营业班次窗口 `[D settle_time, D+1 settle_time)`（基于门店 `settle_time`，未配置兜底 `04:00`），与后台订单列表及日结口径严格统一；
  - 仅传 `endTime` 时，起始时间自动推导至该截止时间对应的营业班次起始点 `[D settle_time, endTime)`；
  - 仅传 `startTime` 时，截止时间自动收敛至当前时刻 `now`；
  - `endTime` 早于 `startTime` 时拦截并返回 HTTP 400 `endTime cannot be earlier than startTime`。
- **返回数据**：
  - `code`: 0
  - `list`: 外卖配送记录数组（每项包含 `actual_delivery_fee` 实际配送费，取自 `zsq_actual_fee`）
  - `total`: 满足条件的总记录数
  - `pageNum`: 当前页码
  - `pageSize`: 每页条数
  - `startTime`: 实际生效的筛选起始时间（回显）
  - `endTime`: 实际生效的筛选截止时间（回显）
- **关联扩展**：
  - `t_order` 实体非持久化字段同步扩展 `actual_delivery_fee`（Double），在 `TakeoutDeliveryService.enrichOrder`/`enrichOrders` 中自动带出关联的实际配送费。

## KDS 设备删除与级联清理契约（2026-10-08 / WI-004）

- **背景与解决问题**：
  - 此前管理端删除/解绑设备接口仅将 `t_kds_device.enabled` 置为 0 并清空 Token，未物理删除数据库行；且列表查询未过滤 `enabled=1`，导致前端重新获取列表时设备依然存在，出现“无法真正删除设备”的问题。
  - 本次升级确保删除设备时对 `t_kds_device` 执行**真正的物理删除**，并级联清理关联配置，发布注销事件使各端即刻生效。

- **接口定义**：
  - **路径**：`POST /admin/kds/device/unbind`（完全兼容现有前端）或 `POST /admin/kds/device/delete`（别名，亦支持 `GET` / `DELETE`）
  - **权限**：`kds:config`
  - **请求头**：`X-Shop-Id: {shopId}`
  - **请求体（或 Query 参数）**：
    - `id` / `deviceId` / `device_id`（可选，数字）：设备主键 ID（优先级高于设备编码）
    - `device_code` / `deviceCode`（可选，字符串）：设备编码
    - *两者至少提供其一，否则返回 `code=500` "device_code 或 id 不能为空"*
  - **业务处理动作（事务内执行）**：
    1. 校验设备属于当前请求门店 `shop_id`；
    2. 物理删除 `t_kds_device_workflow` 中该设备对应的工作流配置；
    3. 物理删除 `t_kds_device_screen` 中该设备对应的可见烤制岗配置；
    4. 物理删除 `t_kds_device_pairing_ticket` 中该门店与该设备对应的未消费配对票据；
    5. 物理删除 `t_kds_device` 数据库行；
    6. 发布 `KdsDeviceCredentialChangedEvent`，即刻作废该设备在云端与各端缓存的凭据，并通知 WebSocket / LAN 断开该设备会话。
  - **设备列表防护**：
    - `GET /admin/kds/device/list` 增加 `enabled = 1` 条件过滤，彻底阻断历史软解绑残留记录回显。

## 数据报表接口时间窗口规范与营业日自动补全契约（2026-10-08 / WI-005）

- **背景与解决痛点**：
  - 数据报表与数据分析功能在前端通常提供快捷日期档位（今日、昨日、近7天、近30天）以及自定义时间区间。此前部分接口强制要求传入时分秒（`yyyy-MM-dd HH:mm:ss`），或传入纯日期后直接以自然日 `00:00:00` 比较，导致截断或查不到晚间跨日数据，与门店实际营业日（以 `settle_time` 如 `04:00` 为界）口径脱节。
  - 本次升级使数据报表及数据分析全线接口支持传入纯年月日（`yyyy-MM-dd`），并根据门店营业日截止时间（`settle_time`，未配置默认 `04:00`）自动补全为标准的营业日窗口；同时完全保留自定义时间传参（携带时分秒）的精确控制能力。

- **适用接口清单**：
  1. **数据分析系列**：
     - `GET /admin/analytics/business`：营业数据总览
     - `GET /admin/analytics/business/trend`：营业趋势分析
     - `GET /admin/analytics/dishes`：菜品销量与毛利分析
     - `GET /admin/analytics/customers`：顾客画像与新老客分析
     - `GET /admin/analytics/members`：会员充值与营收贡献
     - `GET /admin/analytics/marketing`：营销活动效果与ROI
  2. **数据报表系列**：
     - `GET /admin/report/daily`：日报。支持 `date` 与 `detail`（布尔值，默认 false）。`detail=true` 时返回商业级 8 大维度日结报告（基础元数据、营收核心、支付渠道明细、钱箱现金盘点、就餐方式分布、会员运营简报、风控异常审计、热销菜品 TOP 10 榜单与热敏打印文本）；`detail=false` 时返回轻量级汇总（兼容 totalAmount, orderCount, grossRevenue, totalDiscount, totalRefund 等）。
     - `GET /admin/report/weekly`：周报
     - `GET /admin/report/dishRanking`：菜品销售排行榜
     - `GET /admin/report/cashierPerformance`：收银绩效统计
     - `GET /admin/report/shopProfit`：门店营收与利润
     - `GET /admin/report/compare`：同比/环比分析
     - `GET /admin/report/repurchase/weekly`：周复购率
     - `GET /admin/report/repurchase/newCustomer`：新客复购率
     - `GET /admin/report/dashboard`：运营看板汇总
  3. **订单销售统计系列**：
     - `GET|POST /admin/order/statisticsCategorySales`：分类销售额统计
     - `GET|POST /admin/order/statisticsDishSales`：菜品销售额统计
  4. **异步导出任务**：
     - `POST /admin/reports/exports`：报表数据导出任务创建

- **时间参数别名支持**：
  - 各接口统一兼容如下参数别名：
    - 起始时间：`startTime` / `startDate` / `start`（单日查询支持 `date`）
    - 截止时间：`endTime` / `endDate` / `end`

- **时间窗口解析规则（权威口径）**：
  1. **纯日期输入（快捷档位：今日、昨日、近7天、近30天等）**：
     - 格式：`yyyy-MM-dd`（例如 `2026-10-08`）；
     - 自动结合门店 `settle_time`（未配置默认 `04:00`）补全为：
       - 起始时间：`startDate settle_time`（例如 `2026-10-08 04:00:00`）；
       - 截止时间：`(endDate + 1日) settle_time`（例如 `2026-10-09 04:00:00`）；
     - 典型示例（假设门店 `settle_time = 04:00`）：
       - **今日**（`start=2026-10-08, end=2026-10-08` 或 `date=2026-10-08`）：`[2026-10-08 04:00:00, 2026-10-09 04:00:00)`
       - **昨日**（`start=2026-10-07, end=2026-10-07`）：`[2026-10-07 04:00:00, 2026-10-08 04:00:00)`
       - **近7天**（`start=2026-10-02, end=2026-10-08`）：`[2026-10-02 04:00:00, 2026-10-09 04:00:00)`
       - **近30天**（`start=2026-09-09, end=2026-10-08`）：`[2026-09-09 04:00:00, 2026-10-09 04:00:00)`
  2. **自定义时间输入（带时分秒）**：
     - 格式：`yyyy-MM-dd HH:mm:ss` 或 `yyyy-MM-dd HH:mm`；
     - 后端**精确保留**客户端传入的具体时分秒，仅进行格式规范化（`T` 转为空格，缺失秒自动补 `:00`），不进行营业日强制替换；
     - 示例：`start=2026-10-08 10:00:00, end=2026-10-08 22:30:00` → `[2026-10-08 10:00:00, 2026-10-08 22:30:00]`
  3. **缺省传参兜底**：
     - 若起始与截止时间均未传，默认使用最近已结算营业日的完整 24 小时周期；
     - 若仅传一端纯日期，另一端自动对齐该日期（即单日营业日查询）。



## 统一实时消息通道与出餐超时动态阈值契约（2026-10-31 / WI-078）

### 1. 统一 WebSocket 实时通道（`WS /ws/v1/notify`）
- **连接地址**：`ws(s)://<host>/ws/v1/notify?client_type=CASHIER|MINI_PROGRAM&shop_id=<shopId>&token=<jwt>&openid=<openid>&device_id=<deviceId>`
- **鉴权规则**：
  - `client_type=CASHIER`：校验管理员 JWT（`token` 参数或 `Authorization: Bearer <jwt>`）或收银 KDS 租约（`X-Cashier-Lease-Token`）；校验失败返回 `1008 POLICY_VIOLATION`。
  - `client_type=MINI_PROGRAM`：按 `shop_id` 与 `openid` 绑定会话，支持连接后发送 `{"frame_type":"BIND_CONTEXT","shop_id":1,"openid":"..."}` 动态切换上下文。
- **标准消息信封（`UnifiedMessageEnvelope`）**：
  - 顶层字段：`frame_type` (`EVENT`/`CONNECTED`/`PONG`/`ACK_RESULT`/`CONTEXT_BOUND`)、`message_id`（全局唯一幂等键）、`seq_id`（单调递增游标）、`timestamp`、`expire_at`、`target`、`business_type`、`event_type`、`priority` (`P0`/`P1`/`P2`/`P3`)、`require_ack`、`display_strategy`、`payload`。
  - 核心事件类型：
    - `NEW_ORDER_PAID` (`P1`)：新订单支付完成提醒（顶部横幅 + 语音播报）
    - `ORDER_PREP_TIMEOUT` (`P0`)：订单出餐超时强阻断告警（按门店动态阈值触发，常驻告警条 + 循环语音提醒）
    - `COUPON_GRANTED` (`P1`)：新优惠券到账提醒（含 `aggregation_key="COUPON_GRANTED"`、`aggregation_window_ms=800` 防轰炸聚合，离线自动降级微信订阅消息）
    - `ALERT_DISMISSED` (`P2`)：同门店多台收银机任一终端确认后广播消除告警
    - `TABLE_ORDER_CHANGED` (`P2`) / `KDS_DELIVERY_AVAILABLE` (`P2`) / `MEAL_PICKUP_READY` (`P1`) / `TAKEOUT_DISPATCH_ALERT` (`P0`) / `TAKEOUT_DISPATCH_CHANGED` (`P2`) / `DISH_CATALOG_CHANGED` (`P3`) / `SHOP_BUSINESS_CHANGED` (`P2`)

### 2. 配套 REST 接口
1. `GET /admin/shop/notification-config`：查询门店出餐超时动态阈值配置（默认开启、`prep_timeout_minutes=15`、`timeout_repeat_interval_seconds=60`）。
2. `PUT /admin/shop/notification-config`：修改门店出餐超时动态阈值配置（`prep_timeout_minutes` 合法范围 `5~120` 分钟）。
3. `GET /cashier/notifications/sync`（别名 `GET /api/v1/notifications/sync`）：断线重连后按 `last_seq_id` 增量拉取未读且未过期的通知列表及 `server_head_seq_id`。
4. `POST /cashier/notifications/ack`（别名 `POST /api/v1/notifications/ack`）：批量确认消息已读并向同门店所有收银终端广播 `ALERT_DISMISSED`。
5. `GET /config/subscribe-templates`：新增返回 `templates.couponGranted`、`templates.couponExpiring` 供小程序端订阅优惠券到账与临期通知。
6. `GET /user/notifications/sync` 与 `POST /user/notifications/ack`（Phase 2 / WI-079）：C端小程序专用增量同步与已读确认入口，支持 `X-User-Token` 自动绑定 `openid` 并拦截跨用户越权请求（返回 `403`）。
7. 新增 Phase 2 实时事件：
   - `COUPON_EXPIRING_SOON` (`P2`, `BOTTOM_SNACKBAR`)：优惠券临期提醒（默认过期前 120 分钟扫描触发，在线推送底部悬浮条，离线降级微信订阅消息）。
   - `ORDER_READY_FOR_PICKUP` (`P0`, `TOP_BANNER_AND_VIBRATE`)：C端顾客专属取餐强提醒（按订单 `openid` 精准推送取餐码与桌号）。
   - `REFUND_REQUESTED` (`P0`, `PERSISTENT_ALERT_BANNER`)：B端收银台退单/退款申请强提醒。
   - `ACTIVITY_POPUP_CHANGED` (`P2`, `MODAL_POPUP_OR_INVALIDATE`)：后台新增/修改/删除营销活动弹窗时实时广播，小程序端失效 3 分钟缓存并纳入单模态优先级队列（`P1 优惠券弹窗 > 500ms 冷却 > P2 活动海报弹窗`）展示。
   - `SHOP_ANNOUNCEMENT_CHANGED` (`P2`, `TOP_NOTICE_BAR`)：后台新增/修改/删除门店公告时实时广播，小程序顶部通告栏即时刷新。
   - `QUEUE_TICKET_CALLED` (`P0`, `TOP_BANNER_AND_VIBRATE`)：C端排队叫号到号强提醒（按取号顾客 `openid` 精准触达，顶部强提醒卡片 + 震动）。
   - `ORDER_REFUND_PROCESSED` (`P1`, `TOP_BANNER`)：C端顾客订单退款审批/到账结果通知。


### 统一消息通道监控与测试运维 API (Phase 3)

#### 1. 门店通道连接与待处理告警统计
- **接口路径**: `GET /admin/notifications/channel-stats` / `GET /cashier/notifications/channel-stats`
- **请求参数**: `shop_id` (可选，默认 1)
- **响应示例**:
```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "shop_id": 1,
    "cashier_online_count": 2,
    "mini_program_online_count": 18,
    "total_connected_sessions": 20,
    "pending_p0_count": 1,
    "pending_p1_count": 3,
    "server_head_seq_id": 1024
  }
}
```

#### 2. 模拟全链路测试推送
- **接口路径**: `POST /admin/notifications/test-push` / `POST /cashier/notifications/test-push`
- **请求体**:
```json
{
  "shop_id": 1,
  "event_type": "ORDER_PREP_TIMEOUT"
}
```

#### 3. 手动触发过期与已读历史通知归档清理
- **接口路径**: `POST /admin/notifications/cleanup`
- **请求体**:
```json
{
  "retention_days": 7
}
```


---

## 飞书素材接收与本地烧烤 AI 工作流接口契约（2026-10-31）

### 1. 业务背景与协作模型
为实现「飞书群/机器人接收素材 → 自动下载沉淀收件箱 → 本地主控轮询拉取 → 识别平台并落地百度同步盘 → 触发本地 AI Worker 处理 → 结果发回飞书」的业务闭环：
- **飞书事件订阅推送**：配置回调地址为 `POST https://laofei.com.cn/feishu/callback`，订阅 `im.message.receive_v1` 事件；
- **收件箱持久化（/data/bbq_inbox/）**：每条收到消息独立创建 `{yyyyMMdd_HHmmss}_{message_id}` 子目录，写入标准 `meta.json`，并由服务端后台自动获取 `tenant_access_token` 下载图片与视频原文件至 `media/` 目录下；
- **本地主控拉取与确认**：本地主控轮询 `GET /bbq/inbox` 获取 `downloaded=true` 的就绪素材列表，通过暴露的静态 URL 下载素材，处理完毕调用 `POST /bbq/inbox/ack` 进行归档防重。

### 2. 接口详细定义

#### 2.1 飞书事件订阅回调（POST /feishu/callback）
- **权限与认证**：飞书官方回调免 JWT，支持 Verification Token 明文校验与 Encrypt Key AES-256-CBC 解密模式；
- **URL 首次验证（type=url_verification）**：
  - 请求体：`{"type": "url_verification", "token": "...", "challenge": "..."}`
  - 响应体：`{"challenge": "..."}`
- **消息接收事件（im.message.receive_v1）**：
  - 解析 `message_id`、`chat_id`、`sender_open_id`、`create_time`、`message_type` 及 `content`；
  - 具备 `message_id` 强幂等防重机制；
  - 异步触发 `tenant_access_token` 获取与媒体原文件下载，就绪后更新 `meta.json` 中 `downloaded=true`；
  - 响应：`{"code": 0}`。

#### 2.2 本地主控拉取待处理素材列表（GET /bbq/inbox）
- **认证**：可选安全防线 `X-Inbox-Token` 请求头或 `token` 查询参数（由配置项 `feishu.inbox-token` 约定）；
- **响应数据结构**：
```json
{
  "code": 0,
  "data": {
    "items": [
      {
        "inbox_id": "20261031_100001_om_xxx",
        "meta_url": "https://laofei.com.cn/bbq/inbox/20261031_100001_om_xxx/meta.json",
        "media_urls": [
          "https://laofei.com.cn/bbq/inbox/20261031_100001_om_xxx/media/1.jpg"
        ],
        "downloaded": true
      }
    ]
  }
}
```

#### 2.3 本地主控确认已取走素材（POST /bbq/inbox/ack）
- **认证**：可选 `X-Inbox-Token` 或 `token`；
- **请求体**：
```json
{
  "inbox_id": "20261031_100001_om_xxx",
  "status": "ok"
}
```
- **处理逻辑**：校验 `inbox_id` 防范路径穿越，将收件箱子目录原子移动至归档目录（`/data/bbq_inbox_archive/`），避免本地主控重复消费；
- **响应**：`{"code": 0}`。

#### 2.4 静态素材下载与查看（GET /bbq/inbox/{inboxId}/**）
- **用途**：供本地主控或浏览器直接流式下载 `meta.json` 及 `media/` 原文件；
- **安全**：严密防范 `..` 路径穿越攻击，确保仅能在子目录授权范围内读取。

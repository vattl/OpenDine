# D026 — KDS 统一看板设备级岗分流（方案 A）

> 状态：
> **方案待确认**
> （未动代码）
> 分支：
> `codex/audit-remediation`
> 　范围：
> `server`
> 子项目
> 关联：D025 已提交；前置审计已确认统一看板取数不分设备、旧五屏 grill/board 按设备 tag 真分流

## 1. 背景与目标

### 1.1 背景



* 多台 KDS 统一看板（`workflow_board`）设备时，`KdsOverviewBoardService` 所有取数（`collectEnrichedItems` / `collectOrderViewItems` / `countWorkflowQueues`）只按 `shop_id + PRODUCTION_GRILL_TAGS（meat_grill/veg_grill/seafood_special 全三岗）+ queue` 过滤，**不按设备过滤** → 多台设备看到的工单完全一致，无法把荤 / 素 / 海鲜分到不同设备。

* 旧五屏模式有岗级分流能力：`/kds/grill/board` 强制 `tag == device.screen_tag`（403 越权），`KdsGrillBoardService.buildBoard(shopId, screenTag)` 按屏过滤取数。但旧屏接口无统一看板的队列统计 / 合并规则 / 归档能力，且已定位为遗留路径。

* 现状仅存的统一看板分流粒度是**环节**（`t_kds_device_workflow`：prep/cook/serve 多选 + `canAccessQueue` 403 控制），**岗级**（同一 cook 队列内按荤 / 素 / 海鲜拆分）缺失。

### 1.2 目标

给统一看板增加**设备级可见岗**配置：设备可多选烤制岗（如设备 1 = 荤菜岗，设备 2 = 素菜 + 海鲜岗），统一看板取数按设备可见岗过滤。未配置设备保持三岗全选（行为不变，100% 兼容）。

### 1.3 非目标（明确不做）



* 不改建单路由：`KdsRoutingService.resolve`、`t_kds_ticket` 创建逻辑不动（工单仍按菜品 / 分类 / 默认屏 → 三岗档口创建）。

* 不动旧五屏 REST（`/kds/grill` 等）与设备→队列访问控制（`canAccessQueue` 语义不变）。

* 不改 `KdsWebSocketHub` 订阅模型：WS 推送 V1 仍按 `screen_tag` 桶全量广播，**不按设备岗过滤**（客户端按自身岗过滤渲染；按设备订阅列为 V2 可选）。

* 不新增订单 / 菜品侧字段。

## 2. 现状（Current State）

### 2.1 设备配置现状（已审计）



* `t_kds_device`：单 `screen_tag`（设备主屏身份）+ `station_id` + token；**无多岗配置**。

* `t_kds_device_workflow`（`db_diancan.sql`）：`device_id` 主键 + `workflows` 逗号分隔（prep/cook/serve），由 `KdsWorkflowStore` 读写。

* 配置入口：`POST /kds/device/login`（设备登录，body 可带 `screenTag` + 可选 `workflows`）；`POST /admin/kds/device/bind`（管理端绑定，仅单 screen\_tag，无 workflows）。

### 2.2 取数链路现状（已审计）



```
KdsWorkflowController.board/bootstrap（device 已鉴权）

&#x20;→ KdsWorkflowService.buildBoard(device, ...)

&#x20;  → KdsOverviewBoardService.buildBoard(shopId, queue, ...)   // ← device 上下文丢失

&#x20;    → collectEnrichedItems(shopId, q, d, extras, kw, ...)

&#x20;      → .eq("shop\_id", shopId).in("screen\_tag", PRODUCTION\_GRILL\_TAGS).applyQueueFilter(q)
```

`device` 只用于 `canAccessQueue`（403 访问控制）与 `isPrepWorkflowEnabled`，**取数层拿不到设备身份** → 岗级过滤无从谈起。

### 2.3 涉及关键文件

`KdsOverviewBoardService`（collectItems / collectEnrichedItems / collectOrderViewItems / countWorkflowQueues）、`KdsWorkflowService`（buildBoard / buildBootstrap / countQueues）、`KdsDeviceService`（bind / saveWorkflowSelection / enrichWorkflows / unbind）、`KdsDeviceController`（login / me）、`AdminKdsController`（device/bind / device/list）、`KdsWorkflowStore`（模式参照）。

## 3. 方案设计（方案 A：设备可见岗过滤）

### 3.1 总体思路

仿 `t_kds_device_workflow` 模式新增设备级 "可见岗" 存储；统一看板取数从 `device` 解析可见岗集合并注入查询条件（`.in("screen_tag", effectiveTags)`）。**岗（看什么菜）与环节（看哪个队列）正交组合**，默认未配置 = 三岗全选 = 现状。

### 3.2 数据模型

新增表 `t_kds_device_screen`（仿 `t_kds_device_workflow`，不动 `t_kds_device` 主表）：



```
CREATE TABLE IF NOT EXISTS \`t\_kds\_device\_screen\` (

&#x20; \`device\_id\` bigint NOT NULL COMMENT 't\_kds\_device.id',

&#x20; \`screen\_tags\` varchar(128) NOT NULL COMMENT '可见烤制岗，逗号分隔：meat\_grill,veg\_grill,seafood\_special',

&#x20; \`updated\_at\` datetime NOT NULL DEFAULT CURRENT\_TIMESTAMP ON UPDATE CURRENT\_TIMESTAMP,

&#x20; PRIMARY KEY (\`device\_id\`)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='KDS 设备可见岗';
```

语义：



* **无记录 / 空值 / 删除** → 三岗全选（`PRODUCTION_GRILL_TAGS`），与现状完全一致。

* 仅接受三岗子集；传入其他 tag 静默忽略，全非法则按清空处理（回默认三岗）。

DDL 落点：`db_diancan.sql` 全量定义 + 增量同步脚本（与 `t_kds_device_workflow` 一致）。

### 3.3 接口变更



| 接口                            | 变更                                                                |
| ----------------------------- | ----------------------------------------------------------------- |
| `POST /kds/device/login`      | body 增加可选 `screenTags` / `screen_tags`（数组）→ `saveScreenSelection` |
| `POST /admin/kds/device/bind` | body 增加可选 `screenTags` / `screen_tags`（数组）→ 同上（管理端便捷配置）           |
| `GET /admin/kds/device/list`  | 返回体每个 device 增加 `screen_tags`（enrichScreens）                      |
| `GET /kds/device/me`          | 返回体增加 `screen_tags`                                               |

字段命名沿用项目双兼容惯例（camelCase + snake\_case 均可识别）。

### 3.4 服务层



* 新增 `KdsDeviceScreenStore`（仿 `KdsWorkflowStore`，JdbcTemplate）：


  * `List<String> get(long deviceId)` — 无记录返回空

  * `void save(long deviceId, List<String> screenTags)` — 空 / 全非法 → delete（回默认）

  * `void delete(long deviceId)`

* `KdsDeviceService`：


  * `saveScreenSelection(Long deviceId, List<String> screenTags)` — 过滤仅保留三岗子集

  * `Set<String> screenTagsOf(KdsDevice device)` — 有配置返回配置 ∩ 三岗；否则默认三岗（**取数层统一入口**）

  * `enrichScreens(KdsDevice device)` — 组装 `screen_tags` 回显（list/me 用）

  * `unbind` / `delete` 时同步清理 screen 记录

  * `bind` 透传可选 screenTags 参数

### 3.5 取数层



* `KdsOverviewBoardService`：


  * `collectEnrichedItems(..., Set<String> screenTags)` 新增参数：`.in("screen_tag", screenTags)` 替换写死的 `PRODUCTION_GRILL_TAGS`；`screenTags == null` 时仍用三岗（防御）。

  * `collectItems` / `collectOrderViewItems` / `countWorkflowQueues` 同步透传。

* `KdsWorkflowService`：


  * `buildBoard` / `buildBootstrap` / `countQueues` 从 `device` 取 `screenTagsOf(device)` 传入取数层。

* `KdsWorkflowController`：**无需改动**（`device` 已在方法内，透传发生在 Service 层）。

* 订单视图（`collectOrderViewItems` 的 `.in("screen_tag", PRODUCTION_GRILL_TAGS)`）同步替换为设备可见岗。

### 3.6 兼容性



* 无 `t_kds_device_screen` 记录的老设备 → 三岗全选，行为与现状逐字节一致。

* `screen_tags` 与 `workflows` 正交：设备 1 = \[meat\_grill] × \[cook]（只看荤菜烤制）；设备 2 = \[meat\_grill, veg\_grill] × \[serve]（荤素传菜）。

* 旧五屏设备（grill/expedition/skewer 绑定）不读 screen\_tags，不受影响。

* `decorateBoard` 的 `screen_tag`（写死 BOSS\_OVERVIEW 的兼容字段）不动。

## 4. 边界与决策

### 4.1 与 workflows（环节）正交

`screen_tags`（岗维度）与 `workflows`（环节维度）是两种独立分流，取交集即为 "某设备看某岗的某环节"。`canAccessQueue` 保持现状只控环节，岗过滤由取数条件完成。

### 4.2 WS 推送（V1 全量，V2 可选）

`KdsPushService` 按 `screen_tag` 桶广播（`workflow_board` 桶收到三岗全部变更）。V1 不改 WS：客户端收到事件后按自身 `screen_tags` 本地过滤渲染（REST 拉取已精确，WS 只是增量提示）。V2 可选：`KdsWebSocketHub` 增加按设备订阅，推送按设备岗过滤，避免荤菜机收到素菜事件。

### 4.3 不改变建单路由

本方案只改**展示层过滤**。工单创建仍依赖 `resolve`（菜品 / 分类 / 默认屏 → 三岗档口 enabled=1）。若门店某岗档口停用，该岗无工单，设备即使配置了该岗也自然无数据 —— 行为合理，无需额外处理。

## 5. 影响面（文件清单）



| 类型 | 文件                               | 说明                                                                  |
| -- | -------------------------------- | ------------------------------------------------------------------- |
| 新增 | `KdsDeviceScreenStore.java`      | 可见岗存取（仿 KdsWorkflowStore）                                           |
| 新增 | `KdsDeviceScreenStoreTest.java`  | get/save/delete/ 非法过滤                                               |
| 修改 | `KdsDeviceService.java`          | saveScreenSelection /screenTagsOf/enrichScreens /bind 透传 /unbind 清理 |
| 修改 | `KdsDeviceController.java`       | login 解析 screenTags；me 回显                                           |
| 修改 | `AdminKdsController.java`        | device/bind 解析 screenTags；device/list 回显                            |
| 修改 | `KdsOverviewBoardService.java`   | collectEnrichedItems 等加 screenTags 过滤                               |
| 修改 | `KdsWorkflowService.java`        | buildBoard/buildBootstrap/countQueues 透传设备可见岗                       |
| 修改 | `docs/db_diancan.sql` + 增量同步 SQL | 新增 t\_kds\_device\_screen                                           |
| 修改 | `docs/openapi.yaml`              | device/login、device/bind、device/list、device/me 补充 screenTags 字段     |

## 6. 测试计划



* `KdsDeviceScreenStoreTest`：保存 / 读取 / 删除 / 全非法回默认。

* `KdsOverviewBoardServiceTest`（新增或扩展）：`screenTags=[meat_grill]` 时荤菜工单进入、素 / 海鲜工单排除；`null` → 三岗全选；与 queue 过滤叠加。

* `KdsDeviceServiceTest`（扩展）：saveScreenSelection 过滤、screenTagsOf 默认三岗、unbind 清理。

* 全量 `mvn test` 回归（现 836 用例基线）。

* 手工验证：3 台设备分别配 \[荤]/\[素 + 海鲜]/\[全] → REST board 各自只出对应岗；未配置设备行为不变。

## 7. 风险与回滚



* **前端需配合**：登录 / 绑定时不传 `screenTags` 则无分流效果（但不报错、不回归）。前端发布前可先配一台验证。

* **WS 全量推送**：客户端渲染需按岗本地过滤；若客户端不做过滤，可能出现 "收到但不显示" 的浪费事件（无正确性问题）。V2 再优化。

* **新表初始化**：依赖 schema 初始化脚本执行（生产需跑 DDL），未执行前功能自动回退为默认三岗（无记录 = 现状）。

* **回滚**：仅删 `t_kds_device_screen` 数据 / 表即可回到全量模式；代码层改动集中在取数与服务层，回退无残留风险。
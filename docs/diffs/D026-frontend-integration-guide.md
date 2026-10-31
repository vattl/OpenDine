# D026 前端调用方案（KDS 统一看板设备级岗分流）

> 给前端 AI 的集成说明。服务端已完成：设备可见岗配置存储、看板 / 角标按岗过滤。前端需配合：管理端配置、设备登录持久化、WebSocket 按岗过滤。
> 契约版本：openapi v1.2.237 起。改动后端提交：
>
> `354ff7c`
>
> 。

## 1. 概念与数据模型

### 1.1 两个易混淆的概念



| 概念                   | 字段                           | 说明                             | 可选值                                                                                                                             |
| -------------------- | ---------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| **屏型 screen\_tag**   | `screenTag` / `screen_tag`   | 设备是哪种屏（登录 / 绑定时的必填项）           | `workflow_board`（统一工作流看板）/ `meat_grill` / `veg_grill` / `seafood_special` / `skewer_aggregate` / `expedition` / `boss_overview` |
| **可见烤制岗 screenTags** | `screenTags` / `screen_tags` | 统一看板设备**能看到哪些岗的菜**（D026 新增，可选） | 仅 `meat_grill` / `veg_grill` / `seafood_special` 的子集                                                                            |

### 1.2 设备对象（KdsDevice）新增字段



```
{

&#x20; "id": 2,

&#x20; "shop\_id": 1,

&#x20; "screen\_tag": "workflow\_board",

&#x20; "device\_code": "KDS-WORK-01",

&#x20; "device\_name": "后厨综合屏",

&#x20; "workflows": \["prep", "cook", "serve"],

&#x20; "screen\_tags": \["meat\_grill", "veg\_grill"],   // D026 新增：可见烤制岗

&#x20; "device\_token": "fc19caa1b3794f4a92e0c5bc23805343"

}
```

**规则（前端必须遵守）**：



* `screen_tags` 为空数组 / 字段缺失 = **三岗全选**（`["meat_grill", "veg_grill", "seafood_special"]`），与改造前行为完全一致

* 传非法值（非三岗）会被服务端忽略；全非法按清空处理 → 回默认三岗全选

### 1.3 前端有效岗计算（伪代码）



```
const ALL\_GRILL\_TAGS = \['meat\_grill', 'veg\_grill', 'seafood\_special'];

function effectiveScreenTags(device: KdsDevice): string\[] {

&#x20; const tags = (device.screen\_tags ?? \[]).filter(t => ALL\_GRILL\_TAGS.includes(t));

&#x20; return tags.length > 0 ? tags : \[...ALL\_GRILL\_TAGS];   // 空/全非法 => 三岗全选

}
```



***

## 2. 接口契约

### 2.1 管理端绑定 / 编辑设备：`POST /admin/kds/device/bind`

请求体（camelCase 与 snake\_case 二选一均可，camelCase 优先）：



```
{

&#x20; "deviceCode": "KDS-WORK-01",        // 必填（或 device\_code）

&#x20; "deviceName": "后厨综合屏",          // 可选（或 device\_name）

&#x20; "screenTag": "workflow\_board",      // 必填，屏型（或 screen\_tag）

&#x20; "screenTags": \["meat\_grill", "veg\_grill"]   // 可选，可见烤制岗（或 screen\_tags）

}
```



* 不传 `screenTags` / 传 `[]` = 删除该设备可见岗配置 = 三岗全选

* 响应：`{ code: 0, device: { ..., screen_tags: [...] } }`

### 2.2 设备端登录：`POST /kds/device/login`

请求体：



```
{

&#x20; "shop\_id": 1,                        // 必填

&#x20; "device\_code": "KDS-WORK-01",        // 必填

&#x20; "screen\_tag": "workflow\_board",      // 必填，屏型

&#x20; "device\_name": "后厨综合屏",          // 可选

&#x20; "workflows": \["prep", "cook", "serve"],   // 可选，按原逻辑

&#x20; "screenTags": \["meat\_grill", "veg\_grill"] // D026：可见烤制岗（或 screen\_tags）

}
```

响应 `device` 回显 `screen_tags`。**前端必须持久化&#x20;**`device_token`**、**`screen_tag`**、**`shop_id`**、**`screen_tags`**、**`workflows`，冷启动 / 重启后再次调用 login 回传。

### 2.3 查询当前设备：`GET /kds/device/me`



* 请求头：`X-Kds-Device-Token: <device_token>`

* 返回 `device`（含 `screen_tags`，未配置为空数组）

* 用途：App 冷启动 / 页面刷新前核对 `screen_tag`/`shop_id` 与本地缓存是否一致；**换岗必须重新 login**，me 不会刷新 token / 岗

### 2.4 管理端设备列表：`GET /admin/kds/device/list`



* 每台设备回显 `screen_tags`（未配置为空数组），用于编辑页回显勾选

### 2.5 统一看板：`GET /kds/workflow/bootstrap`、`GET /kds/overview/board`



* 请求头：`X-Kds-Device-Token`

* 服务端**已按设备可见岗过滤**工单列表与队列角标，前端直接渲染

* `bootstrap` 返回结构：



```
{

&#x20; "screen\_tag": "workflow\_board",

&#x20; "queues": {

&#x20;   "pending\_prep": { /\* board \*/ },

&#x20;   "pending\_cook": { /\* board \*/ }

&#x20; },

&#x20; "workflows": \["prep", "cook", "serve"],

&#x20; "visible\_queues": \["pending\_prep", "pending\_cook"],

&#x20; "queue\_counts": { "pending\_prep": 3, "pending\_cook": 5 },   // 已按设备岗过滤

&#x20; "enable\_prep\_workflow": true

}
```



* board 内每行工单（items）带 `screen_tag` 字段（该工单所属岗），前端**本地增量过滤时使用**：



```
{

&#x20; "ticket\_id": 58321,

&#x20; "detail\_id": 58321,

&#x20; "screen\_tag": "meat\_grill",   // 工单所属岗

&#x20; "item\_status": 0,

&#x20; "quantity": 1,

&#x20; // ... 其余字段不变

}
```

### 2.6 WebSocket 实时推送：`ws://<host>/ws/kds?shop_id=1&screen_tag=workflow_board&token=<device_token>`

消息信封（envelope）：



```
{

&#x20; "type": "new\_order",              // 事件类型

&#x20; "shop\_id": 1,

&#x20; "screen\_tag": "meat\_grill",       // 该消息所属桶/岗

&#x20; "payload": { /\* 事件体 \*/ }

}
```

事件类型：`new_order` / `update_order` / `order_status_changed` / `cancel_item` / `cancel_order` / `config_changed` / `dish_flags_changed` 等。

**重要（D026 非目标，前端必须处理）**：WS 仍按 `(shop_id, screen_tag)` 桶全量广播，**不会**按设备可见岗过滤。即：设备订阅 `workflow_board` 桶，会收到该桶内所有岗的工单事件。



***

## 3. 前端改动清单

### 3.1 管理端（设备绑定 / 编辑页）



* 绑定 / 编辑表单增加 \*\*"可见烤制岗" 多选 \*\*，三个选项：荤烤 `meat_grill`、素烤 `veg_grill`、海鲜 `seafood_special`

* 不选任何项 = 三岗全选（提交时省略 `screenTags` 或传 `[]`）

* 编辑时用 `GET /admin/kds/device/list` 返回的 `screen_tags` 回显勾选；保存用 `POST /admin/kds/device/bind` 提交 `screenTags`

### 3.2 设备端（统一看板 App）



1. **登录**：login 时带上本地持久化的 `screenTags`（如无则省略）；保存响应里的 `device.screen_tags`

2. **启动 / 刷新**：先调 `GET /kds/device/me` 核对并取最新 `screen_tags`（与本地不一致以服务端为准）；再调 `bootstrap` 拉全量

3. **渲染**：`bootstrap`/`board` 返回即已按岗过滤，**直接渲染，无需二次过滤**

4. **WS 处理（关键）**：

* 收到消息 → 解析 `envelope.screen_tag` → 若该值 ∈ 设备有效岗集合 → 处理；否则**丢弃**

* **例外**：`config_changed` / `dish_flags_changed` 等全局配置类消息（与岗无关），收到后**直接全量刷新**（重拉 bootstrap），不按岗过滤

* `cancel_order` 会广播到所有桶，按岗过滤后丢弃无关岗即可

* 最稳妥兜底：对 `new_order` / `update_order` / `order_status_changed` 类消息，也可选择**收到后重拉 board**（服务端过滤），仅在推送频繁时用增量过滤

### 3.3 WS 过滤伪代码



```
function shouldHandleWsMessage(msg: WsEnvelope, device: KdsDevice): boolean {

&#x20; if (\['config\_changed', 'dish\_flags\_changed'].includes(msg.type)) {

&#x20;   return true;                       // 全局配置类：直接刷新

&#x20; }

&#x20; if (msg.screen\_tag == null) {

&#x20;   return true;                       // 无岗信息：保守处理

&#x20; }

&#x20; return effectiveScreenTags(device).includes(msg.screen\_tag);  // 按岗过滤

}
```



***

## 4. 兼容与注意事项



* **旧设备完全兼容**：未配置 `screen_tags` 的设备 = 三岗全选，行为与改造前一致，前端无需为旧数据做特殊分支

* **改配置即时生效**：管理端改绑或设备重新 login 后，下次 `bootstrap`/`me` 即返回新 `screen_tags`；已连接的 WS 连接不会自动重连，需前端在检测到 `screen_tags` 变化时重新拉取（或重连 WS）

* **换岗**：必须重新调 `POST /kds/device/login`（`/kds/device/me` 不负责换岗）

* **参数命名**：请求体 camelCase /snake\_case 都接受（`screenTags` / `screen_tags`）；响应统一返回 snake\_case（`screen_tags`）

* 可见岗可选值**只有三个**：`meat_grill` / `veg_grill` / `seafood_special`，前端枚举需与之一致
# B 端接口与权限码汇总

B 端包含 **/admin** 与 **/cashier** 下所有需 JWT 鉴权的接口（不含已放行的 `/adminLogin`）。  
下表为接口路径、方法及对应权限码，用于录入 `t_api_permission` 并供拦截器校验。

## 权限码说明（与 docs/权限设计.md 一致）

| 权限码 | 说明 |
|--------|------|
| admin:password | 修改密码 |
| admin:manage | 管理员与角色、RBAC 配置、系统配置、日志等 |
| order:view | 订单列表、详情、订单日志 |
| order:operate | 接单、结账、明细删除、收银订单操作 |
| order:config | 自动接单、支付方式、日结等 |
| dish:manage | 菜品、分类、单位 |
| table:manage | 桌台 |
| banner:manage | 轮播图 |
| announcement:manage | 门店公告（连锁，t_announcement） |
| statistics:view | 营业额、分类/菜品销售、报表、报表分析 |
| user:view | 用户信息查询、会员 |
| user:points | 手动加积分 |
| kds:view | KDS 厨显只读（预留） |
| kds:operate | KDS 厨显操作（设备端 REST 以令牌鉴权） |
| kds:config | KDS 五屏档口、绑屏、门店模式、设备、工单重推 |
| cashier:shift | 收银班次（可选，此处与 order:config 归为一类或单独） |

注：收银端 `/cashier/*` 使用 order:operate、table:manage、statistics:view 等与后台一致的权限码，便于角色复用。

---

## 接口清单（按模块）

### 1. 登录与个人（不录入 t_api_permission 的公开接口）

| 路径 | 方法 | 说明 |
|------|------|------|
| /adminLogin | POST | 公开，不拦截 |
| /admin/me/permissions | GET | 登录后获取当前权限，仅需 JWT，未配置时放行 |

### 2. 管理员与密码

| 路径 | 方法 | 权限码 |
|------|------|--------|
| /admin/modifyPassword | POST | admin:password |
| /admin/administrator/list | GET | admin:manage |
| /admin/administrator/create | POST | admin:manage |
| /admin/administrator/ | PUT | admin:manage（匹配 /admin/administrator/{id}/roles） |

### 3. RBAC 配置

| 路径 | 方法 | 权限码 |
|------|------|--------|
| /admin/rbac/roles | GET | admin:manage |
| /admin/rbac/roles | POST | admin:manage |
| /admin/rbac/roles/ | DELETE | admin:manage（匹配 /admin/rbac/roles/{id}） |
| /admin/rbac/roles/ | PUT | admin:manage（匹配 /admin/rbac/roles/{id}/permissions） |
| /admin/rbac/permissions | GET | admin:manage |
| /admin/rbac/permissions | POST | admin:manage |
| /admin/rbac/permissions/ | DELETE | admin:manage（匹配 /admin/rbac/permissions/{id}） |
| /admin/rbac/api-permissions | GET | admin:manage |
| /admin/rbac/api-permissions | POST | admin:manage |
| /admin/rbac/api-permissions/ | DELETE | admin:manage（匹配 /admin/rbac/api-permissions/{id}） |

### 4. 系统配置

| 路径 | 方法 | 权限码 |
|------|------|--------|
| /admin/config/feieyun | GET | admin:manage |
| /admin/config/feieyun | PUT | admin:manage |
| /admin/config/invite-poster | GET | admin:manage |
| /admin/config/invite-poster | PUT | admin:manage |

### 5. 订单（admin）

| 路径 | 方法 | 权限码 |
|------|------|--------|
| /admin/order/list | GET | order:view |
| /admin/order/list | POST | order:view |
| /admin/orderDetail/list | GET | order:view |
| /admin/order/log/ | GET | order:view（匹配 /admin/order/log/{orderId}） |
| /admin/order/receiving | POST | order:operate |
| /admin/order/rece | POST | order:operate |
| /admin/order/checkout | POST | order:operate |
| /admin/order/refund | POST | order:operate（微信退款） |
| /admin/orderDetail/delete_menu | GET | order:operate |
| /admin/orderDetail/delete_menu | POST | order:operate |
| /admin/orderDetail/updateQuantity | POST | order:operate |
| /admin/order/auto-accept | GET | order:config |
| /admin/order/auto-accept | POST | order:config |
| /admin/order/banners | GET | banner:manage |
| /admin/order/addbanners | POST | banner:manage |
| /admin/order/uploadBannerFile | POST | banner:manage |
| /admin/order/delete_banners/ | DELETE | banner:manage（匹配 /admin/order/delete_banners/{id}） |
| /admin/order/salesvolume | GET | statistics:view |
| /admin/order/statisticsCategorySales | GET | statistics:view |
| /admin/order/statisticsCategorySales | POST | statistics:view |
| /admin/order/statisticsDishSales | GET | statistics:view |
| /admin/order/statisticsDishSales | POST | statistics:view |
| /admin/analytics/business | GET | statistics:view |
| /admin/analytics/business/trend | GET | statistics:view |
| /admin/analytics/dishes | GET | statistics:view |
| /admin/analytics/customers | GET | statistics:view |
| /admin/analytics/members | GET | statistics:view |
| /admin/analytics/marketing | GET | statistics:view |
| /admin/order/getUserInfo | POST | user:view |
| /admin/order/getAllUser | POST | user:view |
| /admin/order/getOneUserInfo | POST | user:view |
| /admin/order/addPoints | POST | user:points |

### 5.1 用户统计（按注册时间 t_user.time）

| 路径 | 方法 | 权限码 |
|------|------|--------|
| /admin/user/sevenDays | GET | user:view |
| /admin/user/lastMonth | GET | user:view |
| /admin/user/thisMonth | GET | user:view |
| /admin/user/scope | GET | user:view |
| /admin/user/scope | POST | user:view |

### 5.2 门店公告（连锁）

| 路径 | 方法 | 权限码 |
|------|------|--------|
| /admin/announcement/list | GET | announcement:manage |
| /admin/announcement/get | GET | announcement:manage |
| /admin/announcement/add | POST | announcement:manage |
| /admin/announcement/update | POST | announcement:manage |
| /admin/announcement/delete | GET | announcement:manage |

### 6. 菜品 / 分类 / 单位

| 路径 | 方法 | 权限码 |
|------|------|--------|
| /admin/category/list | GET | dish:manage |
| /admin/category/list | POST | dish:manage |
| /admin/category/listAll | GET | dish:manage |
| /admin/category/listAll | POST | dish:manage |
| /admin/category/add | POST | dish:manage |
| /admin/category/delete | GET | dish:manage |
| /admin/category/sort | POST | dish:manage |
| /admin/dish/list | GET | dish:manage |
| /admin/dish/list | POST | dish:manage |
| /admin/dish/save | POST | dish:manage |
| /admin/dish/delete | GET | dish:manage |
| /admin/dish/updateOnSale | POST | dish:manage |
| /admin/dish/sort | POST | dish:manage |
| /admin/dish/uploadImage | POST | dish:manage |
| /admin/unit/listAll | GET | dish:manage |
| /admin/unit/listAll | POST | dish:manage |
| /admin/unit/add | POST | dish:manage |

### 7. 桌台（admin）

| 路径 | 方法 | 权限码 |
|------|------|--------|
| /admin/table/list | GET | table:manage |
| /admin/table/list | POST | table:manage |
| /admin/table/add | POST | table:manage |
| /admin/table/delete | GET | table:manage |
| /admin/table/out | GET | table:manage |
| /admin/table/status | GET | table:manage |

### 8. 会员

| 路径 | 方法 | 权限码 |
|------|------|--------|
| /admin/member/recharge | POST | user:view |
| /admin/member/recharge/list | GET | user:view |
| /admin/member/consumption | GET | user:view |
| /admin/member/profile | GET | user:view |

### 9. 支付方式 / 商户 / 报表 / 日志 / 日结 / 物料 / 第三方

| 路径 | 方法 | 权限码 |
|------|------|--------|
| /admin/payment-method/list | GET | order:config |
| /admin/payment-method/save | POST | order:config |
| /admin/shop/list | GET | order:config |
| /admin/shop/save | POST | order:config |
| /admin/report/daily | GET | statistics:view |
| /admin/report/weekly | GET | statistics:view |
| /admin/report/monthly | GET | statistics:view |
| /admin/report/dishRanking | GET | statistics:view |
| /admin/report/cashierPerformance | GET | statistics:view |
| /admin/report/shopProfit | GET | statistics:view |
| /admin/report/compare | GET | statistics:view |
| /admin/report/inventory | GET | statistics:view |
| /admin/report/dashboard | GET | statistics:view |
| /admin/report/recharge/list | GET | statistics:view |
| /admin/log/operation | GET | log:view |
| /admin/daily/settle | POST | order:config |
| /admin/daily/summary | GET | order:config |
| /admin/daily/income | GET | order:config |
| /admin/daily/byChannel | GET | order:config |
| /admin/daily/grossProfit | GET | order:config |
| /admin/material/list | GET | admin:manage |
| /admin/material/save | POST | admin:manage |
| /admin/material/inbound | POST | admin:manage |
| /admin/material/outbound | POST | admin:manage |
| /admin/material/alert | GET | admin:manage |
| /admin/third/order/sync | POST | admin:manage |
| /admin/third/order/statusPush | POST | admin:manage |
| /admin/third/reconciliation | GET | admin:manage |

### 10. 收银端 /cashier

| 路径 | 方法 | 权限码 |
|------|------|--------|
| /cashier/order/quickOrder | POST | order:operate |
| /cashier/order/addDishes | POST | order:operate |
| /cashier/order/refundDish | POST | order:operate |
| /cashier/order/updatePrice | POST | order:operate |
| /cashier/order/discount | POST | order:operate |
| /cashier/order/checkout | POST | order:operate |
| /cashier/order/hang | POST | order:operate |
| /cashier/order/unCheckout | POST | order:operate |
| /cashier/order/today | GET | order:view |
| /cashier/order/search | GET | order:view |
| /cashier/table/open | POST | table:manage |
| /cashier/table/merge | POST | table:manage |
| /cashier/table/transfer | POST | table:manage |
| /cashier/table/clear | POST | table:manage |
| /cashier/table/statusMap | GET | table:manage |
| /cashier/print/kitchen | POST | order:operate |
| /cashier/shift/start | POST | order:config |
| /cashier/shift/handover | POST | order:config |
| /cashier/shift/current | GET | order:config |

### 11. KDS 厨房显示（/admin/kds）

运营配置步骤、页面字段对照与 curl 示例见 **`docs/kds_admin_setup_guide.md`**。

| 路径 | 方法 | 权限码 |
|------|------|--------|
| /admin/kds/station/list | GET | kds:config |
| /admin/kds/station/save | POST | kds:config |
| /admin/kds/station/delete | POST | kds:config |
| /admin/kds/station/init-five | POST | kds:config |
| /admin/kds/station/category/bind | POST | kds:config |
| /admin/kds/station/category/list | GET | kds:config |
| /admin/kds/dish-screen/bind | POST | kds:config |
| /admin/kds/dish-screen/list | GET | kds:config |
| /admin/kds/config/get | GET | kds:config |
| /admin/kds/config/save | POST | kds:config |
| /admin/kds/device/list | GET | kds:config |
| /admin/kds/device/bind | POST | kds:config |
| /admin/kds/device/unbind | POST | kds:config |
| /admin/kds/device/delete | POST/GET/DELETE | kds:config |
| /admin/kds/ticket/repush | POST | kds:config |
| /cashier/kds/delivery/lease | POST | cashier:operate |
| /cashier/kds/authority/lease | POST | cashier:operate |
| /cashier/kds/delivery/bootstrap | GET | cashier:operate |
| /cashier/kds/delivery/events | GET | cashier:operate |
| /cashier/kds/delivery/ack | POST | cashier:operate |
| /cashier/kds/delivery/status | GET | cashier:operate |
| /cashier/kds/orders/{orderId}/projection | GET | cashier:operate |

**收银端 KDS 投递流 `/cashier/kds/*` 与 `/admin/cashier/kds/*`**：校验 JWT 与 `X-Shop-Id`，权限码映射为 `cashier:operate`。
**厨显端 `/kds/*`**：使用 **`X-Kds-Device-Token`**（`KdsDeviceAuthInterceptor`），不录入本表。详见 `docs/openapi.yaml` 标签 **KDS-Client**、`docs/postman-kds.json`。

---

## 说明

- **path_pattern**：与请求路径完全一致或为前缀；拦截器按「路径长度降序」匹配，更长的模式优先（如先匹配 `/admin/order/delete_banners/` 再匹配 `/admin/order/`）。
- **未在数据库映射和代码内置映射中配置的 B 端接口**：返回 `403 接口权限未配置`，禁止默认放行。
- 如需某接口「仅登录即可访问」，必须加入后端精确的最小白名单；不得通过遗漏 `t_api_permission` 达成。

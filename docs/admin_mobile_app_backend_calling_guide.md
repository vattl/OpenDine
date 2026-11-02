# 运营 APP 后端接口调用说明

本文对应 `backend_coordination_app_mobile.md`，适用于 Flutter 运营 APP。完整字段定义以 `docs/openapi.yaml` 为准。

## 1. 上线前准备

1. 执行 `docs/db_migration_admin_mobile_app.sql`。
2. 重启后端，使数据库接口权限映射重新加载。
3. 确认店员、店长、收银角色已获得 `announcement:view`；负责桌台操作的角色已获得 `table:operate` 或 `cashier:operate`。
4. 在 `t_admin_app_version` 配置 Android、iOS 各渠道版本策略。

除版本查询和设备解绑外，本文接口均应携带：

```http
Authorization: Bearer <JWT>
X-Shop-Id: <当前门店ID>
Content-Type: application/json
```

APP 切换门店后必须更新 `X-Shop-Id`。后端仍会校验账号是否有权访问该门店。

## 2. 登录后的推荐初始化顺序

```text
登录成功
  -> 读取账号权限和可访问门店
  -> 选定当前门店
  -> 查询 APP 版本策略
  -> 获取系统推送 token
  -> 注册推送设备
  -> 拉取公告和业务数据
```

## 3. 公告只读接口

```http
GET /admin/announcement/list?status=1
GET /admin/announcement/get?id=123
```

查询接口接受 `announcement:view` 或 `announcement:manage`。新增、修改、删除仍要求 `announcement:manage`，APP 不应仅凭页面可见就展示编辑入口。

## 4. 推送设备

### 4.1 注册或刷新设备

```http
POST /admin/push/device/register

{
  "deviceToken": "vendor-device-token",
  "platform": "android",
  "channel": "huawei",
  "appVersion": "2.0.1+202",
  "deviceModel": "HUAWEI Pura 70"
}
```

`platform` 支持 `android`、`ios`。iOS 必须使用 `apns`；Android 支持 `fcm`、`huawei`、`xiaomi`、`oppo`、`vivo`。系统 token 刷新、账号切换或门店切换后应重新注册。同一 token 会自动归属到最后一次注册的账号和门店。

### 4.2 通知偏好

```http
POST /admin/push/preference

{
  "types": ["new_order", "refund", "table_call"]
}
```

类型名仅允许小写字母、数字和下划线，最多 32 项。提交空数组表示当前账号在当前门店关闭全部业务通知。

### 4.3 退出登录

```http
POST /admin/push/device/unregister

{
  "deviceToken": "vendor-device-token"
}
```

解绑只要求有效 JWT，不要求 `X-Shop-Id`。APP 应先解绑成功，再清除本地 JWT；若网络失败，可保留 token 并在下次登录后重新注册覆盖归属。

> 当前后端已完成设备、门店和通知偏好的持久化接口。APNs、FCM 及各 Android 厂商的实际消息投递仍需部署环境提供厂商账号、证书或密钥，并接入对应发送适配器；注册成功不等于厂商推送链路已经开通。

## 5. 订单写接口幂等

以下接口支持 `X-Client-Request-Id`：

```text
POST /cashier/order/quickOrder
POST /cashier/order/addDishes
POST /cashier/order/checkout
```

APP 每次新的业务动作生成一个不超过 128 字符的唯一键，例如 UUID：

```http
X-Client-Request-Id: 8d7b9c64-98a8-4cf9-a02b-b884d410d012
```

规则：

- 同一门店、同一键在 24 小时内返回首次成功响应，不会重复建单、加菜或结账；失败响应会释放该键，修正参数后可重试。
- 请求超时且结果未知时，重试必须沿用原键和原接口。
- 用户主动发起新动作时必须生成新键。
- 同一键跨三个接口复用会返回 `code=409`。
- 旧版本不传该请求头时，后端保持原有行为。

Flutter/Dio 可在业务层固定键，避免重试拦截器每次生成新值：

```dart
final requestId = const Uuid().v4();
final response = await dio.post(
  '/cashier/order/checkout',
  data: checkoutBody,
  options: Options(headers: {'X-Client-Request-Id': requestId}),
);
// 网络超时重试时继续使用 requestId。
```

## 6. 桌台操作权限

```text
POST /cashier/table/open
POST /cashier/table/merge
POST /cashier/table/transfer
POST /cashier/table/clear
```

四个接口接受 `cashier:operate` 或 `table:operate`。APP 可根据任一权限展示桌台操作入口，但仍须携带当前门店请求头。桌台接口原有 `Idempotency-Key` 规则不变，不要与订单接口的 `X-Client-Request-Id` 混用。

## 7. APP 版本策略

```http
GET /admin/app/version?platform=android&channel=mobile
Authorization: Bearer <JWT>
```

成功响应：

```json
{
  "code": 0,
  "data": {
    "latest": "2.0.1",
    "minSupported": "2.0.0",
    "forceUpdate": false,
    "releaseNotes": "稳定性优化",
    "downloadUrl": "https://example.com/app.apk"
  }
}
```

APP 使用语义化版本逐段比较，不要按字符串字典序比较。建议逻辑：

- 当前版本低于 `minSupported`：阻断使用并进入强制升级页。
- `forceUpdate=true` 且当前版本低于 `latest`：阻断使用并强制升级。
- 当前版本低于 `latest`，但不满足强制条件：展示可关闭的升级提示。
- `downloadUrl` 为空：只展示版本信息，不执行跳转。

## 8. 通用错误处理

- `code=401`：JWT 无效或已过期，回到登录页。
- `code=4001`：缺少门店上下文，重新选择门店并补发 `X-Shop-Id`。
- `code=4003`：账号无权访问该门店，刷新账号门店列表。
- `code=409`：业务冲突或幂等键误用，直接展示服务端 `msg`，不要无条件换键重试。
- HTTP 超时但没有业务响应：保留本次订单请求键并重试原请求。

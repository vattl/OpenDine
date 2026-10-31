# 权限模块安全修复进度

更新时间：2026-08-23

## 总体状态

- 当前阶段：权限专项审计所列修复已全部完成并通过交付复核
- 工作分支：`codex/permission-hardening-phase1`
- 原则：失败关闭、显式授权、服务端身份、数据库范围二次校验

## 进度

- [x] 完成权限模块七层完整性专项审计
- [x] 修复“无角色即超级管理员”
- [x] 修复权限查询异常时授予全部权限
- [x] 修复 KDS 设备匿名注册/绑定
- [x] 修复后台接口权限映射缺失默认放行
- [x] 修复 C 端直接信任 `openid`
- [x] 收紧匿名白名单中的管理写接口
- [x] 修复跨店 `shopId`、`allShops` 和全局配置绕过
- [x] 实现管理员 token 撤销与密钥轮换
- [x] 补齐权限变更与越权访问审计日志

## 第一阶段验证记录

| 批次 | 内容 | 测试 | 状态 |
|---|---|---|---|
| 1 | RBAC 和总部范围 fail-open | `mvn "-Dtest=AdminPermissionServiceImplSecurityTest,AdminShopAccessServiceImplSecurityTest" test`（4/4 通过） | 已完成 |
| 2 | KDS 设备注册与心跳保护 | `mvn "-Dtest=AdminPermissionServiceImplSecurityTest,AdminShopAccessServiceImplSecurityTest,KdsDeviceControllerSecurityTest,KdsDeviceAuthInterceptorSecurityTest" test`（9/9 通过） | 已完成 |
| 3 | 后台权限映射失败关闭、路由补齐、数据库通配契约 | 权限、KDS 与复制契约定向回归（41/41 通过） | 已完成 |
| 4 | JWT 运行时密钥、双密钥轮换、管理员会话版本撤销、本人密码修改约束 | `JwtTokenServiceTest`、`AdminControllerSecurityTest`、`SysInterceptorPermissionMappingSecurityTest`（10/10 通过） | 已完成 |
| 5 | C 端用户 Token、openid 全层级一致性校验、排队/车牌/支付查询资源归属 | `UserIdentityInterceptorSecurityTest`、`OrderUserLoginSecurityTest`（6/6 通过） | 已完成 |
| 6 | 公开前缀中的历史管理接口重新绑定管理员 JWT 与权限码 | `SysInterceptorPermissionMappingSecurityTest`、`UserIdentityInterceptorSecurityTest`（11/11 通过） | 已完成 |
| 7 | 门店参数、`allShops`、全局配置、收银上下文和 C 端订单归属二次校验 | 门店范围、拦截器、收银与订单安全定向回归（40/40 通过） | 已完成 |
| 8 | 认证/越权拒绝与权限配置变更持久化审计、总部/门店日志查询隔离 | 安全审计、拦截器、C 端、KDS 与数据范围定向回归（30/30 通过） | 已完成 |
| 9 | 全量自动化回归 | `mvn test`（356 项：355 通过，0 失败，1 项需显式启用的独立 debug 库烟测） | 已完成 |
| 10 | 支付/外卖身份最终复核：支付预下单、余额支付、会员充值和外卖创单只信任 `X-User-Token`，订单归属二次校验；桌台详情移出匿名白名单；审计 IP 不信任客户端转发头 | 定向回归 9/9 通过；最终 `mvn test`（359 项：358 通过，0 失败，1 项需显式启用的独立 debug 库烟测） | 已完成 |

## 交付产物

- JAR：`target/diancan-0.0.1-SNAPSHOT.jar`
- 构建：`mvn package -DskipTests`，成功
- 大小：71,667,896 bytes
- SHA-256：`707781E90BCC1EF5EC1007BCFEA12B6168096A7BA03C7A580E55778764ABEB9A`

## 风险与兼容性说明

- 修复“无角色即超管”后，历史上未绑定角色的管理员会失去后台权限；部署前必须查询并显式绑定角色。
- KDS 注册保护上线后，必须通过环境变量 `KDS_DEVICE_PAIRING_SECRET` 配置配对密钥，并在设备登录请求头传 `X-Kds-Pairing-Secret`；未配置时默认拒绝绑定。
- 已绑定设备的现有 token 不受影响；心跳请求现在必须携带 `X-Kds-Device-Token`，且服务端忽略请求体中的设备身份，以 token 绑定设备为准。
- 新增 `/admin/**`、`/cashier/**` 或 `/api/admin/cashier/**` 接口时必须同步登记权限；未登记接口现在返回 `code=403`、`msg=接口权限未配置`，并记录 traceId、adminId、路径和方法。
- 仅 `/admin/me/permissions`、`/admin/me/shops`、`/admin/app/version` 与管理员本人推送设备/偏好接口允许“仅登录”访问，名单采用精确匹配。
- 部署批次 4 前先执行 `docs/db_migration_admin_token_version.sql`，并设置不少于 32 字节的 `AUTH_JWT_CURRENT_SECRET`；密钥轮换时把旧值暂存于 `AUTH_JWT_PREVIOUS_SECRET`，超过最长 Token 生命周期后清空。旧硬编码密钥签发的 Token 将失效，需要重新登录。
- 修改密码接口现在要求请求体同时提供当前密码 `password` 与新密码 `newPassword`，用户名参数不再决定修改目标；成功后当前管理员全部旧 Token 立即失效。
- 小程序必须保存 `/order/getOpenid` 返回的 `user_token`，并在用户私有数据及写请求中传 `X-User-Token`；仅继续传 `openid` 的旧客户端将收到 401，必须与本批次同步升级。
- `/order/getPrepayId`、`/order/payByBalance`、`/order/recharge`、`/order/takeout/create` 不再接受 `code`/`wxCode` 在业务接口内换身份；Token 过期后先调用 `/order/getOpenid` 重新换取 `X-User-Token`。请求体 `openid` 仅为兼容字段，必须与 Token 一致且不会覆盖服务端身份。
- 历史 `/order/ChangeBusiness`、`ChangeIsReview`、`changeWxzf`、`notice`、`printContent`、`autoAcceptAndPrint`、`delete/{id}` 以及 `/activity` 的新增/修改/删除弹窗接口不再匿名；兼容路径保留，但强制管理员 JWT 与对应 `order:*` / `banner:manage` 权限。
- 非总部管理员只能查询、修改其已授权门店；请求头、查询参数及 JSON 中的 `shopId`/`shop_id`、`shopCode`/`shop_code` 不一致时直接拒绝。`allShops=true` 和 `shop_id=0` 全局配置仅总部账号可用。
- 收银开单、交班和桌台查询只使用拦截器解析后的门店上下文；C 端按桌/订单号查询、加菜及 AI 工具查询均再次校验订单 `openid` 归属。
- 安全审计统一写入 `t_operation_log`（`module=security`），记录管理员 ID、方法、路径、权限码、门店、结果码与 traceId；不落密码、token、openid。门店管理员只可查授权门店日志，总部可查全局日志或通过 `allShops=true` 查全部。
- 非总部管理员必须显式绑定门店或区域；即使系统只有一家营业门店，也不再自动继承访问权。
- `KdsLocalSmokeTest` 现在仅在显式设置 `RUN_LOCAL_KDS_SMOKE=true` 时运行，并强制使用 `debug` profile，防止常规测试误连、误写生产数据库。

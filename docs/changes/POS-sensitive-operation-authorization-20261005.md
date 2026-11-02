# POS 敏感业务操作员工二次授权

## Objective

为收银端打折、订单退款、退菜、赠送/改价和强制删除订单建立统一的服务端二次授权边界。每次操作必须提交员工账号（用户名或工号）与密码；服务端在执行同一业务请求前校验密码、细粒度权限和门店范围。订单删除入口仅对当前登录的 `super_admin` 显示，后端继续强制当前会话为 `super_admin`，并要求二次授权员工同样为 `super_admin`。

## Assumptions Requiring Approval

1. 二次授权员工可以与当前登录收银员不同，用于店长/主管现场授权。
2. 每次敏感操作均重新输入账号与密码；不缓存密码，不复用授权，不签发可重放的长期令牌。
3. 权限映射沿用现有权威权限码：
   - 打折：`order:operate:discount`
   - 退款、退菜：`order:operate:refund`
   - 赠送菜品/改价：`order:operate:changePrice`
   - 删除订单：`order:delete` + 二次授权员工为 `super_admin`
4. 本次“删除”指账单/订单强制删除；普通菜品明细删除不新增入口。

## Product and Security Context

- Primary user goal: 收银员发起敏感操作，由有权限员工现场授权后完成。
- Assets: 订单金额、退款资金、库存、审计身份、订单历史。
- Trust boundary: Flutter 表单输入通过 HTTPS 进入服务端；客户端权限和显示状态不作为安全边界。
- Abuse cases:
  - 直接调用接口绕过密码弹窗。
  - 普通员工账号为高权限操作授权。
  - 跨门店员工为当前门店操作授权。
  - 非超级管理员通过隐藏入口或直接请求删除订单。
  - 密码进入调试日志、本地存储或审计详情。

## Authoritative Owners

- 角色与超级管理员判定：`IAdminShopAccessService.isSuperAdmin`。
- 权限集合：`IAdminPermissionService.getPermissionCodesByAdminId`。
- 密码校验：`AdminPasswordUtil.matches`。
- 门店范围：`IAdminShopAccessService.listAccessibleShopIds`。
- 敏感业务执行：各订单 Controller 的服务端事务入口。

## Contract Delta

### Additive response change

`GET /admin/me/permissions` 响应 `data` 新增：

```json
{
  "isSuperAdmin": true
}
```

旧客户端可忽略该字段；新客户端缺失时失败关闭为 `false`。

### Breaking request validation change

下列敏感请求必须新增 `authorization` 对象：

```json
{
  "authorization": {
    "account": "EMP1001",
    "password": "user-entered-secret"
  }
}
```

涉及接口：

- `POST /cashier/order/discount`
- `POST /cashier/order/refund`
- `POST /cashier/order/refundDish`
- `POST /cashier/order/updatePrice`
- `POST /admin/order/refund`
- `DELETE /order/delete/{id}`

缺失/密码错误返回认证失败；密码正确但权限、门店或超级管理员条件不满足返回拒绝。密码不得进入响应、日志或持久化。

## Affected Surface Map

- Server authorization service: CHANGE
- Server current-user permissions response: CHANGE
- Server sensitive order controllers: CHANGE
- Server OpenAPI and API guide: CHANGE
- Flutter auth session/state mapping: CHANGE
- Flutter shared authorization dialog/model: CHANGE
- Flutter POS discount/refund/gift flows: CHANGE
- Flutter bill refund/delete flows and delete visibility: CHANGE
- Flutter repositories/request contracts: CHANGE
- Existing order calculation, persistence schema and response DTOs: VERIFY_NO_CHANGE
- KDS display/transport: VERIFY_NO_CHANGE (only existing refund/price events continue downstream)

## Layer Impact Matrix

| Layer | Classification | Evidence / change |
| --- | --- | --- |
| UI | CHANGE | Shared employee account/password dialog; delete entrance gated by `isSuperAdmin` |
| Interaction | CHANGE | Authorization occurs after business details/confirmation and before submission |
| Frontend State | CHANGE | Session gains fail-closed `isSuperAdmin` |
| API Client | CHANGE | Repositories include nested authorization body |
| Request Contract | CHANGE | Sensitive endpoints require `authorization` |
| Controller | CHANGE | Calls shared authorization service before mutation |
| Service | CHANGE | Shared password + permission + shop + role validator |
| Domain | VERIFY_NO_CHANGE | Order/refund/discount semantics unchanged |
| Persistence | VERIFY_NO_CHANGE | No schema change; credentials never stored |
| Response Contract | CHANGE | `/admin/me/permissions` adds `isSuperAdmin` |
| Frontend Mapping | CHANGE | Parse boolean with false default |
| UI Display | CHANGE | Non-super-admin sees no delete entry |

## Implementation Tasks

1. Server authorization foundation and unit tests.
2. Protect cashier discount/refund/refundDish/updatePrice and admin refund/delete endpoints.
3. Add `isSuperAdmin` to permissions response and synchronize OpenAPI/API docs.
4. Add Flutter authorization value object/dialog and repository contract fields.
5. Gate all bill delete entries and wire bill refund/delete authorization.
6. Wire POS discount/refund/gift/refundDish authorization.
7. Run server focused/full tests, package JAR, Flutter focused/full tests and analyzer.

## Success Criteria

- Direct sensitive requests without authorization fail before mutation.
- Wrong password, missing permission, wrong shop or insufficient role all fail closed.
- Authorized employee succeeds and is available to audit code as the actual approving operator.
- Non-super-admin sessions render no bill delete entry; direct delete requests still fail server-side.
- Password is absent from logs, local storage, audit snapshots and error messages.
- OpenAPI and `docs/API.md` match implementation.

## Commands

- Server focused tests: `.\mvnw.cmd -Dtest=<test classes> test`
- Server full tests: `.\mvnw.cmd test`
- Server package: `.\mvnw.cmd clean package -DskipTests`
- Flutter focused tests: `flutter test test/cashier_bill_test.dart test/pos_page_test.dart test/model_contract_test.dart`
- Flutter analysis: `flutter analyze`

## Boundaries

- Always: backend authorization is authoritative; fail closed; redact password.
- Ask first: changing the four assumptions above or adding database schema.
- Never: authorize only in Flutter, cache plaintext credentials, or infer super-admin from permission breadth.

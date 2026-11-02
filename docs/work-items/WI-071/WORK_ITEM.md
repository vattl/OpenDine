# WORK ITEM — WI-071

## Request

会员注册统一默认昵称老肥吃货➕id号，可以修改昵称，只有注册的时候首次填入默认昵称，后续通过修改接口更新昵称。

## Type

FEATURE / DATA_MODEL / USER_PROFILE

## State

ACCEPTED

## Requirement Contract

### Goal

1. 会员注册（新用户写入 `t_user` 表）时，未指定昵称的情况下统一填入默认昵称：`老肥吃货` + 自增用户ID（例如 ID 为 10086 则昵称为 `老肥吃货10086`）；
2. 仅在注册插入用户时首次填入该默认昵称；
3. 后续任何用户登录、会话更新、手机号绑定或下单等操作不得篡改或重置已有的昵称；
4. 用户可在后续通过用户信息修改接口（`POST /order/updateUser`、`POST /order/updateAvatar`）主动修改自定义昵称。

### Current behavior

1. 新用户通过微信授权/登录注册写入 `t_user` 时，`name` 字段为 `null`；
2. 小程序展示未命名的空白或回退占位符；
3. `CustomerProfileService.updateAvatar` 接收 `nickname` 参数但未更新至实体，导致通过头像接口附带修改昵称失效；
4. 缺乏统一的注册首次昵称赋初值与防覆盖守卫机制。

### Target behavior

1. `IUserService.save(User entity)`：重写持久化逻辑，新用户落库获得 `id` 后，若 `name` 为空，自动设为 `老肥吃货` + `id`；
2. `IUserService.bindPhoneToOpenid`：新用户落库走 `save` 统一赋予默认昵称，老用户绑定手机仅更新手机号与会话，严禁覆盖现有昵称；
3. `WechatMiniProgramAuthServiceImpl.upsertUser`：新用户注册获得默认昵称，老用户后续登录只更新 session_key 和用户类型，不覆盖昵称；
4. `CustomerProfileService.updateUser` / `updateAvatar` / `getUserInfo`：支持双向兼容 `name` 与 `nickname` 字段读写，允许用户修改昵称；
5. 编写自动化测试覆盖：首次注册默认昵称、多次登录昵称不被重置、手机号绑定不覆盖昵称、接口自定义修改昵称等核心场景。

### Acceptance criteria

- [x] 新用户注册落库时，默认昵称自动生成为 `老肥吃货{id}`。
- [x] 注册时若已显式指定昵称，则保留显式昵称，不强制覆盖。
- [x] 老用户再次登录或刷新 session_key 时，昵称保持原样，不被重置为默认昵称。
- [x] 用户绑定手机号（`bindPhoneToOpenid` / `getOfficialPhoneNumber`）时，已有昵称不被篡改。
- [x] 调用 `/order/updateUser` 与 `/order/updateAvatar` 可以成功修改昵称。
- [x] 调用 `/order/getUserInfo` 正确返回最新昵称（`name` 与 `nickname` 均保持一致）。
- [x] 自动化测试全部通过，无回归问题。
- [x] `docs/API.md` 与 `docs/openapi.yaml` 同步更新。
- [x] 执行 `mvn clean package -DskipTests` 打包成功生成可运行 JAR。

## Impact Summary

见 `IMPACT_MAP.md`。

## Design Summary

见 `IMPLEMENTATION_DESIGN.md`。

## Tasks / Vertical Slices

- [x] T01 `User.java` 实体支持 `nickname` 与 `name` 双向兼容。
- [x] T02 `IUserService` & `IUserServiceImpl` 实现首次注册默认昵称赋值与防覆盖。
- [x] T03 `CustomerProfileService` 完善用户信息与头像昵称修改。
- [x] T04 `OrderController` 确保手机号验证与用户信息端点合规。
- [x] T05 编写全套自动化单元与集成测试。
- [x] T06 API 契约与 OpenAPI 同步，Maven 打包验证。

## Acceptance Decision

ACCEPTED

## Business Invariants

- 默认昵称生成规则严格为 `老肥吃货` + 用户ID；
- 只有注册时首次赋初值，后续业务流程（登录、点餐、领券、绑定手机等）绝不可重置或覆盖用户昵称；
- 仅允许通过用户个人资料修改接口更新昵称。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-071/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-071/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: YES
- Blockers: none

## Completion Level

ACCEPTED

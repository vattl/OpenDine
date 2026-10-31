# Acceptance Report — WI-071

Decision: ACCEPTED

## 1. 验收结论
- **状态**: ACCEPTED
- **决议**: 经过服务层重写持久化赋值逻辑、资料服务双向兼容增强、防重置与防覆盖校验、专项单元测试全套通过以及 API 文档同步，WI-071 符合全部验收准则。

## 2. 验收清单核对

| 准则项 | 状态 | 验证说明 |
|---|---|---|
| 新用户注册自动赋予 `老肥吃货{id}` 默认昵称 | PASS | `IUserServiceImpl.save` 在 MyBatis-Plus 获取到自增 ID 后自动赋初值 |
| 显式传入昵称注册不被覆盖 | PASS | `!StringUtils.hasText(entity.getName())` 守卫，存在显式昵称时跳过 |
| 老用户再次登录或刷新 session 不重置昵称 | PASS | `upsertUser` 仅更新 `session_key` 与 `user_type`，不触碰昵称 |
| 手机号绑定不覆盖已有昵称 | PASS | `bindPhoneToOpenid` 仅更新手机号，保留原昵称 |
| 支持通过 `/order/updateUser` 修改昵称 | PASS | 兼容解析 `nickname` 与 `name` 参数并安全持久化 |
| 支持通过 `/order/updateAvatar` 修改昵称 | PASS | 解析可选 `nickname` 参数并保存 |
| `/order/getUserInfo` 返回最新昵称 | PASS | 响应体显式补充 `nickname`，与 `name` 严格一致 |
| 自动化测试全部通过 | PASS | 17 个专项与关联回归测试全部通过 |
| API 文档同步更新 | PASS | `docs/API.md` 与 `docs/openapi.yaml` 均已更新 |
| Maven 打包产出可执行 JAR | PASS | `mvn clean package -DskipTests` 生成 `target/diancan-0.0.1-SNAPSHOT.jar` |

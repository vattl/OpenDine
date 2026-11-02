# Impact Map — WI-071

## Authoritative Owner

`IUserService` / `IUserServiceImpl` (用户领域服务与生命周期管理)。

## Layer Coverage

| 层级 | 路径 / 文件 | 影响类型 | 说明 |
|---|---|---|---|
| 实体模型 | `src/main/java/com/lanf/entity/User.java` | MODIFY | 扩展非持久化字段 `nickname`，添加与 `name` 双向绑定的 getter/setter |
| 服务接口 | `src/main/java/com/lanf/service/IUserService.java` | MODIFY | 声明默认昵称构造与新用户默认值辅助方法 |
| 服务实现 | `src/main/java/com/lanf/service/impl/IUserServiceImpl.java` | MODIFY | 重写 `save(User)` 首次注册赋予 `老肥吃货{id}` 默认昵称；`bindPhoneToOpenid` 防覆盖 |
| 认证实现 | `src/main/java/com/lanf/service/impl/WechatMiniProgramAuthServiceImpl.java` | REVIEW / VERIFY | 确认 `upsertUser` 在新注册时赋予默认昵称，老用户后续登录不触碰昵称 |
| 资料服务 | `src/main/java/com/lanf/service/CustomerProfileService.java` | MODIFY | `updateUser` 兼容 `nickname`/`name`，`updateAvatar` 补充昵称更新，`getUserInfo` 返回 `nickname` |
| 控制层 | `src/main/java/com/lanf/controller/OrderController.java` | VERIFY | 确认 `/getOfficialPhoneNumber` 绑定手机时不覆盖昵称 |
| 契约文档 | `docs/API.md`<br>`docs/openapi.yaml` | MODIFY | 更新用户信息获取与修改接口说明，注明默认昵称规则 |
| 单元测试 | `src/test/java/com/lanf/user/UserRegistrationNicknameTest.java` | CREATE | 增加注册默认昵称生成、老用户防覆盖、接口修改昵称的专项测试 |

## 外部依赖与兼容性
- 数据库表 `t_user.name` 保持原有数据结构，无需修改 DDL。
- 对现有会员数据完全向前兼容，历史已有自定义昵称不受任何影响。

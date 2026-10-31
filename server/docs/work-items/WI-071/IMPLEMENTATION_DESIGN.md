# Implementation Design — WI-071

## Root Fix / Owner

核心收敛于 `IUserServiceImpl` 用户服务。所有新用户注册持久化均由 `IUserServiceImpl.save` 收口；在用户获得自增主键 `id` 后，若 `name` 字段为空，自动生成并持久化默认昵称 `老肥吃货` + `id`。

## 架构与设计原则

### 核心原则
1. **单一入口初始化**：所有通过持久层保存新用户的路径统一由 `IUserServiceImpl.save(User entity)` 收口。在 MyBatis-Plus 执行 insert 生成主键 ID 之后，若用户的 `name` 为空，自动生成并保存 `"老肥吃货" + entity.getId()`；
2. **防覆盖不变量**：
   - 微信 `jscode2session` 登录刷新 `session_key` 时，若用户已存在，仅更新 `session_key` 与 `user_type`，绝不改写 `name`；
   - 手机号绑定（`bindPhoneToOpenid` / `getOfficialPhoneNumber`）时，仅更新 `phone`，绝不改写 `name`；
   - 外部调用 `updateUser` 或 `updateAvatar` 时，必须显式传递非空昵称才更新，否则保持不变；
3. **接口双向兼容**：前端可能在请求与响应中使用 `name` 或 `nickname`。`User.java` 同时提供 `nickname` 的 getter/setter 与 `@TableField(exist = false)`，保证序列化与反序列化双向透明。

## 关键代码设计

### 1. 默认昵称构建器
```java
public static String buildDefaultNickname(Integer id) {
    return "老肥吃货" + (id != null ? id : "");
}
```

### 2. `IUserServiceImpl.save` 重写
```java
@Override
@Transactional(rollbackFor = Exception.class)
public boolean save(User entity) {
    if (entity == null) return false;
    ensureUserDefaults(entity);
    boolean success = super.save(entity);
    if (success && entity.getId() != null) {
        if (!StringUtils.hasText(entity.getName())) {
            entity.setName(buildDefaultNickname(entity.getId()));
            baseMapper.updateById(entity);
        }
    }
    return success;
}
```

### 3. `CustomerProfileService` 增强
- `updateUser(User userInfo)`：检查 `userInfo.getNickname()` 与 `userInfo.getName()`，优先提取有效修改值；
- `updateAvatar(...)`：若入参 `nickname` 非空，同步更新 `user.setName(nickname.trim())`；
- `getUserInfo(...)`：显式补充 `result.put("nickname", user.getName())`，保障前端无论读取 `name` 还是 `nickname` 均能获取统一内容。

## Verification Strategy

1. **注册测试**：验证新用户注册（无初始昵称）落库后自动赋初值为 `老肥吃货{id}`；
2. **防覆盖测试**：老用户二次登录或绑定手机号，自定义昵称保持不变；
3. **修改接口测试**：验证 `POST /order/updateUser` 与 `POST /order/updateAvatar` 正确修改并持久化新昵称；
4. **获取接口测试**：验证 `POST /order/getUserInfo` 返回数据包含正确 `nickname` 与 `name`。

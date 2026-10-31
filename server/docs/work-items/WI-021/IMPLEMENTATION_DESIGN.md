# Implementation Design — WI-021

## Root Fix / Owner

在 `WechatNativePaymentAttemptEntity.active_key` 上声明 MyBatis-Plus `updateStrategy = FieldStrategy.IGNORED`，使 `updateById` 对该字段无论是否为 null 都生成赋值，从根因上覆盖关单、主动查单、成功通知和明确拒绝等所有终态路径。

不在每个服务分支手写 SQL，也不删除历史 attempt；唯一键仍只约束非 NULL 活动值。

## Compatibility

- 数据库列已可空，无迁移。
- API 请求、响应、错误码与权限不变。
- ACTIVE/CREATING/UNKNOWN 写入非空 active_key 的行为不变。

## Verification Strategy

1. 先增加失败测试，检查 ORM 字段元数据允许 null 更新。
2. 验证关单路径设置 CLOSED 并清空实体 active_key。
3. 运行 Native 专项测试与全量测试。
4. 同步 API 修复记录，生成 runnable JAR。

# Acceptance Report — WI-020

Decision: ACCEPTED

## Business outcome

商户模块已具备安全新增、编辑、退役、恢复与多门店隔离能力；订单可按服务端规则匹配任意商户键，并在创建交易时锁定商户配置 ID/版本。配置轮换或退役后，查单、关单、撤销、通知及退款仍能使用原交易凭据。

## Acceptance evidence

- 8 项验收标准全部完成。
- 11 个场景全部 PASS。
- 安全、测试、独立第二遍审查均 PASS。
- API 文档和数据库迁移同步完成。
- 全量 1296 项测试通过，runnable JAR 构建成功。

## State boundary

本决策表示仓库交付已 ACCEPTED；尚未执行生产迁移、部署与真实微信联调，因此不表示 INTEGRATED、DEPLOYED 或 RELEASED。

# Completion Evidence — WI-016

## Status

ACCEPTED. 仓库内付款码支付二期已实现并验证；未部署，也未用真实商户做资金扣款。

## Required evidence

- 迁移：`V023__wechat_micropay.sql`；启动探针覆盖配置列与尝试表。
- API：付款、查询、撤销三个 `cashier:operate` 端点。
- 安全：HMAC-SHA256、响应商户/AppID/商户单号校验、XXE 防护、付款码无持久化且调试日志不输出正文。
- 回归：全量 1271 tests，0 failures/errors，5 skipped；新增撤销专项 4 tests PASS。
- 契约：OpenAPI YAML 解析通过，`docs/API.md` 和消费者 handoff 已同步。
- 构建：`target/diancan-0.0.1-SNAPSHOT.jar`，73,979,613 bytes。

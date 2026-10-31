# Completion Evidence — WI-020

## Current State

ACCEPTED

## Requirement

支付商户管理达到安全生命周期、严格门店隔离、通用路由与交易配置版本绑定要求。

## Changed files

- 商户配置生命周期、历史版本、门店继承策略和通用路由服务。
- Native/MICROPAY/JSAPI 交易绑定与查单、关单、撤销、通知、退款消费者。
- `V027__payment_merchant_commercialization.sql` 数据迁移（集成时因版本占用由 V024 顺延）。
- 管理 API、权限清单、`docs/openapi.yaml` 与 `docs/API.md`。
- 相关单元测试及本 Work Item 验收材料。

## Capability owner

支付配置模块与微信支付渠道。

## Consumer coverage

Known consumers: JSAPI、Native、MICROPAY、支付通知、查单、关单、撤销、退款、管理端商户配置 API
Reviewed: YES
Affected: JSAPI、Native、MICROPAY、支付通知、查单、关单、撤销、退款、管理端商户配置 API
Unknown: NONE

## Cross-layer coverage

Layer Impact Matrix: `LAYER_IMPACT_MATRIX.md`
Contract Delta: `CONTRACT_DELTA.md`
Semantic UI Impact: NONE
End-to-end flow: PASS（创建时绑定配置 ID/版本，后续支付动作按绑定版本解析）

## Tests

- 专项测试：24 项，0 failure，0 error，0 skipped。
- 全量测试：1296 项，0 failure，0 error，5 skipped。
- OpenAPI YAML 解析：PASS，版本 `1.2.295`，478 paths。

## Runtime/manual verification

- `mvnw.cmd clean package -DskipTests`：BUILD SUCCESS。
- runnable JAR：`target/diancan-0.0.1-SNAPSHOT.jar`。
- 未调用真实微信生产接口；上线后仍需用测试订单做证书/回调联调。

## Fake/mock/hardcode review

- 未引入生产假成功或硬编码商户；支付成功仍以微信确认结果为准。
- `plain:` 仅在 debug profile 显式允许；生产无主密钥时写入 fail closed。
- SQL 示例已改为禁用模板，不包含可直接使用的商户密钥。

## Git evidence

- `git diff --check`：PASS（仅工作区 LF/CRLF 提示，无 whitespace error）。
- 工作位于独立 managed worktree，未覆盖主工作区的用户改动。

## Unverified items

生产数据库尚未执行 V024，服务尚未部署，未做真实微信商户联调；这些属于 RELEASE 阶段，不影响仓库级 ACCEPTED。

## Decision

VERIFIED_DONE

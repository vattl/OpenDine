# WORK ITEM — WI-020

## Request

依据商户模块审计结果，修复并完善支付商户管理，使商户生命周期、门店隔离、订单路由、密钥安全和历史交易凭据绑定达到可商业化上线的后端标准。

## Type

REPAIR

## State

ACCEPTED

## Requirement Contract

### Goal

支付商户配置可安全新增、编辑、退役和恢复；门店默认严格使用本店商户；订单可按规则选择任意 `merchantKey`；创建支付时绑定配置 ID/版本，后续回调、查单、关单、撤销和退款使用同一凭据版本。

### Assumptions

- 保留现有 API 路径和 `merchantId=1/2` 兼容，其中 `1 -> default`、`2 -> small_amount`。
- `DELETE /admin/payment/merchants/{id}` 的安全语义改为“退役”，不销毁历史凭据；新增显式恢复动作。
- 全局商户仅是可选模板，门店默认不继承；只有门店策略明确开启时才可回退 `shop_id=0`。
- 不修改前端仓库；所有新增响应字段向后兼容，并提供消费者 handoff。

### Must preserve

- 未确认支付不得标记成功；不确定交易不得因配置变更重复收款。
- 门店管理员不能读取或写入其他门店私有商户；总部模板只能由总部管理。
- API、日志和 Git 不得暴露 APIv2/APIv3 密钥或商户私钥。
- 订单金额仍由服务端计算；客户端不能直接指定支付金额或越权指定其他门店商户。

### Acceptance criteria

- [x] 新建密钥在未配置主密钥时 fail closed；仓库示例不含疑似真实密钥。
- [x] 商户删除改为退役，凭据与历史版本保留；在途支付仍可按绑定版本查单/回调/退款。
- [x] 支持恢复退役商户，所有写操作刷新缓存并记录版本。
- [x] 门店默认严格隔离；全局回退必须由该门店策略显式开启。
- [x] 任意合法 `merchantKey` 可被解析，旧 `1/2` 继续兼容。
- [x] `routingRuleJson` 有确定、可测试的金额/就餐方式路由语义。
- [x] Native、MICROPAY、JSAPI 创建与后续操作绑定同一商户配置 ID/版本。
- [x] API/OpenAPI/迁移、专项测试、全量测试与 runnable JAR 完成。

## Business Invariants

- INV-MERCHANT-001：支付只能使用订单所属门店的有效商户，除非该门店明确开启全局继承。
- INV-MERCHANT-002：交易创建后，商户配置变更不得改变该交易的凭据身份。
- INV-MERCHANT-003：商户退役不删除历史支付、查单、退款和对账所需凭据。
- INV-MERCHANT-004：生产密钥不得明文新增或出现在 API、日志、示例和 Git diff 中。
- INV-MERCHANT-005：路由结果必须由服务端订单属性与门店策略决定，客户端不能跨店覆盖。

## Acceptance Decision

ACCEPTED

仓库实现、自动化验证、API 文档与 runnable JAR 均完成；尚未部署生产，因此状态不提升为 RELEASED。

## Implementation Ready

- Status: `YES`
- Blockers: NONE

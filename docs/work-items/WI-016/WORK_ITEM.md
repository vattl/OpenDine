# WORK ITEM — WI-016

## Request

完成收银微信支付第二期：收银员扫描顾客微信付款码，款项直接进入门店已配置的微信支付商户。

## Type

FEATURE

## State

ACCEPTED

## Requirement Contract

### Goal

提供微信付款码支付（MICROPAY）的下单、权威查单与安全撤销闭环，并复用一期的幂等订单入账、支付台账和履约副作用。

### Target behavior

1. `POST /cashier/payment/wechat/micropay/orders` 接收订单号、一次性付款码和可选终端号；金额、商户和门店均由服务端确定。
2. `GET /cashier/payment/wechat/micropay/orders/{orderNo}` 通过微信 V2 查单收敛 `USERPAYING` 或网络未知结果，成功时幂等入账。
3. `POST /cashier/payment/wechat/micropay/orders/{orderNo}/reverse` 在查询确认未成功后撤销不确定交易。
4. APIv2 密钥加密保存，客户端证书仅保存服务器文件引用；付款码不落库、不写日志。

### Must preserve

- 仅微信签名校验通过的 `SUCCESS` 可确认支付。
- 同一订单最多一个活动付款码支付尝试，同一商户单号稳定重试，避免重复扣款。
- 所有订单、尝试和商户配置均按当前 JWT 门店隔离。
- 既有 Native、JSAPI、退款、对账、KDS、打印和台账语义保持不变。
- 网络超时和 `USERPAYING/SYSTEMERROR/BANKERROR` 均不是支付失败，更不是支付成功。

### Acceptance criteria

- [x] 付款码格式和服务端金额校验有效，付款码不会持久化或出现在响应/日志。
- [x] 微信 V2 请求使用 HMAC-SHA256，所有响应在信任业务字段前验证签名。
- [x] `SUCCESS` 复用共享幂等入账；`USERPAYING` 和未知状态可查单收敛。
- [x] 撤销前先查单，支付成功不得撤销；撤销使用客户端证书。
- [x] 商户配置支持 APIv2 密钥和 P12 证书引用，敏感值脱敏。
- [x] 权限、迁移、OpenAPI、API 文档和消费者 handoff 完整。
- [x] 专项测试、回归测试和完整 JAR 打包通过。

## Tasks / Vertical Slices

- [x] T01 商户 V2 凭据与付款尝试持久化。
- [x] T02 V2 XML 签名、验签和安全解析客户端。
- [x] T03 付款、查单、撤销编排与共享入账。
- [x] T04 API、权限、契约和消费者 handoff。
- [x] T05 安全、回归、打包和验收。

## Acceptance Decision

ACCEPTED（仓库内；未部署、未做真实商户扣款）

## Verification Evidence

- 全量测试：1271 run，0 failures，0 errors，5 skipped。
- 新增撤销场景专项补跑：4 run，0 failures/errors。
- OpenAPI YAML 解析、`git diff --check`、密钥材料扫描通过。
- `mvnw.cmd clean package -DskipTests` 成功生成 runnable JAR。

## Business Invariants

- INV-PAY-001：未经微信权威确认不得标记支付成功。
- INV-PAY-002：金额、门店、商户和订单归属由服务端控制。
- INV-PAY-003：支付成功应用与业务副作用幂等。

## Implementation Ready

- Status: `YES`
- Blockers: NONE

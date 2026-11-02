# Review Report — WI-016

## Decision

PASS

## Five-axis review

- Correctness: 修复了门店限定、稳定商户单号、未知状态阻断、查单后撤销和成功幂等入账。
- Readability: V2 codec、transport、orchestration、entity/controller 分层明确。
- Architecture: 复用 `WechatPaymentSuccessService`，未复制账务/KDS/打印副作用。
- Security: 修复 RestTemplate DEBUG 付款码泄露风险；外部 XML、签名和商户字段全部按不可信输入处理。
- Performance: 每次请求有超时；撤销 mTLS client 使用 try-with-resources，无连接资源泄露。

## Findings resolved

1. Required：付款码字符串请求体会被 Spring DEBUG 日志打印。改为 UTF-8 `byte[]` 载荷并以测试日志验证脱敏。
2. Required：共享成功服务只按 orderNo 加锁查询。新增可选 expectedShopId，并让 Native/MICROPAY 主动查单传入门店。
3. Required：V2 已签名响应仍需绑定当前交易。客户端现在强制校验 appid、mch_id 和 out_trade_no。

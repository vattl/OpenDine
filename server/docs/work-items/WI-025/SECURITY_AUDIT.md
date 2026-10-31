# Security Audit — WI-025

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: NOT_APPLICABLE

## Threat Model

- 重复收款覆盖：同订单存在未冲正成功 PAYMENT 时，仅完全相同的请求、渠道、金额和第三方交易号可重放。
- 重复退款/篡改重放：幂等号命中后精确比较订单、渠道、金额、原流水和第三方退款号，不一致即拒绝。
- 超额冲正：REVERSAL 按 `original_ledger_id` 汇总已冲正额，只冲原 PAYMENT 剩余余额。
- 账本缺失掩盖：读取路径不再自愈写入；日结逐单比较订单投影与权威流水，差异时不签发令牌。
- 多门店串单：收银结账/现金退款使用 `shop_id + order_no` 行锁；日结和对账均按门店及营业窗口过滤。
- 挂账伪装收款：挂账订单不要求或生成支付流水，对账实收层显式排除。
- 对账误匹配：支付/退款类型分离、退款统一负数、重复订单号条目一次性消费，防止同一渠道条目重复绑定。
- 敏感信息：差异扫描未发现新增私钥、API 密钥或硬编码密码；日志未新增证书、APIv3 密钥或支付密文输出。

## Residual Risk

上线前应使用生产数据副本运行订单—流水一致性审计并处理历史缺口，否则新日结阻断会如设计生效。真实微信/支付宝账单格式仍需在集成环境回放验证。

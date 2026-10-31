-- 微信支付 401 安全处置模板。
-- 不在仓库中保存真实 AppID、商户号、API 密钥、证书序列号或私钥路径。
-- 请先在微信商户平台核对同一商户下的 apiclient_key / 证书序列号，
-- 再通过受控商户管理 API 更新；无 PAYMENT_CONFIG_MASTER_KEY 时密钥写入会被拒绝。

-- 可先退役问题配置，阻止继续创建新交易，同时保留历史交易查单/退款能力：
UPDATE t_payment_merchant_config
SET status = 'RETIRED', enabled = 0, updated_at = NOW()
WHERE id = :merchant_config_id
  AND shop_id = :shop_id;

-- 修复完成后请调用 POST /admin/payment/merchants/{id}/restore，
-- 不要用 SQL 写入明文 api_v3_key_enc/api_v2_key_enc。

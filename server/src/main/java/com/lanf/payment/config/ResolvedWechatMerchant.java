package com.lanf.payment.config;

/**
 * 从 {@code t_payment_merchant_config} 解析的微信商户配置（无 yml 回退）。
 */
public final class ResolvedWechatMerchant {

    public String merchantKey;
    public String legacyMerchantId;
    public String appId;
    public String mchId;
    public String notifyUrl;
    public String refundNotifyUrl;
    public String apiV3Key;
    public String apiV2Key;
    public String serialNo;
    public String platformPubKeyId;
    public String platformPubKeyRef;
    public String privateKeyRef;
    public String clientCertP12Ref;
    public Long dbConfigId;
    public Integer dbShopId;
    public Integer dbCredentialVersion;
}

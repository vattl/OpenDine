package com.lanf.payment.support;

import com.lanf.payment.entity.PaymentMerchantConfigEntity;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.List;

/**
 * 判断 DB 微信商户是否满足线上支付前置条件。
 */
public final class PaymentMerchantReadiness {

    /** 线上微信支付发起时商户配置缺失的提示（createPrepay 兜底）；收银端开关校验已放开（D012）。 */
    public static final String ENABLE_WECHAT_PAY_HINT =
            "请先在支付商户配置中新增并启用微信支付商户（default），方可开启微信支付";

    public static final String ENABLE_MINI_PROGRAM_WECHAT_PAY_HINT =
            "微信小程序支付商户配置不完整，请补齐 AppID、商户号、支付回调地址、APIv3密钥、"
                    + "商户证书序列号、平台公钥ID/公钥及商户私钥后再启用";

    /** @deprecated 使用 {@link #ENABLE_WECHAT_PAY_HINT} */
    public static final String ENABLE_ONLINE_PAY_HINT = ENABLE_WECHAT_PAY_HINT;

    private PaymentMerchantReadiness() {
    }

    public static boolean isWechatRowPayReady(PaymentMerchantConfigEntity row) {
        return missingFields(row).isEmpty();
    }

    public static List<String> missingFields(PaymentMerchantConfigEntity row) {
        List<String> missing = new ArrayList<>();
        if (row == null || row.getEnabled() == null || row.getEnabled() == 0) {
            missing.add("enabled");
        }
        requireText(missing, "appId", row != null ? row.getApp_id() : null);
        requireText(missing, "mchId", row != null ? row.getMch_id() : null);
        requireText(missing, "notifyUrl", row != null ? row.getNotify_url() : null);
        requireText(missing, "serialNo", row != null ? row.getSerial_no() : null);
        requireText(missing, "platformPubKeyId", row != null ? row.getPlatform_pub_key_id() : null);
        requireText(missing, "platformPubKeyRef", row != null ? row.getPlatform_pub_key_ref() : null);
        requireText(missing, "privateKeyRef", row != null ? row.getPrivate_key_ref() : null);
        if (row == null || !StringUtils.hasText(row.getApi_v3_key_enc())) {
            missing.add("apiV3Key");
        }
        return missing;
    }

    private static void requireText(List<String> missing, String name, String value) {
        if (!StringUtils.hasText(value)) {
            missing.add(name);
        }
    }
}

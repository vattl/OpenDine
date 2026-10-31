package com.lanf.payment.service;

import com.lanf.entity.R;
import com.lanf.payment.PaymentErrorCodes;
import com.lanf.payment.support.PaymentMerchantReadiness;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

/**
 * C 端支付入口能力校验（P1：总开关与分渠道；不改变结算逻辑）。
 */
@Service
public class PaymentOnlineGuardService {

    @Autowired
    private PaymentCapabilityService capabilityService;
    @Autowired
    private PaymentMerchantConfigService merchantConfigService;

    public R checkOnlinePay(Integer shopId) {
        if (!capabilityService.isMiniProgramPayEnabled(shopId)) {
            return R.error(PaymentErrorCodes.ONLINE_PAY_DISABLED, capabilityService.getDisabledMessage(shopId));
        }
        return null;
    }

    public R checkWechatPay(Integer shopId) {
        R online = checkOnlinePay(shopId);
        if (online != null) {
            return online;
        }
        PaymentCapabilityService.ResolvedCapability capability = capabilityService.resolve(shopId);
        if (!capability.miniProgramWechatEnabledConfigured) {
            return R.error(PaymentErrorCodes.CHANNEL_DISABLED, capabilityService.getDisabledMessage(shopId));
        }
        if (!capability.miniProgramWechatMerchantReady) {
            String missing = capability.miniProgramWechatMissingFields == null
                    ? ""
                    : String.join(", ", capability.miniProgramWechatMissingFields);
            String message = PaymentMerchantReadiness.ENABLE_MINI_PROGRAM_WECHAT_PAY_HINT;
            if (!missing.isEmpty()) {
                message += "；缺少：" + missing;
            }
            return R.error(PaymentErrorCodes.MERCHANT_NOT_CONFIGURED, message);
        }
        return null;
    }

    /** 收银端微信支付能力校验；与小程序端开关相互独立。 */
    public R checkCashierWechatPay(Integer shopId) {
        PaymentCapabilityService.ResolvedCapability capability = capabilityService.resolve(shopId);
        if (!capability.cashierPayEnabled || !capability.cashierWechatEnabledConfigured) {
            return R.error(PaymentErrorCodes.CHANNEL_DISABLED, capabilityService.getDisabledMessage(shopId));
        }
        if (!capability.wechatMerchantReady) {
            return R.error(PaymentErrorCodes.MERCHANT_NOT_CONFIGURED,
                    "收银微信支付商户未配置完整，请先在运营端完成商户配置");
        }
        return null;
    }

    public R checkCashierWechatMicropay(Integer shopId) {
        R general = checkCashierWechatPay(shopId);
        if (general != null) return general;
        java.util.List<String> missing = merchantConfigService.getWechatMicropayMissingFields(shopId);
        if (!missing.isEmpty()) {
            return R.error(PaymentErrorCodes.MERCHANT_NOT_CONFIGURED,
                    "微信付款码支付配置不完整，缺少：" + String.join(", ", missing));
        }
        return null;
    }

    public R checkBalancePay(Integer shopId) {
        R online = checkOnlinePay(shopId);
        if (online != null) {
            return online;
        }
        if (!capabilityService.isBalanceEnabled(shopId)) {
            return R.error(PaymentErrorCodes.CHANNEL_DISABLED, capabilityService.getDisabledMessage(shopId));
        }
        return null;
    }

    public R checkWechatRecharge(Integer shopId) {
        return checkWechatPay(shopId);
    }
}

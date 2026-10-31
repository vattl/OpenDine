package com.lanf.payment.support;

import org.springframework.util.StringUtils;

public final class PaymentMerchantNoUtil {

    public static final String PREFIX_DINING = "ORD";
    public static final String PREFIX_WX_RECHARGE = "RCH";

    private PaymentMerchantNoUtil() {
    }

    public static boolean isWxRechargeMerchantNo(String businessNo) {
        return StringUtils.hasText(businessNo) && businessNo.startsWith(PREFIX_WX_RECHARGE);
    }

    public static String parseOrderNoFromOutTradeNo(String outTradeNo) {
        if (outTradeNo == null) {
            return null;
        }
        int last = outTradeNo.lastIndexOf('_');
        if (last > 0 && last < outTradeNo.length() - 1) {
            String suffix = outTradeNo.substring(last + 1);
            if (suffix.matches("[0-9]+")) {
                return outTradeNo.substring(0, last);
            }
        }
        return outTradeNo;
    }
}

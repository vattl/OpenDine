package com.lanf.payment.support;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Date;

public final class PaymentDateUtil {

    private static final Logger log = LoggerFactory.getLogger(PaymentDateUtil.class);

    private PaymentDateUtil() {
    }

    public static Date parseWechatSuccessTime(String dateStr) {
        if (dateStr == null || dateStr.trim().isEmpty()) {
            return new Date();
        }
        try {
            return new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX").parse(dateStr.trim());
        } catch (ParseException e) {
            try {
                return new SimpleDateFormat("yyyyMMddHHmmss").parse(dateStr.trim());
            } catch (ParseException ignored) {
                log.error("解析日期失败: {}", dateStr, e);
                return new Date();
            }
        }
    }
}

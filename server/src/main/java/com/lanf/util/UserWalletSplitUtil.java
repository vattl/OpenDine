package com.lanf.util;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * 用户钱包本金 / 赠送金分账（按「分」整数计算，本金份额四舍五入，另一桶取剩余，保证相加等于本次金额）。
 */
public final class UserWalletSplitUtil {

    private UserWalletSplitUtil() {
    }

    /**
     * 本次消费（分）在「当前剩余本金 / 当前剩余赠送金」之间的拆分。
     *
     * @param consumeFen       本次扣款总分，须 &gt; 0
     * @param principalAvailFen 当前本金剩余分，须 &gt;= 0
     * @param giftAvailFen      当前赠送金剩余分，须 &gt;= 0
     * @return [本金扣减分, 赠送金扣减分]，二者之和等于 consumeFen
     */
    public static int[] splitConsumptionFen(long consumeFen, long principalAvailFen, long giftAvailFen) {
        if (consumeFen <= 0) {
            throw new IllegalArgumentException("consumeFen must be positive");
        }
        if (principalAvailFen < 0 || giftAvailFen < 0) {
            throw new IllegalArgumentException("avail fen must be non-negative");
        }
        long total = principalAvailFen + giftAvailFen;
        if (total < consumeFen) {
            throw new IllegalArgumentException("insufficient total wallet");
        }
        if (giftAvailFen == 0) {
            return new int[]{(int) consumeFen, 0};
        }
        if (principalAvailFen == 0) {
            return new int[]{0, (int) consumeFen};
        }
        long dP = BigDecimal.valueOf(consumeFen)
                .multiply(BigDecimal.valueOf(principalAvailFen))
                .divide(BigDecimal.valueOf(total), 0, RoundingMode.HALF_UP)
                .longValue();
        long dG = consumeFen - dP;
        if (dP > principalAvailFen) {
            dP = principalAvailFen;
            dG = consumeFen - dP;
        }
        if (dG > giftAvailFen) {
            dG = giftAvailFen;
            dP = consumeFen - dG;
        }
        if (dP < 0 || dG < 0 || dP > principalAvailFen || dG > giftAvailFen || dP + dG != consumeFen) {
            throw new IllegalStateException("wallet split invariant failed");
        }
        return new int[]{(int) dP, (int) dG};
    }

    /**
     * 退款（分）按「原支付时本金/赠送金扣款」比例拆分退回账户。
     *
     * @param refundFen           本次退款分
     * @param origPrincipalPaidFen 原订单余额支付从本金扣的分
     * @param origGiftPaidFen      原订单余额支付从赠送金扣的分
     */
    public static int[] splitRefundFen(long refundFen, long origPrincipalPaidFen, long origGiftPaidFen) {
        if (refundFen <= 0) {
            throw new IllegalArgumentException("refundFen must be positive");
        }
        if (origPrincipalPaidFen < 0 || origGiftPaidFen < 0) {
            throw new IllegalArgumentException("orig paid fen must be non-negative");
        }
        long origTotal = origPrincipalPaidFen + origGiftPaidFen;
        if (origTotal <= 0) {
            return new int[]{(int) refundFen, 0};
        }
        long dP = BigDecimal.valueOf(refundFen)
                .multiply(BigDecimal.valueOf(origPrincipalPaidFen))
                .divide(BigDecimal.valueOf(origTotal), 0, RoundingMode.HALF_UP)
                .longValue();
        long dG = refundFen - dP;
        if (dP > origPrincipalPaidFen) {
            dP = origPrincipalPaidFen;
            dG = refundFen - dP;
        }
        if (dG > origGiftPaidFen) {
            dG = origGiftPaidFen;
            dP = refundFen - dG;
        }
        if (dP < 0 || dG < 0 || dP + dG != refundFen) {
            throw new IllegalStateException("refund split invariant failed");
        }
        return new int[]{(int) dP, (int) dG};
    }

    /** Convert legacy API numbers before arithmetic; reject non-finite input. */
    public static BigDecimal decimal(Double value) {
        return value == null ? BigDecimal.ZERO : BigDecimal.valueOf(value);
    }

    public static double roundYuan(BigDecimal value) {
        return value.setScale(2, RoundingMode.HALF_UP).doubleValue();
    }

    public static int yuanToFen(double yuan) {
        return yuanToFen(BigDecimal.valueOf(yuan));
    }

    public static BigDecimal fenToYuanBd(int fen) {
        return BigDecimal.valueOf(fen).divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
    }

    public static int yuanToFen(BigDecimal yuan) {
        if (yuan == null) {
            return 0;
        }
        return yuan.setScale(2, RoundingMode.HALF_UP)
                .multiply(BigDecimal.valueOf(100))
                .setScale(0, RoundingMode.HALF_UP)
                .intValueExact();
    }
}

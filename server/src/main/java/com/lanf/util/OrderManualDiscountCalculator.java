package com.lanf.util;

import com.lanf.entity.Order;

/**
 * 运营/收银手动订单优惠计算（写入 {@code t_order.discount_amount}）。
 */
public final class OrderManualDiscountCalculator {

    private OrderManualDiscountCalculator() {
    }

    /** 订单原价（元）= sett_amount + service_fee */
    public static double orderGrossYuan(Order order) {
        if (order == null) {
            return 0d;
        }
        double sett = order.getSett_amount() != null ? order.getSett_amount() : 0d;
        double svc = order.getService_fee() != null ? order.getService_fee() : 0d;
        return round2(sett + svc);
    }

    /**
     * @param discountAmountYuan 直接指定优惠金额（元），优先
     * @param payRate            实付倍率，如 0.9 表示九折（实付=原价×0.9）
     * @param wipeZero           是否在应付上抹零到整数元（增加优惠额）
     */
    public static double resolveDiscountYuan(Order order, Double discountAmountYuan, Double payRate, Boolean wipeZero) {
        double gross = orderGrossYuan(order);
        if (gross <= 0d) {
            return 0d;
        }
        double discount;
        if (discountAmountYuan != null) {
            discount = round2(Math.max(0d, discountAmountYuan));
        } else if (payRate != null) {
            double rate = clampPayRate(payRate);
            discount = round2(gross * (1d - rate));
        } else if (Boolean.TRUE.equals(wipeZero)) {
            discount = order.getDiscount_amount() != null ? order.getDiscount_amount() : 0d;
        } else {
            throw new IllegalArgumentException("请传 discountAmount、payRate 或 wipeZero 至少一项");
        }
        if (discount > gross) {
            discount = gross;
        }
        if (Boolean.TRUE.equals(wipeZero)) {
            // 抹零 = 免去应付的小数零头（向下抹整，如 123.45 → 123.00）；
            // 注意不是 ceil 差（那是补整），修复历史计算偏差。
            double payable = gross - discount;
            if (payable > 0d) {
                double floorPayable = Math.floor(payable);
                if (payable - floorPayable > 0.001d) {
                    discount = round2(discount + (payable - floorPayable));
                }
            }
            if (discount > gross) {
                discount = gross;
            }
        }
        return round2(discount);
    }

    public static double payableAfterDiscountYuan(Order order, double discountYuan) {
        return round2(Math.max(0d, orderGrossYuan(order) - discountYuan));
    }

    private static double clampPayRate(double rate) {
        if (Double.isNaN(rate) || rate <= 0d || rate > 1d) {
            throw new IllegalArgumentException("payRate 须在 (0,1] 之间，如 0.9 表示九折");
        }
        if (rate < 0.01d) {
            return 0.01d;
        }
        return rate;
    }

    private static double round2(double v) {
        return Math.round(v * 100d) / 100d;
    }
}

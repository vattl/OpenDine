package com.lanf.util;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * 打包/外卖订单打包费：商品小计每满 100 元加 1 元，不足 100 元也收 1 元（有商品时）。
 * 下单时对前端 {@code sett_amount} 做二次校验：已含打包费则沿用，否则补入。
 */
public final class OrderPackagingFeeCalculator {

    private static final double MONEY_EPS = 0.01;

    private OrderPackagingFeeCalculator() {
    }

    /**
     * @param goodsSubtotalYuan 商品小计（元，不含打包费、配送费）
     * @return 打包费（元）；商品小计 ≤ 0 时为 0
     */
    public static double calcYuan(double goodsSubtotalYuan) {
        if (goodsSubtotalYuan <= 0) {
            return 0d;
        }
        long units = (long) Math.ceil(goodsSubtotalYuan / 100.0);
        return Math.max(1L, units);
    }

    public static BigDecimal calcBigDecimal(double goodsSubtotalYuan) {
        return BigDecimal.valueOf(calcYuan(goodsSubtotalYuan)).setScale(2, RoundingMode.HALF_UP);
    }

    public static double roundMoney(double v) {
        return Math.round(v * 100) / 100.0;
    }

    /**
     * 堂食：仅商品小计；前端传了 sett 且 ≥ 商品小计时可沿用，否则按明细小计。
     */
    public static double resolveSettForDineIn(double goodsSubtotalYuan, Double frontSettAmountYuan) {
        double goods = roundMoney(goodsSubtotalYuan);
        if (frontSettAmountYuan != null && roundMoney(frontSettAmountYuan) >= goods - MONEY_EPS) {
            return roundMoney(frontSettAmountYuan);
        }
        return goods;
    }

    /**
     * 打包单二次校验 sett_amount。
     */
    public static double resolveSettForTakeOut(double goodsSubtotalYuan, Double frontSettAmountYuan) {
        return resolveSettWithPackaging(goodsSubtotalYuan, frontSettAmountYuan, 0d, false);
    }

    /**
     * 外卖单二次校验 sett_amount（另校验/补全 {@code deliveryFeeYuan}）。
     */
    public static double resolveSettForWaimai(double goodsSubtotalYuan, Double frontSettAmountYuan,
                                              Double deliveryFeeYuan) {
        double delivery = deliveryFeeYuan != null && deliveryFeeYuan > 0
                ? roundMoney(deliveryFeeYuan) : 0d;
        return resolveSettWithPackaging(goodsSubtotalYuan, frontSettAmountYuan, delivery, true);
    }

    private static double resolveSettWithPackaging(double goodsSubtotalYuan, Double frontSettAmountYuan,
                                                   double deliveryFeeYuan, boolean waimai) {
        double goods = roundMoney(goodsSubtotalYuan);
        double packaging = calcYuan(goods);
        double withPack = roundMoney(goods + packaging);
        double fullExpected = roundMoney(withPack + deliveryFeeYuan);

        if (frontSettAmountYuan == null) {
            return waimai && deliveryFeeYuan > 0 ? fullExpected : withPack;
        }
        double front = roundMoney(frontSettAmountYuan);

        if (frontIncludesPackaging(goods, packaging, withPack, front, deliveryFeeYuan, waimai)) {
            if (waimai && deliveryFeeYuan > 0 && !frontIncludesDelivery(fullExpected, front)) {
                return fullExpected;
            }
            return front;
        }

        if (waimai && deliveryFeeYuan > 0) {
            if (approxEquals(front, roundMoney(goods + deliveryFeeYuan))
                    || front <= roundMoney(goods + deliveryFeeYuan) + MONEY_EPS) {
                return fullExpected;
            }
            return roundMoney(front + packaging);
        }
        return withPack;
    }

    /**
     * 判断前端 sett 是否已计入打包费（避免 goods+配送费 被误判为已含打包费）。
     */
    static boolean frontIncludesPackaging(double goods, double packaging, double goodsPlusPack,
                                        double frontSett, double deliveryFee, boolean waimai) {
        if (frontSett >= goodsPlusPack - MONEY_EPS) {
            return true;
        }
        if (waimai && deliveryFee > 0) {
            double withoutDelivery = roundMoney(frontSett - deliveryFee);
            if (withoutDelivery >= goodsPlusPack - MONEY_EPS) {
                return true;
            }
            if (approxEquals(frontSett, roundMoney(goods + deliveryFee))) {
                return false;
            }
        }
        // An amount equal to the goods subtotal explicitly excludes packaging.
        return false;
    }

    private static boolean frontIncludesDelivery(double fullExpected, double frontSett) {
        return frontSett >= fullExpected - MONEY_EPS;
    }

    private static boolean approxEquals(double a, double b) {
        return Math.abs(a - b) <= MONEY_EPS;
    }
}

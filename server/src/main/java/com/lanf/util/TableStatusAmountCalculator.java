package com.lanf.util;

import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.order.OrderDetailLineStatus;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Computes the table-status payable amount from the persisted order amounts.
 * Detail rows are inspected only for audit counters and never redefine the order's payable amount.
 */
public final class TableStatusAmountCalculator {

    private TableStatusAmountCalculator() {
    }

    public static Result calculate(Order order, List<OrderDetail> details) {
        int giftedLineCount = 0;
        int giftedQuantity = 0;
        int refundedLineCount = 0;

        if (details != null) {
            for (OrderDetail detail : details) {
                if (detail == null) continue;
                if (OrderDetailLineStatus.isRefunded(detail.getLine_status())) {
                    refundedLineCount++;
                    continue;
                }
                if (!OrderDetailLineStatus.isActive(detail.getLine_status())
                        || "combo_component".equalsIgnoreCase(trim(detail.getLine_type()))) {
                    continue;
                }
                double lineAmount = round(nonNegative(detail.getTotal_price()));
                if (lineAmount == 0d) {
                    giftedLineCount++;
                    giftedQuantity += positiveQuantity(detail.getQuantity());
                }
            }
        }

        double goodsAmount = round(nonNegative(order != null ? order.getSett_amount() : null));
        double serviceFee = round(nonNegative(order != null ? order.getService_fee() : null));
        double discountAmount = nonNegative(order != null ? order.getDiscount_amount() : null);
        double refundAmount = nonNegative(order != null ? order.getRefund_amount() : null);
        double giftPaymentAmount = nonNegative(order != null ? order.getPay_amount_gift() : null);
        double payableAmount = Math.max(0d, OrderNetRevenue.netRevenueYuan(order));

        return new Result(goodsAmount, serviceFee, round(discountAmount), round(refundAmount),
                round(giftPaymentAmount), payableAmount, giftedLineCount, giftedQuantity, refundedLineCount);
    }

    private static int positiveQuantity(String quantity) {
        try {
            int parsed = Integer.parseInt(quantity != null ? quantity.trim() : "");
            return Math.max(parsed, 0);
        } catch (NumberFormatException ignored) {
            return 0;
        }
    }

    private static double nonNegative(Double value) {
        if (value == null || value.isNaN() || value.isInfinite()) return 0d;
        return Math.max(value, 0d);
    }

    private static double round(double value) {
        return Math.round(value * 100d) / 100d;
    }

    private static String trim(String value) {
        return value == null ? "" : value.trim();
    }

    public static final class Result {
        private final double goodsAmount;
        private final double serviceFee;
        private final double discountAmount;
        private final double refundAmount;
        private final double giftPaymentAmount;
        private final double payableAmount;
        private final int giftedLineCount;
        private final int giftedQuantity;
        private final int refundedLineCount;

        private Result(double goodsAmount, double serviceFee, double discountAmount, double refundAmount,
                       double giftPaymentAmount, double payableAmount, int giftedLineCount,
                       int giftedQuantity, int refundedLineCount) {
            this.goodsAmount = goodsAmount;
            this.serviceFee = serviceFee;
            this.discountAmount = discountAmount;
            this.refundAmount = refundAmount;
            this.giftPaymentAmount = giftPaymentAmount;
            this.payableAmount = payableAmount;
            this.giftedLineCount = giftedLineCount;
            this.giftedQuantity = giftedQuantity;
            this.refundedLineCount = refundedLineCount;
        }

        public double getGoodsAmount() {
            return goodsAmount;
        }

        public double getServiceFee() {
            return serviceFee;
        }

        public double getPayableAmount() {
            return payableAmount;
        }

        public int getGiftedLineCount() {
            return giftedLineCount;
        }

        public int getGiftedQuantity() {
            return giftedQuantity;
        }

        public int getRefundedLineCount() {
            return refundedLineCount;
        }

        public Map<String, Object> toMap() {
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("goods_amount", goodsAmount);
            result.put("service_fee", serviceFee);
            result.put("discount_amount", discountAmount);
            result.put("refund_amount", refundAmount);
            result.put("gift_payment_amount", giftPaymentAmount);
            result.put("payable_amount", payableAmount);
            result.put("gifted_line_count", giftedLineCount);
            result.put("gifted_quantity", giftedQuantity);
            result.put("refunded_line_count", refundedLineCount);
            result.put("calculation_source", "persisted_order_amounts");
            return result;
        }
    }
}

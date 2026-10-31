package com.lanf.payment.support;

import com.lanf.dto.OrderDTO;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.payment.settlement.PayableAmountContext;

/**
 * 支付模块访问订单域能力；券校验、自动接单/打印等仍委托 {@code OrderController}。
 */
public interface OrderPaymentBridge {

    void validateCoupon(OrderDTO order, boolean isAddDishes);

    R fillPayableAmountContext(Order order, Long couponId, String openidForCoupon, PayableAmountContext ctx);

    R settleOrderPayableAmounts(Order order, Long couponId, String openidForCoupon, boolean allowNineFold);

    void runPostPaymentSuccessSideEffects(Order latestOrder, double paidYuan);

    void doAutoAcceptAndPrint(Order order);

    String generatePrintContent(Order order, boolean frontDeskTicket);

    String generateOrderNo();

    String generateRechargeOrderNo();
}

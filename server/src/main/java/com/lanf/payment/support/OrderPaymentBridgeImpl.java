package com.lanf.payment.support;

import com.lanf.controller.OrderController;
import com.lanf.dto.OrderDTO;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.payment.settlement.PayableAmountContext;
import com.lanf.payment.settlement.PaymentSettlementService;
import com.lanf.payment.success.PaymentSuccessHandler;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Component;

@Component
public class OrderPaymentBridgeImpl implements OrderPaymentBridge {

    @Lazy
    @Autowired
    private OrderController orderController;
    @Lazy
    @Autowired
    private PaymentSettlementService paymentSettlementService;
    @Lazy
    @Autowired
    private PaymentSuccessHandler paymentSuccessHandler;
    @Autowired
    private com.lanf.printing.engine.PrintTemplateEngine printTemplateEngine;

    @Override
    public void validateCoupon(OrderDTO order, boolean isAddDishes) {
        orderController.paymentValidateCoupon(order, isAddDishes);
    }

    @Override
    public R fillPayableAmountContext(Order order, Long couponId, String openidForCoupon, PayableAmountContext ctx) {
        return paymentSettlementService.fillPayableAmountContext(order, couponId, openidForCoupon, ctx);
    }

    @Override
    public R settleOrderPayableAmounts(Order order, Long couponId, String openidForCoupon, boolean allowNineFold) {
        return paymentSettlementService.settle(order, couponId, openidForCoupon, allowNineFold);
    }

    @Override
    public void runPostPaymentSuccessSideEffects(Order latestOrder, double paidYuan) {
        paymentSuccessHandler.run(latestOrder, paidYuan);
    }

    @Override
    public void doAutoAcceptAndPrint(Order order) {
        orderController.paymentDoAutoAcceptAndPrint(order);
    }

    @Override
    public String generatePrintContent(Order order, boolean frontDeskTicket) {
        if (printTemplateEngine != null) {
            return printTemplateEngine.renderReceiptTicket(order, frontDeskTicket, com.lanf.printing.engine.PrintTemplateOptions.defaultOptions());
        }
        return orderController.paymentGeneratePrintContent(order, frontDeskTicket);
    }

    @Override
    public String generateOrderNo() {
        return orderController.paymentGenerateOrderNo();
    }

    @Override
    public String generateRechargeOrderNo() {
        return orderController.paymentGenerateRechargeOrderNo();
    }
}

package com.lanf.payment.settlement;

import com.lanf.entity.Order;
import com.lanf.payment.support.OrderPaymentBridge;
import com.lanf.service.IOrderDetailService;
import com.lanf.util.UserWalletSplitUtil;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import java.math.BigDecimal;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PaymentDecimalTest {
    @Test void halfCentRoundsUpAfterDecimalCalculation() {
        PaymentSettlementService service = new PaymentSettlementService();
        ReflectionTestUtils.setField(service,"orderPaymentBridge",mock(OrderPaymentBridge.class));
        ReflectionTestUtils.setField(service,"orderDetailService",mock(IOrderDetailService.class));
        Order order = new Order(); order.setSett_amount(1.005); order.setService_fee(0d);
        PayableAmountContext ctx = new PayableAmountContext();
        assertEquals(0,service.fillPayableAmountContext(order,null,null,ctx).get("code"));
        assertEquals(1.01,ctx.basePaidYuan);
    }
    @Test void overflowMustNotWrapToAnotherPaymentAmount() {
        assertThrows(ArithmeticException.class,()->UserWalletSplitUtil.yuanToFen(new BigDecimal("21474836.48")));
    }
}

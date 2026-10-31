package com.lanf.payment.facade;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.User;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.payment.service.PaymentNinefoldService;
import com.lanf.payment.service.PaymentOnlineGuardService;
import com.lanf.payment.settlement.PaymentSettlementService;
import com.lanf.payment.support.OrderPaymentBridge;
import com.lanf.payment.support.PaymentNotifyState;
import com.lanf.payment.support.PaymentSettlementLedgerHelper;
import com.lanf.service.IOrderService;
import com.lanf.service.IUserService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class PaymentFacadeBalanceLedgerTest {

    @Test
    void payByBalance_whenAuthoritativeLedgerFails_doesNotPersistPaidOrderOrFulfill() {
        PaymentFacadeService service = new PaymentFacadeService();
        IOrderService orderService = mock(IOrderService.class);
        IUserService userService = mock(IUserService.class);
        UserCouponMapper couponMapper = mock(UserCouponMapper.class);
        PaymentOnlineGuardService guard = mock(PaymentOnlineGuardService.class);
        PaymentSettlementService settlement = mock(PaymentSettlementService.class);
        OrderPaymentBridge bridge = mock(OrderPaymentBridge.class);
        PaymentNinefoldService ninefold = mock(PaymentNinefoldService.class);
        PaymentSettlementLedgerHelper ledgerHelper = mock(PaymentSettlementLedgerHelper.class);

        ReflectionTestUtils.setField(service, "orderService", orderService);
        ReflectionTestUtils.setField(service, "userService", userService);
        ReflectionTestUtils.setField(service, "userCouponMapper", couponMapper);
        ReflectionTestUtils.setField(service, "paymentOnlineGuardService", guard);
        ReflectionTestUtils.setField(service, "paymentSettlementService", settlement);
        ReflectionTestUtils.setField(service, "orderPaymentBridge", bridge);
        ReflectionTestUtils.setField(service, "paymentNinefoldService", ninefold);
        ReflectionTestUtils.setField(service, "paymentNotifyState", new PaymentNotifyState());
        ReflectionTestUtils.setField(service, "paymentSettlementLedgerHelper", ledgerHelper);

        Order order = new Order();
        order.setId(21);
        order.setOrder_no("ORD-BAL-21");
        order.setShop_id(7);
        order.setOpenid("payer");
        order.setTransac_status("unsettled");
        order.setSett_amount(50d);
        order.setDiscount_amount(0d);
        order.setService_fee(0d);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(guard.checkBalancePay(7)).thenReturn(null);
        when(bridge.fillPayableAmountContext(eq(order), any(), eq("payer"), any())).thenReturn(R.ok());
        when(settlement.settle(order, null, "payer", false)).thenReturn(R.ok().put("paidYuan", 50d));
        User payer = new User();
        payer.setId(9);
        payer.setPrincipal_balance(new BigDecimal("50.00"));
        payer.setGift_balance(BigDecimal.ZERO);
        when(userService.getUserByOpenid("payer")).thenReturn(payer);
        when(userService.subtractBalanceSplitIfEnough(9, new BigDecimal("50.00"), new BigDecimal("0.00")))
                .thenReturn(true);
        when(ledgerHelper.recordAuthoritativePayment(any(Order.class), any(), any(), anyString()))
                .thenThrow(new IllegalStateException("ledger down"));

        Map<String, String> params = new HashMap<>();
        params.put("orderNo", "ORD-BAL-21");
        params.put("openid", "payer");

        assertThrows(IllegalStateException.class, () -> service.payByBalance(params));
        verify(orderService, never()).updateById(any(Order.class));
        verify(bridge, never()).runPostPaymentSuccessSideEffects(any(Order.class), any(Double.class));
    }
}

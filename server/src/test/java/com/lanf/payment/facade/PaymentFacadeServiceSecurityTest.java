package com.lanf.payment.facade;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.payment.service.PaymentOnlineGuardService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PaymentFacadeServiceSecurityTest {

    @Test
    void getPrepayIdRejectsAuthenticatedUserWhoDoesNotOwnOrder() {
        IOrderService orderService = mock(IOrderService.class);
        PaymentOnlineGuardService onlineGuard = mock(PaymentOnlineGuardService.class);
        Order order = new Order();
        order.setOrder_no("ORDER-1");
        order.setOpenid("owner-openid");
        order.setTransac_status("unsettled");
        order.setShop_id(1);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);
        when(onlineGuard.checkWechatPay(1)).thenReturn(null);

        PaymentFacadeService service = new PaymentFacadeService();
        ReflectionTestUtils.setField(service, "orderService", orderService);
        ReflectionTestUtils.setField(service, "paymentOnlineGuardService", onlineGuard);

        Map<String, String> params = new HashMap<>();
        params.put("orderNo", "ORDER-1");
        params.put("openid", "attacker-openid");
        R result = service.getPrepayId(params);

        assertEquals(403, result.get("code"));
    }
}

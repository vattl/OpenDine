package com.lanf.admin;

import com.lanf.controller.admin.AdminMemberController;
import com.lanf.entity.R;
import com.lanf.entity.Shift;
import com.lanf.entity.User;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.security.AdminShopScopeGuard;
import com.lanf.service.IMemberRechargeService;
import com.lanf.service.IShiftService;
import com.lanf.service.IUserService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AdminMemberRechargeShiftAttributionTest {

    @Test
    void recharge_withActiveOperatorShift_recordsDrawerAttribution() {
        AdminMemberController controller = new AdminMemberController();
        IUserService userService = mock(IUserService.class);
        IMemberRechargeService rechargeService = mock(IMemberRechargeService.class);
        IShiftService shiftService = mock(IShiftService.class);
        AdminShopScopeGuard guard = mock(AdminShopScopeGuard.class);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 9);
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 7);

        when(guard.resolveTargetShopId(any(), any())).thenAnswer(invocation -> {
            int[] holder = invocation.getArgument(1);
            holder[0] = 7;
            return null;
        });

        User user = new User();
        user.setId(3);
        user.setOpenid("openid-3");
        when(userService.getUserByPhone("13800000000")).thenReturn(user);
        when(userService.addBalanceAndGift(eq(3), any(), any())).thenReturn(true);
        Shift shift = new Shift();
        shift.setDrawer_session_id(88L);
        when(shiftService.getOne(any(), eq(false))).thenReturn(shift);

        ReflectionTestUtils.setField(controller, "userService", userService);
        ReflectionTestUtils.setField(controller, "memberRechargeService", rechargeService);
        ReflectionTestUtils.setField(controller, "shiftService", shiftService);
        ReflectionTestUtils.setField(controller, "adminShopScopeGuard", guard);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("phone", "13800000000");
        body.put("amount", "100.00");
        body.put("gift_amount", "10.00");

        R result = controller.recharge(body);

        assertEquals(0, result.get("code"));
        verify(rechargeService).recordAdminSuccess(3, "openid-3", 7, 9, 88L,
                new BigDecimal("100.00"), new BigDecimal("10.00"),
                "后台人工充值，手机号 13800000000");
    }
}

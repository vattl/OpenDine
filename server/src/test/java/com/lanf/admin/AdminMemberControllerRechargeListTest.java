package com.lanf.admin;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.lanf.controller.admin.AdminMemberController;
import com.lanf.entity.MemberRecharge;
import com.lanf.entity.R;
import com.lanf.security.AdminShopScopeGuard;
import com.lanf.service.IMemberRechargeService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.Collections;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class AdminMemberControllerRechargeListTest {

    @Test
    void rechargeList_returnsMemberPhoneInRecords() {
        AdminMemberController controller = new AdminMemberController();
        IMemberRechargeService rechargeService = mock(IMemberRechargeService.class);
        AdminShopScopeGuard guard = mock(AdminShopScopeGuard.class);
        MockHttpServletRequest request = new MockHttpServletRequest();

        ReflectionTestUtils.setField(controller, "memberRechargeService", rechargeService);
        ReflectionTestUtils.setField(controller, "adminShopScopeGuard", guard);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);

        MemberRecharge recharge = new MemberRecharge();
        recharge.setId(1L);
        recharge.setUser_id(101);
        recharge.setOpenid("openid_101");
        recharge.setRecharge_amount(new BigDecimal("100.00"));
        recharge.setStatus("success");

        IPage<MemberRecharge> page = new Page<>(1, 20);
        page.setRecords(Collections.singletonList(recharge));
        page.setTotal(1);

        when(rechargeService.page(any(), any())).thenReturn(page);
        doAnswer(invocation -> {
            List<MemberRecharge> list = invocation.getArgument(0);
            for (MemberRecharge mr : list) {
                mr.setPhone("13912345678");
            }
            return null;
        }).when(rechargeService).attachMemberPhones(any());

        R res = controller.rechargeList(null, null, null, null, null, null, null,
                null, true, null, null, null, null,
                null, null, null, null, "created_at", "desc", 1, 20);

        assertEquals(0, res.get("code"));
        verify(rechargeService).attachMemberPhones(page.getRecords());

        @SuppressWarnings("unchecked")
        List<MemberRecharge> resultList = (List<MemberRecharge>) res.get("list");
        assertNotNull(resultList);
        assertEquals(1, resultList.size());
        assertEquals("13912345678", resultList.get(0).getPhone());
    }
}

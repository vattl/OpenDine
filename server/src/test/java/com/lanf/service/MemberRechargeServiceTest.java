package com.lanf.service;

import com.lanf.entity.MemberRecharge;
import com.lanf.entity.User;
import com.lanf.mapper.MemberRechargeMapper;
import com.lanf.mapper.UserMapper;
import com.lanf.service.impl.MemberRechargeServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.*;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class MemberRechargeServiceTest {

    private MemberRechargeServiceImpl service;
    private MemberRechargeMapper mapper;
    private UserMapper userMapper;

    @BeforeEach
    void setUp() {
        service = new MemberRechargeServiceImpl();
        mapper = mock(MemberRechargeMapper.class);
        userMapper = mock(UserMapper.class);
        ReflectionTestUtils.setField(service, "baseMapper", mapper);
        ReflectionTestUtils.setField(service, "userMapper", userMapper);
    }

    @Test
    void summarizeSuccessfulByWindow_separatesPrincipalGiftAndCreditedTotal() {
        Map<String, Object> aggregate = new LinkedHashMap<>();
        aggregate.put("success_count", 2L);
        aggregate.put("principal_amount", new BigDecimal("150.25"));
        aggregate.put("gift_amount", new BigDecimal("10.75"));
        when(mapper.summarizeSuccessfulByWindow(any(), any(), any())).thenReturn(aggregate);

        Date start = new Date(1_000L);
        Date end = new Date(2_000L);
        MemberRechargeSummary summary = service.summarizeSuccessfulByWindow(7, start, end);

        assertEquals(2L, summary.getSuccessCount());
        assertEquals(15025L, summary.getPrincipalFen());
        assertEquals(1075L, summary.getGiftFen());
        assertEquals(16100L, summary.getCreditedTotalFen());

        verify(mapper).summarizeSuccessfulByWindow(7, start, end);
    }

    @Test
    void recordAdminSuccess_withShiftContext_persistsServerResolvedAttribution() {
        when(mapper.insert(any(MemberRecharge.class))).thenReturn(1);

        service.recordAdminSuccess(3, "openid-3", 7, 9, 88L,
                new BigDecimal("100.00"), new BigDecimal("10.00"), "柜台充值");

        ArgumentCaptor<MemberRecharge> captor = ArgumentCaptor.forClass(MemberRecharge.class);
        verify(mapper).insert(captor.capture());
        MemberRecharge saved = captor.getValue();
        assertEquals(9, saved.getOperator_id());
        assertEquals(88L, saved.getDrawer_session_id());
        assertEquals(new BigDecimal("100.00"), saved.getRecharge_amount());
        assertEquals(new BigDecimal("10.00"), saved.getGift_amount());
    }

    @Test
    void attachMemberPhones_populatesPhoneByUserIdAndOpenid() {
        MemberRecharge r1 = new MemberRecharge();
        r1.setUser_id(101);
        r1.setOpenid("openid_101");

        MemberRecharge r2 = new MemberRecharge();
        r2.setUser_id(null);
        r2.setOpenid("openid_102");

        MemberRecharge r3 = new MemberRecharge();
        r3.setUser_id(103);
        r3.setOpenid("openid_103");

        User u1 = new User();
        u1.setId(101);
        u1.setOpenid("openid_101");
        u1.setPhone("13800138001");

        User u2 = new User();
        u2.setId(102);
        u2.setOpenid("openid_102");
        u2.setPhone("13800138002");

        when(userMapper.selectBatchIds(any())).thenReturn(Collections.singletonList(u1));
        when(userMapper.selectList(any())).thenReturn(Collections.singletonList(u2));

        service.attachMemberPhones(Arrays.asList(r1, r2, r3));

        assertEquals("13800138001", r1.getPhone());
        assertEquals("13800138002", r2.getPhone());
        assertNull(r3.getPhone());
    }

    @Test
    void attachMemberPhones_handlesNullAndEmpty() {
        service.attachMemberPhones(null);
        service.attachMemberPhones(Collections.emptyList());
    }
}

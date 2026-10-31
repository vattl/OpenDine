package com.lanf.admin;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.config.ServiceFeeConfig;
import com.lanf.controller.admin.AdminMemberController;
import com.lanf.controller.admin.AdminOrderDetailController;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.entity.User;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.service.IUserService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

public class AdminBillDetailCoordinationTest {

    private AdminOrderDetailController orderDetailController;
    private AdminMemberController memberController;
    private IOrderService orderService;
    private IOrderDetailService orderDetailService;
    private ITakeoutDeliveryService takeoutDeliveryService;
    private IUserService userService;
    private ServiceFeeConfig serviceFeeConfig;
    private com.lanf.kds.service.KdsDetailStatusResolver kdsDetailStatusResolver;
    private com.lanf.kds.service.KdsOrderEnrichService kdsOrderEnrichService;
    private com.lanf.kds.mapper.KdsTicketMapper kdsTicketMapper;
    private com.lanf.kds.mapper.KdsOrderMapper kdsOrderMapper;
    private com.lanf.mapper.InviteRecordMapper inviteRecordMapper;
    private com.lanf.mapper.UserCouponMapper userCouponMapper;

    @BeforeEach
    void setUp() {
        orderDetailController = new AdminOrderDetailController();
        memberController = new AdminMemberController();

        orderService = mock(IOrderService.class);
        orderDetailService = mock(IOrderDetailService.class);
        takeoutDeliveryService = mock(ITakeoutDeliveryService.class);
        userService = mock(IUserService.class);
        serviceFeeConfig = mock(ServiceFeeConfig.class);

        kdsTicketMapper = mock(com.lanf.kds.mapper.KdsTicketMapper.class);
        kdsOrderMapper = mock(com.lanf.kds.mapper.KdsOrderMapper.class);
        inviteRecordMapper = mock(com.lanf.mapper.InviteRecordMapper.class);
        userCouponMapper = mock(com.lanf.mapper.UserCouponMapper.class);

        kdsDetailStatusResolver = new com.lanf.kds.service.KdsDetailStatusResolver();
        ReflectionTestUtils.setField(kdsDetailStatusResolver, "ticketMapper", kdsTicketMapper);

        kdsOrderEnrichService = new com.lanf.kds.service.KdsOrderEnrichService();
        ReflectionTestUtils.setField(kdsOrderEnrichService, "kdsOrderMapper", kdsOrderMapper);

        MockHttpServletRequest request = new MockHttpServletRequest();

        ReflectionTestUtils.setField(orderDetailController, "orderService", orderService);
        ReflectionTestUtils.setField(orderDetailController, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(orderDetailController, "takeoutDeliveryService", takeoutDeliveryService);
        ReflectionTestUtils.setField(orderDetailController, "serviceFeeConfig", serviceFeeConfig);
        ReflectionTestUtils.setField(orderDetailController, "httpServletRequest", request);
        ReflectionTestUtils.setField(orderDetailController, "kdsDetailStatusResolver", kdsDetailStatusResolver);
        ReflectionTestUtils.setField(orderDetailController, "kdsOrderEnrichService", kdsOrderEnrichService);

        ReflectionTestUtils.setField(memberController, "orderService", orderService);
        ReflectionTestUtils.setField(memberController, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(memberController, "userService", userService);
        ReflectionTestUtils.setField(memberController, "httpServletRequest", request);
        ReflectionTestUtils.setField(memberController, "inviteRecordMapper", inviteRecordMapper);
        ReflectionTestUtils.setField(memberController, "userCouponMapper", userCouponMapper);
    }

    @Test
    @SuppressWarnings("unchecked")
    void testOrderDetailList_FullCoordinatedResponse() {
        Order order = new Order();
        order.setId(101);
        order.setOrder_no("ORD202609010001");
        order.setTable_number("12");
        order.setTransac_status("success");
        order.setDineInOrTakeOut("堂食");
        order.setSett_amount(258.00);
        order.setDiscount_amount(28.00);
        order.setService_fee(0.00);
        order.setRefund_amount(0.00);
        order.setPayment_method("微信支付");
        order.setPay_amount_wechat(230.00);
        order.setOpenid("user_openid_123");
        order.setRemark("少辣，打包一份柠檬茶");
        order.setOrder_time(new Date());
        order.setPay_time(new Date());

        when(orderService.getById(101)).thenReturn(order);

        User member = new User();
        member.setId(88);
        member.setName("李老板");
        member.setPhone("13912345678");
        member.setOpenid("user_openid_123");
        member.setBalance(new BigDecimal("1580.00"));
        member.setPoints(360);
        when(userService.getUserByOpenid("user_openid_123")).thenReturn(member);

        OrderDetail item1 = new OrderDetail();
        item1.setId(1);
        item1.setName("招牌油边王");
        item1.setSelectedSpicy("大份 · 微辣");
        item1.setQuantity("2");
        item1.setUnit("份");
        item1.setTotal_price(136.00);
        item1.setLine_status("normal");

        OrderDetail item2 = new OrderDetail();
        item2.setId(2);
        item2.setName("手打冻打柠檬茶");
        item2.setSelectedSpicy("少冰 · 常规糖");
        item2.setQuantity("2");
        item2.setUnit("杯");
        item2.setTotal_price(32.00);
        item2.setLine_status("normal");

        when(orderDetailService.list(any(QueryWrapper.class))).thenReturn(Arrays.asList(item1, item2));

        R response = orderDetailController.listByOrderId(101);
        assertEquals(0, response.get("code"));

        // 基线版响应：order 为 Order 实体，明细为 list 字段
        Order orderResp = (Order) response.get("order");
        assertNotNull(orderResp);
        assertEquals("ORD202609010001", orderResp.getOrder_no());
        assertEquals("12", orderResp.getTable_number());

        List<OrderDetail> detailList = (List<OrderDetail>) response.get("list");
        assertNotNull(detailList);
        assertEquals(2, detailList.size());
        assertEquals("招牌油边王", detailList.get(0).getName());
        assertEquals(136.00, detailList.get(0).getTotal_price(), 0.001);
        assertEquals("手打冻打柠檬茶", detailList.get(1).getName());
        assertEquals(32.00, detailList.get(1).getTotal_price(), 0.001);
    }

    @Test
    @SuppressWarnings("unchecked")
    void testMemberProfile_WithTagsAndLastVisit() {
        User member = new User();
        member.setId(88);
        member.setName("李老板");
        member.setPhone("13912345678");
        member.setOpenid("user_openid_123");
        member.setBalance(new BigDecimal("1580.00"));
        member.setPoints(360);
        when(userService.getUserByPhone("13912345678")).thenReturn(member);

        Order o1 = new Order();
        o1.setId(101);
        o1.setOrder_no("ORD001");
        o1.setTransac_status("success");
        o1.setSett_amount(300.00);
        o1.setPay_time(new Date(System.currentTimeMillis() - 3600000));
        o1.setPayment_method("微信支付");

        Order o2 = new Order();
        o2.setId(102);
        o2.setOrder_no("ORD002");
        o2.setTransac_status("success");
        o2.setSett_amount(200.00);
        o2.setPay_time(new Date(System.currentTimeMillis() - 7200000));
        o2.setPayment_method("微信支付");

        when(orderService.list(any(QueryWrapper.class))).thenReturn(Arrays.asList(o1, o2));

        OrderDetail d1 = new OrderDetail();
        d1.setId(1);
        d1.setMId(101);
        d1.setName("招牌油边王");
        d1.setSelectedSpicy("{\"辣度\":\"微辣\"}");

        when(orderDetailService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(d1));

        R response = memberController.profile("13912345678", "all");
        assertEquals(0, response.get("code"));

        Map<String, Object> profile = (Map<String, Object>) response.get("profile");
        assertNotNull(profile);
        assertEquals(2, profile.get("orderCount"));
        assertEquals(500.00, profile.get("totalAmount"));
        assertEquals(250.00, profile.get("avgOrderValue"));
        assertNotNull(profile.get("lastVisit"));
        assertNotNull(profile.get("last_visit_time"));

        List<String> tags = (List<String>) profile.get("tags");
        assertNotNull(tags);
        assertTrue(tags.contains("微辣") || tags.contains("爱吃招牌油边王") || tags.contains("回头客"));

        Map<String, Object> data = (Map<String, Object>) response.get("data");
        assertNotNull(data);
        assertEquals(profile, data);
    }

    @Test
    @SuppressWarnings("unchecked")
    void testMemberConsumption_WithLimitAndFormattedRecords() {
        User member = new User();
        member.setId(88);
        member.setName("李老板");
        member.setPhone("13912345678");
        member.setOpenid("user_openid_123");
        when(userService.getUserByPhone("13912345678")).thenReturn(member);

        Order o1 = new Order();
        o1.setId(99);
        o1.setOrder_no("ORD202608250002");
        o1.setSett_amount(320.00);
        o1.setDiscount_amount(0.00);
        o1.setService_fee(0.00);
        o1.setRefund_amount(0.00);
        o1.setPay_amount_gift(0.00);
        o1.setTable_number("06");
        o1.setPayment_method("微信支付");
        o1.setDineInOrTakeOut("堂食");
        o1.setPay_time(new Date());

        when(orderService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(o1));

        R response = memberController.consumption("13912345678", 5, null, null, "all");
        assertEquals(0, response.get("code"));

        List<Map<String, Object>> list = (List<Map<String, Object>>) response.get("list");
        assertNotNull(list);
        assertEquals(1, list.size());
        assertEquals(99, list.get(0).get("id"));
        assertEquals("ORD202608250002", list.get(0).get("order_no"));
        assertEquals(320.00, list.get(0).get("amount"));
        assertEquals(320.00, list.get(0).get("actual_amount"));
        assertEquals("06", list.get(0).get("table_number"));
        assertEquals("微信支付", list.get(0).get("payment_method"));
        assertEquals("堂食", list.get(0).get("dineInOrTakeOut"));

        List<Map<String, Object>> data = (List<Map<String, Object>>) response.get("data");
        assertNotNull(data);
        assertEquals(list, data);
    }

    @Test
    @SuppressWarnings("unchecked")
    void testOrderDetailList_KdsItemStatusEnrichment() {
        Order order = new Order();
        order.setId(200);
        order.setOrder_no("ORD202609090001");
        order.setTable_number("08");
        order.setTransac_status("success");
        order.setDineInOrTakeOut("堂食");

        when(orderService.getById(200)).thenReturn(order);

        OrderDetail d1 = new OrderDetail();
        d1.setId(10);
        d1.setMId(200);
        d1.setName("羊肉串");
        d1.setLine_status("normal");

        OrderDetail d2 = new OrderDetail();
        d2.setId(11);
        d2.setMId(200);
        d2.setName("生蚝");
        d2.setLine_status("normal");

        OrderDetail d3 = new OrderDetail();
        d3.setId(12);
        d3.setMId(200);
        d3.setName("烤茄子");
        d3.setLine_status("refunded");

        when(orderDetailService.list(any(QueryWrapper.class))).thenReturn(Arrays.asList(d1, d2, d3));

        com.lanf.kds.entity.KdsTicket t1 = new com.lanf.kds.entity.KdsTicket();
        t1.setDetail_id(10);
        t1.setItem_status(com.lanf.kds.KdsItemStatus.COOKING);
        t1.setServed_quantity(0);

        com.lanf.kds.entity.KdsTicket t2 = new com.lanf.kds.entity.KdsTicket();
        t2.setDetail_id(11);
        t2.setItem_status(com.lanf.kds.KdsItemStatus.DONE);
        t2.setServed_quantity(2);

        when(kdsTicketMapper.selectList(any(QueryWrapper.class))).thenReturn(Arrays.asList(t1, t2));

        com.lanf.kds.entity.KdsOrder kdsOrder = new com.lanf.kds.entity.KdsOrder();
        kdsOrder.setOrder_id(200);
        kdsOrder.setKds_order_status(20); // 制作中

        when(kdsOrderMapper.selectList(any(QueryWrapper.class))).thenReturn(Collections.singletonList(kdsOrder));

        R response = orderDetailController.listByOrderId(200);
        assertEquals(0, response.get("code"));

        Order respOrder = (Order) response.get("order");
        assertNotNull(respOrder);
        assertEquals(20, respOrder.getKds_order_status());

        List<OrderDetail> details = (List<OrderDetail>) response.get("list");
        assertNotNull(details);
        assertEquals(3, details.size());

        // d1 (COOKING)
        assertEquals(com.lanf.kds.KdsItemStatus.COOKING, details.get(0).getKds_item_status());
        assertEquals("制作中", details.get(0).getKds_status_text());
        assertEquals(0, details.get(0).getKds_served_quantity());

        // d2 (DONE)
        assertEquals(com.lanf.kds.KdsItemStatus.DONE, details.get(1).getKds_item_status());
        assertEquals("已完成", details.get(1).getKds_status_text());
        assertEquals(2, details.get(1).getKds_served_quantity());

        // d3 (Refunded fallback)
        assertEquals(com.lanf.kds.KdsItemStatus.VOID, details.get(2).getKds_item_status());
        assertEquals("已退菜", details.get(2).getKds_status_text());
        assertEquals(0, details.get(2).getKds_served_quantity());
    }
}

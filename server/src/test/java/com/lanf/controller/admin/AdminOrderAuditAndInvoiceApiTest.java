package com.lanf.controller.admin;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.entity.*;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class AdminOrderAuditAndInvoiceApiTest {

    private AdminOrderController adminOrderController;
    private AdminMemberController adminMemberController;

    private IOrderService orderService;
    private IOrderDetailService orderDetailService;
    private IUserService userService;
    private PaymentLedgerService paymentLedgerService;

    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        adminOrderController = new AdminOrderController();
        adminMemberController = new AdminMemberController();

        orderService = mock(IOrderService.class);
        orderDetailService = mock(IOrderDetailService.class);
        userService = mock(IUserService.class);
        paymentLedgerService = mock(PaymentLedgerService.class);

        com.lanf.mapper.OrderInvoiceMapper invoiceMapper = mock(com.lanf.mapper.OrderInvoiceMapper.class);
        com.lanf.service.impl.OrderInvoiceServiceImpl invoiceServiceImpl = new com.lanf.service.impl.OrderInvoiceServiceImpl();
        ReflectionTestUtils.setField(invoiceServiceImpl, "baseMapper", invoiceMapper);
        ReflectionTestUtils.setField(invoiceServiceImpl, "objectMapper", new com.fasterxml.jackson.databind.ObjectMapper());

        request = new MockHttpServletRequest();
        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 5);
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 1);

        ReflectionTestUtils.setField(adminOrderController, "orderService", orderService);
        ReflectionTestUtils.setField(adminOrderController, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(adminOrderController, "paymentLedgerService", paymentLedgerService);
        ReflectionTestUtils.setField(adminOrderController, "orderInvoiceService", invoiceServiceImpl);
        ReflectionTestUtils.setField(adminOrderController, "httpServletRequest", request);

        ReflectionTestUtils.setField(adminMemberController, "userService", userService);
        ReflectionTestUtils.setField(adminMemberController, "orderService", orderService);
        ReflectionTestUtils.setField(adminMemberController, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(adminMemberController, "httpServletRequest", request);
    }

    @Test
    void createInvoiceQrcode_success() {
        Order order = new Order();
        order.setId(101);
        order.setOrder_no("ORD202610220803");
        order.setShop_id(5);
        order.setSett_amount(288.00);
        order.setTransac_status("success");
        order.setPay_time(new Date());

        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);

        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORD202610220803");
        body.put("tableNumber", "A03");
        body.put("invoiceAmount", 288.00);
        body.put("taxRate", 0.06);

        R r = adminOrderController.createInvoiceQrcode(body);
        assertEquals(200, r.get("code"));

        Map<String, Object> data = (Map<String, Object>) r.get("data");
        assertNotNull(data);
        assertEquals("ORD202610220803", data.get("orderNo"));
        assertEquals("PENDING_SCAN", data.get("invoiceStatus"));
        assertTrue(String.valueOf(data.get("invoiceQrUrl")).contains("ORD202610220803"));
        assertEquals(1440, data.get("expireMinutes"));
    }

    @Test
    void createInvoiceQrcode_unpaidOrder_rejected() {
        Order order = new Order();
        order.setId(102);
        order.setOrder_no("ORD202610220804");
        order.setShop_id(5);
        order.setSett_amount(100.00);
        order.setTransac_status("unsettled");

        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);

        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORD202610220804");

        R r = adminOrderController.createInvoiceQrcode(body);
        assertEquals(400, r.get("code"));
        assertTrue(String.valueOf(r.get("msg")).contains("未支付订单不可开具发票"));
    }

    @Test
    void createInvoiceQrcode_excessiveAmount_rejected() {
        Order order = new Order();
        order.setId(101);
        order.setOrder_no("ORD202610220803");
        order.setShop_id(5);
        order.setSett_amount(100.00);
        order.setTransac_status("success");
        order.setPay_time(new Date());

        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);

        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORD202610220803");
        body.put("invoiceAmount", 200.00);

        R r = adminOrderController.createInvoiceQrcode(body);
        assertEquals(400, r.get("code"));
        assertTrue(String.valueOf(r.get("msg")).contains("开票金额超出剩余可开票金额") || String.valueOf(r.get("msg")).contains("开票金额不能超过订单实付金额"));
    }

    @Test
    void getAuditTimeline_successWithCashPayment() {
        Order order = new Order();
        order.setId(101);
        order.setOrder_no("ORD202610220803");
        order.setShop_id(5);
        order.setTable_number("A03");
        order.setNumber_of_diners("4");
        order.setOrder_admin_name("张晓峰 (0801)");
        order.setPayment_method("现金");
        order.setSett_amount(288.00);
        order.setTransac_status("success");
        order.setOrder_time(new Date(1761128120000L));
        order.setPay_time(new Date(1761129735000L));

        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);

        OrderDetail d1 = new OrderDetail();
        d1.setName("烤油边");
        d1.setMorder_num(1);
        when(orderDetailService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(d1));

        PaymentLedger ledger = PaymentLedger.builder()
                .ledger_no("LEDGER-20261022-001")
                .channel(PaymentLedger.CHANNEL_CASH)
                .amount_fen(28800)
                .created_at(order.getPay_time())
                .build();
        when(paymentLedgerService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(ledger));

        R r = adminOrderController.getAuditTimeline("ORD202610220803");
        assertEquals(200, r.get("code"));

        Map<String, Object> data = (Map<String, Object>) r.get("data");
        assertNotNull(data);
        List<Map<String, Object>> events = (List<Map<String, Object>>) data.get("events");
        assertNotNull(events);
        assertTrue(events.size() >= 4);

        Set<String> actions = new HashSet<>();
        for (Map<String, Object> evt : events) {
            actions.add(String.valueOf(evt.get("action")));
        }
        assertTrue(actions.contains("CREATE_ORDER"));
        assertTrue(actions.contains("KITCHEN_PRINT"));
        assertTrue(actions.contains("PAY_SUCCESS"));
        assertTrue(actions.contains("CASH_DRAWER_OPEN"));
    }

    @Test
    void getPersonaTags_success() {
        User user = new User();
        user.setId(88);
        user.setPhone("13800138000");
        user.setOpenid("wx_openid_88");
        user.setBalance(BigDecimal.valueOf(500.00));

        when(userService.getUserByPhone("13800138000")).thenReturn(user);

        Order o1 = new Order();
        o1.setId(1);
        o1.setTable_number("A03");
        o1.setPay_time(new Date());
        o1.setTransac_status("success");

        Order o2 = new Order();
        o2.setId(2);
        o2.setTable_number("A05");
        o2.setPay_time(new Date(System.currentTimeMillis() - 86400000L));
        o2.setTransac_status("success");

        Order o3 = new Order();
        o3.setId(3);
        o3.setTable_number("A02");
        o3.setPay_time(new Date(System.currentTimeMillis() - 172800000L));
        o3.setTransac_status("success");

        Order o4 = new Order();
        o4.setId(4);
        o4.setTable_number("A01");
        o4.setPay_time(new Date(System.currentTimeMillis() - 259200000L));
        o4.setTransac_status("success");

        when(orderService.list(any(Wrapper.class))).thenReturn(Arrays.asList(o1, o2, o3, o4));

        OrderDetail d1 = new OrderDetail();
        d1.setName("招牌烤油边");
        OrderDetail d2 = new OrderDetail();
        d2.setName("特醇鲜啤(1L)");
        when(orderDetailService.list(any(Wrapper.class))).thenReturn(Arrays.asList(d1, d2));

        R r = adminMemberController.getPersonaTags("13800138000", null, "accessible");
        assertEquals(200, r.get("code"));

        Map<String, Object> data = (Map<String, Object>) r.get("data");
        assertNotNull(data);
        assertEquals(88, data.get("memberId"));
        assertEquals("13800138000", data.get("phone"));

        List<Map<String, String>> tags = (List<Map<String, String>>) data.get("tags");
        assertNotNull(tags);
        assertEquals(6, tags.size());

        Set<String> types = new HashSet<>();
        for (Map<String, String> tag : tags) {
            types.add(tag.get("type"));
        }
        assertTrue(types.contains("frequency"));
        assertTrue(types.contains("taste"));
        assertTrue(types.contains("drink"));
        assertTrue(types.contains("seat"));
        assertTrue(types.contains("time"));
        assertTrue(types.contains("behavior"));
    }

    @Test
    void listInvoices_success() {
        IOrderInvoiceService mockInvoiceService = mock(IOrderInvoiceService.class);
        ReflectionTestUtils.setField(adminOrderController, "orderInvoiceService", mockInvoiceService);

        Map<String, Object> mockData = new HashMap<>();
        mockData.put("records", Collections.emptyList());
        mockData.put("total", 0);
        mockData.put("current", 1);
        mockData.put("metrics", Collections.emptyMap());

        R mockResp = new R();
        mockResp.put("code", 200);
        mockResp.put("data", mockData);
        when(mockInvoiceService.pageInvoiceForAdmin(eq(1), eq(10), eq("TITLE_SUBMITTED"), eq("阿里巴巴"), isNull(), isNull(), eq(5)))
                .thenReturn(mockResp);

        R r = adminOrderController.listInvoices(1, 10, "TITLE_SUBMITTED", "阿里巴巴", null, null);
        assertEquals(200, r.get("code"));
        assertEquals(mockData, r.get("data"));
        verify(mockInvoiceService).pageInvoiceForAdmin(1, 10, "TITLE_SUBMITTED", "阿里巴巴", null, null, 5);
    }

    @Test
    void listInvoices_withExplicitShopIdParam_filtersByParamShop() {
        IOrderInvoiceService mockInvoiceService = mock(IOrderInvoiceService.class);
        ReflectionTestUtils.setField(adminOrderController, "orderInvoiceService", mockInvoiceService);

        Map<String, Object> mockData = new HashMap<>();
        mockData.put("total", 1L);
        mockData.put("list", Collections.emptyList());

        R mockResp = new R();
        mockResp.put("code", 200);
        mockResp.put("data", mockData);
        when(mockInvoiceService.pageInvoiceForAdmin(eq(1), eq(10), eq("TITLE_SUBMITTED"), isNull(), isNull(), isNull(), eq(9)))
                .thenReturn(mockResp);

        R r = adminOrderController.listInvoices(1, 10, "TITLE_SUBMITTED", null, null, null, 9, null);
        assertEquals(200, r.get("code"));
        assertEquals(mockData, r.get("data"));
        verify(mockInvoiceService).pageInvoiceForAdmin(1, 10, "TITLE_SUBMITTED", null, null, null, 9);
    }

    @Test
    void rejectInvoice_success() {
        IOrderInvoiceService mockInvoiceService = mock(IOrderInvoiceService.class);
        ReflectionTestUtils.setField(adminOrderController, "orderInvoiceService", mockInvoiceService);

        Order order = new Order();
        order.setId(101);
        order.setOrder_no("ORD202610280088");
        order.setShop_id(5);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);

        R mockRejectResp = new R();
        mockRejectResp.put("code", 200);
        mockRejectResp.put("msg", "已成功驳回开票申请");
        when(mockInvoiceService.rejectInvoice("ORD202610280088", "抬头税号不匹配，请核实后重新提交", 1))
                .thenReturn(mockRejectResp);

        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORD202610280088");
        body.put("reason", "抬头税号不匹配，请核实后重新提交");

        R r = adminOrderController.rejectInvoice(body);
        assertEquals(200, r.get("code"));
        assertEquals("已成功驳回开票申请", r.get("msg"));
        verify(mockInvoiceService).rejectInvoice("ORD202610280088", "抬头税号不匹配，请核实后重新提交", 1);
    }

    @Test
    void rejectInvoice_missingParams_returnsError() {
        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORD202610280088");
        // missing reason
        R r = adminOrderController.rejectInvoice(body);
        assertEquals(400, r.get("code"));
        assertTrue(String.valueOf(r.get("msg")).contains("单号和驳回原因不能为空"));

        body.clear();
        body.put("reason", "Some reason");
        // missing orderNo
        r = adminOrderController.rejectInvoice(body);
        assertEquals(400, r.get("code"));
        assertTrue(String.valueOf(r.get("msg")).contains("单号和驳回原因不能为空"));
    }

    @Test
    void insertInvoiceCard_success() {
        IOrderInvoiceService mockInvoiceService = mock(IOrderInvoiceService.class);
        ReflectionTestUtils.setField(adminOrderController, "orderInvoiceService", mockInvoiceService);

        Order order = new Order();
        order.setId(102);
        order.setOrder_no("ORD-CARD-001");
        order.setShop_id(5);
        when(orderService.getOne(any(Wrapper.class))).thenReturn(order);

        R mockCardResp = new R();
        mockCardResp.put("code", 200);
        mockCardResp.put("msg", "已成功推送到微信卡包");
        mockCardResp.put("cardStatus", "SUCCESS");
        when(mockInvoiceService.insertInvoiceToWechatCard("ORD-CARD-001", 1)).thenReturn(mockCardResp);

        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "ORD-CARD-001");

        R r = adminOrderController.insertInvoiceCard(body);
        assertEquals(200, r.get("code"));
        assertEquals("SUCCESS", r.get("cardStatus"));
        verify(mockInvoiceService).insertInvoiceToWechatCard("ORD-CARD-001", 1);
    }

    @Test
    void insertInvoiceCard_missingOrderNo_returnsError() {
        Map<String, Object> body = new HashMap<>();
        body.put("orderNo", "");
        R r = adminOrderController.insertInvoiceCard(body);
        assertEquals(400, r.get("code"));
        assertTrue(String.valueOf(r.get("msg")).contains("订单号不能为空"));
    }
}

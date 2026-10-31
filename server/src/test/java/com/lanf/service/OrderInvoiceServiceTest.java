package com.lanf.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderInvoice;
import com.lanf.entity.R;
import com.lanf.mapper.OrderInvoiceMapper;
import com.lanf.payment.channel.wechat.WechatMerchantKeyStore;
import com.lanf.service.impl.OrderInvoiceServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.RestTemplate;

import java.math.BigDecimal;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class OrderInvoiceServiceTest {

    private OrderInvoiceServiceImpl invoiceService;
    private OrderInvoiceMapper invoiceMapper;
    private WechatMerchantKeyStore merchantKeyStore;
    private RestTemplate restTemplate;
    private ObjectMapper objectMapper;
    private IOrderService orderService;

    @BeforeEach
    void setUp() {
        invoiceService = new OrderInvoiceServiceImpl();
        invoiceMapper = mock(OrderInvoiceMapper.class);
        merchantKeyStore = mock(WechatMerchantKeyStore.class);
        restTemplate = mock(RestTemplate.class);
        objectMapper = new ObjectMapper();
        orderService = mock(IOrderService.class);

        ReflectionTestUtils.setField(invoiceService, "baseMapper", invoiceMapper);
        ReflectionTestUtils.setField(invoiceService, "merchantKeyStore", merchantKeyStore);
        ReflectionTestUtils.setField(invoiceService, "restTemplate", restTemplate);
        ReflectionTestUtils.setField(invoiceService, "objectMapper", objectMapper);
        ReflectionTestUtils.setField(invoiceService, "orderService", orderService);
    }

    @Test
    void createInvoiceQrcode_unpaidOrder_rejected() {
        Order order = new Order();
        order.setId(100);
        order.setOrder_no("ORD-UNPAID-001");
        order.setShop_id(1);
        order.setSett_amount(100.00);
        order.setTransac_status("unsettled");

        R result = invoiceService.createInvoiceQrcode(order, 100.00, 0.06, 9);
        assertEquals(400, result.get("code"));
        assertTrue(String.valueOf(result.get("msg")).contains("未支付订单不可开具发票"));
        verify(invoiceMapper, never()).insert(any(OrderInvoice.class));
    }

    @Test
    void createInvoiceQrcode_excessiveAmount_rejected() {
        Order order = new Order();
        order.setId(101);
        order.setOrder_no("ORD-TEST-001");
        order.setShop_id(1);
        order.setSett_amount(100.00);
        order.setTransac_status("success");
        order.setPay_time(new Date());

        R result = invoiceService.createInvoiceQrcode(order, 200.00, 0.06, 9);
        assertEquals(400, result.get("code"));
        assertTrue(String.valueOf(result.get("msg")).contains("开票金额超出剩余可开票金额"));
        verify(invoiceMapper, never()).insert(any(OrderInvoice.class));
    }

    @Test
    void createInvoiceQrcode_success_generatesTokenAndHash() {
        Order order = new Order();
        order.setId(102);
        order.setOrder_no("ORD-TEST-002");
        order.setShop_id(1);
        order.setSett_amount(88.00);
        order.setTransac_status("success");
        order.setPay_time(new Date());

        when(invoiceMapper.selectOne(any())).thenReturn(null);
        when(invoiceMapper.insert(any(OrderInvoice.class))).thenAnswer(invocation -> {
            OrderInvoice inv = invocation.getArgument(0);
            assertNotNull(inv.getToken_hash());
            assertEquals(64, inv.getToken_hash().length());
            assertNotNull(inv.getToken_expire_at());
            assertNull(inv.getError_msg(), "error_msg 不得泄露明文令牌");
            return 1;
        });

        R result = invoiceService.createInvoiceQrcode(order, 88.00, 0.06, 9);
        assertEquals(200, result.get("code"));

        Map<String, Object> data = (Map<String, Object>) result.get("data");
        assertNotNull(data);
        assertEquals("ORD-TEST-002", data.get("orderNo"));
        assertEquals("PENDING_SCAN", data.get("invoiceStatus"));
        assertEquals(88.00, data.get("invoiceAmount"));
        assertTrue(String.valueOf(data.get("invoiceQrUrl")).contains("token=inv_"));

        verify(invoiceMapper).insert(any(OrderInvoice.class));
    }

    @Test
    void createInvoiceQrcode_cumulativeLimitExceeded_rejected() {
        Order order = new Order();
        order.setId(103);
        order.setOrder_no("ORD-TEST-003");
        order.setShop_id(1);
        order.setSett_amount(100.00);
        order.setTransac_status("success");
        order.setPay_time(new Date());

        OrderInvoice existingInvoice = OrderInvoice.builder()
                .id(1L)
                .order_no("ORD-TEST-003")
                .invoice_amount(new BigDecimal("100.00"))
                .invoice_status(OrderInvoice.STATUS_SUCCESS)
                .build();

        when(invoiceMapper.selectList(any())).thenReturn(Collections.singletonList(existingInvoice));

        R result = invoiceService.createInvoiceQrcode(order, 50.00, 0.06, 9);
        assertEquals(400, result.get("code"));
        assertTrue(String.valueOf(result.get("msg")).contains("无可开票余额"));
    }

    @Test
    void getInvoiceInfoForPublic_missingToken_rejected401() {
        R result = invoiceService.getInvoiceInfoForPublic("ORD-TEST-004", null, "");
        assertEquals(401, result.get("code"));
        assertTrue(String.valueOf(result.get("msg")).contains("缺少安全令牌"));
    }

    @Test
    void getInvoiceInfoForPublic_missingRecord_rejected404() {
        when(invoiceMapper.selectOne(any())).thenReturn(null);

        R result = invoiceService.getInvoiceInfoForPublic("ORD-NOT-EXIST", null, "token_123");
        assertEquals(404, result.get("code"));
        assertTrue(String.valueOf(result.get("msg")).contains("未找到对应的开票记录"));
        // 确保没有触发自动初始化落库
        verify(invoiceMapper, never()).insert(any(OrderInvoice.class));
    }

    @Test
    void getInvoiceInfoForPublic_invalidToken_rejected403() {
        String realToken = "inv_secret1234567890";
        String realHash = OrderInvoiceServiceImpl.sha256Hex(realToken);

        OrderInvoice invoice = OrderInvoice.builder()
                .id(10L)
                .order_no("ORD-TEST-005")
                .token_hash(realHash)
                .token_expire_at(new Date(System.currentTimeMillis() + 3600000L))
                .invoice_status(OrderInvoice.STATUS_PENDING_SCAN)
                .invoice_amount(new BigDecimal("150.00"))
                .build();

        when(invoiceMapper.selectOne(any())).thenReturn(invoice);

        R result = invoiceService.getInvoiceInfoForPublic("ORD-TEST-005", null, "inv_wrong_token");
        assertEquals(403, result.get("code"));
        assertTrue(String.valueOf(result.get("msg")).contains("开票令牌无效"));
    }

    @Test
    void getInvoiceInfoForPublic_expiredToken_rejected403() {
        String token = "inv_expired123";
        String tokenHash = OrderInvoiceServiceImpl.sha256Hex(token);

        OrderInvoice invoice = OrderInvoice.builder()
                .id(11L)
                .order_no("ORD-TEST-006")
                .token_hash(tokenHash)
                .token_expire_at(new Date(System.currentTimeMillis() - 10000L)) // 已过期
                .invoice_status(OrderInvoice.STATUS_PENDING_SCAN)
                .build();

        when(invoiceMapper.selectOne(any())).thenReturn(invoice);

        R result = invoiceService.getInvoiceInfoForPublic("ORD-TEST-006", null, token);
        assertEquals(403, result.get("code"));
        assertTrue(String.valueOf(result.get("msg")).contains("开票申请已过期"));
    }

    @Test
    void getInvoiceInfoForPublic_validToken_returnsMaskedPii() {
        String token = "inv_valid_token_123";
        String tokenHash = OrderInvoiceServiceImpl.sha256Hex(token);

        OrderInvoice invoice = OrderInvoice.builder()
                .id(12L)
                .order_no("ORD-TEST-007")
                .token_hash(tokenHash)
                .token_expire_at(new Date(System.currentTimeMillis() + 3600000L))
                .invoice_status(OrderInvoice.STATUS_TITLE_SUBMITTED)
                .invoice_amount(new BigDecimal("150.00"))
                .tax_rate(new BigDecimal("0.0600"))
                .buyer_title("北京老肥家餐饮管理有限公司")
                .buyer_tax_no("91110108MA00000000")
                .buyer_phone("13812345678")
                .buyer_email("finance@laofei.com")
                .build();

        when(invoiceMapper.selectOne(any())).thenReturn(invoice);

        R result = invoiceService.getInvoiceInfoForPublic("ORD-TEST-007", null, token);
        assertEquals(200, result.get("code"));
        Map<String, Object> data = (Map<String, Object>) result.get("data");
        assertEquals("ORD-TEST-007", data.get("orderNo"));
        assertEquals("北京老肥家餐饮管理有限公司", data.get("buyerTitle"));
        // 验证脱敏
        assertEquals("9111********0000", data.get("buyerTaxNo"));
        assertEquals("138****5678", data.get("buyerPhone"));
        assertEquals("f***e@laofei.com", data.get("buyerEmail"));
    }

    @Test
    void submitInvoiceTitleFromCustomer_validCompany_updatesStatusAndUsedAt() {
        String token = "inv_token_submit";
        String tokenHash = OrderInvoiceServiceImpl.sha256Hex(token);

        OrderInvoice invoice = OrderInvoice.builder()
                .id(13L)
                .order_no("ORD-TEST-008")
                .token_hash(tokenHash)
                .token_expire_at(new Date(System.currentTimeMillis() + 3600000L))
                .invoice_status(OrderInvoice.STATUS_PENDING_SCAN)
                .invoice_amount(new BigDecimal("66.00"))
                .build();

        when(invoiceMapper.selectOne(any())).thenReturn(invoice);
        when(invoiceMapper.updateById(any(OrderInvoice.class))).thenReturn(1);

        R result = invoiceService.submitInvoiceTitleFromCustomer(
                "ORD-TEST-008", null, token,
                "COMPANY", "北京华莱士餐饮管理有限公司", "91110108MA00000000",
                "finance@test.com", "13800000000"
        );

        assertEquals(200, result.get("code"));
        assertEquals(OrderInvoice.STATUS_TITLE_SUBMITTED, invoice.getInvoice_status());
        assertEquals("北京华莱士餐饮管理有限公司", invoice.getBuyer_title());
        assertEquals("91110108MA00000000", invoice.getBuyer_tax_no());
        assertEquals("finance@test.com", invoice.getBuyer_email());
        assertNotNull(invoice.getToken_used_at());
        verify(invoiceMapper).updateById(invoice);
    }

    @Test
    void submitInvoiceTitleFromCustomer_alreadySuccess_rejected() {
        String token = "inv_token_submit2";
        String tokenHash = OrderInvoiceServiceImpl.sha256Hex(token);

        OrderInvoice invoice = OrderInvoice.builder()
                .id(14L)
                .order_no("ORD-TEST-009")
                .token_hash(tokenHash)
                .token_expire_at(new Date(System.currentTimeMillis() + 3600000L))
                .invoice_status(OrderInvoice.STATUS_SUCCESS)
                .build();

        when(invoiceMapper.selectOne(any())).thenReturn(invoice);

        R result = invoiceService.submitInvoiceTitleFromCustomer(
                "ORD-TEST-009", null, token,
                "COMPANY", "新抬头公司", "91110108MA00000000",
                "test@test.com", "13800000000"
        );

        assertEquals(400, result.get("code"));
        assertTrue(String.valueOf(result.get("msg")).contains("发票已开具完成，不可重复修改抬头"));
    }

    @Test
    void issueInvoice_pendingScan_rejectedByStateMachine() {
        OrderInvoice invoice = OrderInvoice.builder()
                .id(15L)
                .order_no("ORD-TEST-010")
                .invoice_status(OrderInvoice.STATUS_PENDING_SCAN)
                .build();

        when(invoiceMapper.selectOne(any())).thenReturn(invoice);

        R result = invoiceService.issueInvoice("ORD-TEST-010", "20261028001", "011002200111", "https://download.pdf", 9);
        assertEquals(400, result.get("code"));
        assertTrue(String.valueOf(result.get("msg")).contains("顾客尚未提交发票抬头"));
    }

    @Test
    void issueInvoice_titleSubmitted_success() {
        OrderInvoice invoice = OrderInvoice.builder()
                .id(16L)
                .order_no("ORD-TEST-011")
                .invoice_status(OrderInvoice.STATUS_TITLE_SUBMITTED)
                .build();

        when(invoiceMapper.selectOne(any())).thenReturn(invoice);
        when(invoiceMapper.updateById(any(OrderInvoice.class))).thenReturn(1);

        R result = invoiceService.issueInvoice("ORD-TEST-011", "20261028001", "011002200111", "https://download.pdf", 9);
        assertEquals(200, result.get("code"));
        assertEquals(OrderInvoice.STATUS_SUCCESS, invoice.getInvoice_status());
        assertEquals("20261028001", invoice.getFapiao_number());
        assertEquals("011002200111", invoice.getFapiao_code());
        assertEquals("https://download.pdf", invoice.getFapiao_file_url());
        verify(invoiceMapper).updateById(invoice);
    }

    @Test
    void utilityMethods_maskingAndSanitize() {
        assertEquals("138****5678", OrderInvoiceServiceImpl.maskPhone("13812345678"));
        assertEquals("9111********0000", OrderInvoiceServiceImpl.maskTaxNo("91110108MA00000000"));
        assertEquals("f***e@domain.com", OrderInvoiceServiceImpl.maskEmail("finance@domain.com"));
        assertNull(OrderInvoiceServiceImpl.sanitizeFileUrl("javascript:alert(1)"));
        assertEquals("https://download.pdf", OrderInvoiceServiceImpl.sanitizeFileUrl("https://download.pdf"));
    }

    @Test
    void rejectInvoice_titleSubmitted_success() {
        OrderInvoice invoice = OrderInvoice.builder()
                .id(20L)
                .order_no("ORD-REJECT-001")
                .invoice_status(OrderInvoice.STATUS_TITLE_SUBMITTED)
                .build();

        when(invoiceMapper.selectOne(any())).thenReturn(invoice);
        when(invoiceMapper.updateById(any(OrderInvoice.class))).thenReturn(1);

        R result = invoiceService.rejectInvoice("ORD-REJECT-001", "税号位数错误", 8);
        assertEquals(200, result.get("code"));
        assertEquals(OrderInvoice.STATUS_REJECTED, invoice.getInvoice_status());
        assertEquals("税号位数错误", invoice.getError_msg());
        assertEquals(8, invoice.getOperator_id());
        verify(invoiceMapper).updateById(invoice);
    }

    @Test
    void rejectInvoice_alreadySuccess_forbidden() {
        OrderInvoice invoice = OrderInvoice.builder()
                .id(21L)
                .order_no("ORD-REJECT-002")
                .invoice_status(OrderInvoice.STATUS_SUCCESS)
                .build();

        when(invoiceMapper.selectOne(any())).thenReturn(invoice);

        R result = invoiceService.rejectInvoice("ORD-REJECT-002", "税号错误", 8);
        assertEquals(400, result.get("code"));
        assertTrue(String.valueOf(result.get("msg")).contains("已开具完成，不可驳回"));
    }

    @Test
    void rejectInvoice_pendingScan_forbidden() {
        OrderInvoice invoice = OrderInvoice.builder()
                .id(22L)
                .order_no("ORD-REJECT-003")
                .invoice_status(OrderInvoice.STATUS_PENDING_SCAN)
                .build();

        when(invoiceMapper.selectOne(any())).thenReturn(invoice);

        R result = invoiceService.rejectInvoice("ORD-REJECT-003", "错误", 8);
        assertEquals(400, result.get("code"));
        assertTrue(String.valueOf(result.get("msg")).contains("顾客尚未提交发票抬头"));
    }

    @Test
    void issueInvoice_rejectedState_forbidden() {
        OrderInvoice invoice = OrderInvoice.builder()
                .id(23L)
                .order_no("ORD-ISSUE-REJ")
                .invoice_status(OrderInvoice.STATUS_REJECTED)
                .build();

        when(invoiceMapper.selectOne(any())).thenReturn(invoice);

        R result = invoiceService.issueInvoice("ORD-ISSUE-REJ", "24110001", null, null, 8);
        assertEquals(400, result.get("code"));
        assertTrue(String.valueOf(result.get("msg")).contains("开票申请已被驳回"));
    }

    @Test
    void issueInvoice_emptyFileUrl_success() {
        OrderInvoice invoice = OrderInvoice.builder()
                .id(24L)
                .order_no("ORD-ISSUE-NOURL")
                .invoice_status(OrderInvoice.STATUS_TITLE_SUBMITTED)
                .build();

        when(invoiceMapper.selectOne(any())).thenReturn(invoice);
        when(invoiceMapper.updateById(any(OrderInvoice.class))).thenReturn(1);

        R result = invoiceService.issueInvoice("ORD-ISSUE-NOURL", "24110002", "CODE001", "", 8);
        assertEquals(200, result.get("code"));
        assertEquals(OrderInvoice.STATUS_SUCCESS, invoice.getInvoice_status());
        assertNull(invoice.getFapiao_file_url());
    }

    @Test
    void submitInvoiceTitle_fromRejected_resubmissionSuccess() {
        String token = "safe-token-for-resubmission-12345";
        String tokenHash = OrderInvoiceServiceImpl.sha256Hex(token);
        Date future = new Date(System.currentTimeMillis() + 3600_000L);

        OrderInvoice invoice = OrderInvoice.builder()
                .id(25L)
                .order_no("ORD-RESUBMIT-001")
                .token_hash(tokenHash)
                .token_expire_at(future)
                .invoice_status(OrderInvoice.STATUS_REJECTED)
                .error_msg("上次税号错误")
                .build();

        when(invoiceMapper.selectOne(any())).thenReturn(invoice);
        when(invoiceMapper.updateById(any(OrderInvoice.class))).thenReturn(1);

        R result = invoiceService.submitInvoiceTitleFromCustomer("ORD-RESUBMIT-001", null, token,
                "COMPANY", "北京华胜新科公司", "91110108MA0028XY9Q", "test@test.com", "13800000000");

        assertEquals(200, result.get("code"));
        assertEquals(OrderInvoice.STATUS_TITLE_SUBMITTED, invoice.getInvoice_status());
        assertNull(invoice.getError_msg()); // 驳回原因应被清空
        assertEquals("北京华胜新科公司", invoice.getBuyer_title());
        assertEquals("91110108MA0028XY9Q", invoice.getBuyer_tax_no());
    }

    @Test
    void getInvoiceInfoForPublic_rejected_returnsRejectReason() {
        String token = "safe-token-rejected-query-12345";
        String tokenHash = OrderInvoiceServiceImpl.sha256Hex(token);
        Date future = new Date(System.currentTimeMillis() + 3600_000L);

        OrderInvoice invoice = OrderInvoice.builder()
                .id(26L)
                .order_no("ORD-QUERY-REJ")
                .token_hash(tokenHash)
                .token_expire_at(future)
                .invoice_status(OrderInvoice.STATUS_REJECTED)
                .error_msg("请提供正确的统一社会信用代码")
                .buyer_title("错误企业抬头")
                .build();

        when(invoiceMapper.selectOne(any())).thenReturn(invoice);

        R result = invoiceService.getInvoiceInfoForPublic("ORD-QUERY-REJ", null, token);
        assertEquals(200, result.get("code"));
        Map<String, Object> data = (Map<String, Object>) result.get("data");
        assertEquals(OrderInvoice.STATUS_REJECTED, data.get("invoiceStatus"));
        assertEquals("请提供正确的统一社会信用代码", data.get("rejectReason"));
    }

    @Test
    void pageInvoiceForAdmin_success() {
        com.baomidou.mybatisplus.extension.plugins.pagination.Page<OrderInvoice> mockPage =
                new com.baomidou.mybatisplus.extension.plugins.pagination.Page<>(1, 10);
        List<OrderInvoice> list = Arrays.asList(
                OrderInvoice.builder().id(1L).order_no("ORD-PAGE-1").invoice_status(OrderInvoice.STATUS_TITLE_SUBMITTED).build(),
                OrderInvoice.builder().id(2L).order_no("ORD-PAGE-2").invoice_status(OrderInvoice.STATUS_SUCCESS).build()
        );
        mockPage.setRecords(list);
        mockPage.setTotal(2);

        when(invoiceMapper.selectPage(any(), any())).thenAnswer(invocation -> {
            com.baomidou.mybatisplus.extension.plugins.pagination.Page<OrderInvoice> p = invocation.getArgument(0);
            p.setRecords(list);
            p.setTotal(2);
            return p;
        });
        when(invoiceMapper.selectCount(any())).thenReturn(5);

        R result = invoiceService.pageInvoiceForAdmin(1, 10, "TITLE_SUBMITTED", "ORD", null, null, 1);
        assertEquals(200, result.get("code"));
        Map<String, Object> data = (Map<String, Object>) result.get("data");
        assertNotNull(data);
        assertEquals(2, ((Number) data.get("total")).intValue());
        Map<String, Object> metrics = (Map<String, Object>) data.get("metrics");
        assertNotNull(metrics);
        assertTrue(metrics.containsKey("countWaiting"));
        assertTrue(metrics.containsKey("countSuccess"));
        assertTrue(metrics.containsKey("countRejected"));
        assertTrue(metrics.containsKey("countPendingScan"));
    }

    @Test
    void pageInvoiceForAdmin_enrichesShopTaxEntityInfo() {
        IShopService shopService = mock(IShopService.class);
        ReflectionTestUtils.setField(invoiceService, "shopService", shopService);

        com.lanf.entity.Shop shop = new com.lanf.entity.Shop();
        shop.setId(1);
        shop.setName("老肥家总店");
        shop.setCode("SHOP001");
        shop.setAddress("广东省深圳市南山区高新南九道科技南路");

        when(shopService.listByIds(any())).thenReturn(Collections.singletonList(shop));

        com.baomidou.mybatisplus.extension.plugins.pagination.Page<OrderInvoice> mockPage =
                new com.baomidou.mybatisplus.extension.plugins.pagination.Page<>(1, 10);
        OrderInvoice inv = OrderInvoice.builder()
                .id(1L)
                .order_no("ORD-TAX-001")
                .shop_id(1)
                .invoice_status(OrderInvoice.STATUS_TITLE_SUBMITTED)
                .build();
        List<OrderInvoice> list = new ArrayList<>(Collections.singletonList(inv));
        mockPage.setRecords(list);
        mockPage.setTotal(1);

        when(invoiceMapper.selectPage(any(), any())).thenAnswer(invocation -> {
            com.baomidou.mybatisplus.extension.plugins.pagination.Page<OrderInvoice> p = invocation.getArgument(0);
            p.setRecords(list);
            p.setTotal(1);
            return p;
        });
        when(invoiceMapper.selectCount(any())).thenReturn(1);

        R result = invoiceService.pageInvoiceForAdmin(1, 10, null, null, null, null, null);
        assertEquals(200, result.get("code"));
        Map<String, Object> data = (Map<String, Object>) result.get("data");
        List<OrderInvoice> records = (List<OrderInvoice>) data.get("list");
        assertEquals(1, records.size());
        assertEquals("老肥家总店", records.get(0).getShop_name(), "各门店为独立纳税主体，必须丰富门店主体名称");
        assertEquals("SHOP001", records.get(0).getShop_code(), "必须丰富门店主体编码");
        assertEquals("广东省深圳市南山区高新南九道科技南路", records.get(0).getShop_address(), "必须丰富门店地址用于税务定位");
        assertEquals("国家税务总局深圳市电子税务局", records.get(0).getTax_bureau_name(), "必须精准匹配对应税局");
        assertEquals("https://etax.shenzhen.chinatax.gov.cn/", records.get(0).getTax_bureau_url(), "必须精准提供对应税局URL");
    }

    @Test
    void insertInvoiceToWechatCard_noCredential_gracefullyMarksFailed() {
        OrderInvoice inv = OrderInvoice.builder()
                .id(30L)
                .order_no("ORD-CARD-NOCRED")
                .invoice_status(OrderInvoice.STATUS_SUCCESS)
                .fapiao_number("24110008")
                .build();
        when(invoiceMapper.selectOne(any())).thenReturn(inv);
        when(invoiceMapper.updateById(any(OrderInvoice.class))).thenReturn(1);
        when(merchantKeyStore.resolveForPay(any(), any(), any())).thenReturn(null);

        R result = invoiceService.insertInvoiceToWechatCard("ORD-CARD-NOCRED", 1);
        assertEquals(200, result.get("code"));
        assertEquals(OrderInvoice.CARD_STATUS_FAILED, result.get("cardStatus"));
        assertEquals(OrderInvoice.CARD_STATUS_FAILED, inv.getCard_insert_status());
        assertTrue(inv.getCard_insert_msg().contains("私钥凭据未就绪"));
    }

    @Test
    void insertInvoiceToWechatCard_unissuedInvoice_rejected() {
        OrderInvoice inv = OrderInvoice.builder()
                .id(31L)
                .order_no("ORD-CARD-UNISSUED")
                .invoice_status(OrderInvoice.STATUS_TITLE_SUBMITTED)
                .fapiao_number("24110009")
                .build();
        when(invoiceMapper.selectOne(any())).thenReturn(inv);

        R result = invoiceService.insertInvoiceToWechatCard("ORD-CARD-UNISSUED", 1);
        assertEquals(400, result.get("code"));
        assertTrue(String.valueOf(result.get("msg")).contains("发票尚未开具完成"));
    }
}

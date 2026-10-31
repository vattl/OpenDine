package com.lanf.printing;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.Shop;
import com.lanf.printing.engine.PrintTemplateEngine;
import com.lanf.printing.engine.PrintTemplateEngineImpl;
import com.lanf.printing.engine.PrintTicketParser;
import com.lanf.printing.entity.PrintingDevice;
import com.lanf.printing.entity.PrintingRule;
import com.lanf.printing.service.PrintDispatcherService;
import com.lanf.printing.service.impl.PrintDispatcherServiceImpl;
import com.lanf.printing.entity.PrintingTemplate;
import com.lanf.printing.mapper.PrintingDeviceMapper;
import com.lanf.printing.mapper.PrintingJobMapper;
import com.lanf.printing.mapper.PrintingRuleMapper;
import com.lanf.printing.mapper.PrintingTemplateMapper;
import com.lanf.printing.model.PrintPreviewResult;
import com.lanf.printing.service.PrintingService;
import com.lanf.service.IFeieyunService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
public class PrintPreviewTest {

    @Mock
    private PrintingDeviceMapper deviceMapper;
    @Mock
    private PrintingRuleMapper ruleMapper;
    @Mock
    private PrintingJobMapper jobMapper;
    @Mock
    private PrintingTemplateMapper templateMapper;
    @Mock
    private IFeieyunService feieyunService;
    @Mock
    private IShopService shopService;
    @Mock
    private IOrderService orderService;
    @Mock
    private IOrderDetailService orderDetailService;

    private ObjectMapper objectMapper;
    private PrintTemplateEngine templateEngine;
    private PrintDispatcherService printDispatcherService;
    private PrintingService printingService;

    @BeforeEach
    void setUp() {
        objectMapper = new ObjectMapper();
        templateEngine = new PrintTemplateEngineImpl();
        printingService = new PrintingService();

        ReflectionTestUtils.setField(printingService, "deviceMapper", deviceMapper);
        ReflectionTestUtils.setField(printingService, "ruleMapper", ruleMapper);
        ReflectionTestUtils.setField(printingService, "jobMapper", jobMapper);
        ReflectionTestUtils.setField(printingService, "templateMapper", templateMapper);
        ReflectionTestUtils.setField(printingService, "feieyunService", feieyunService);
        ReflectionTestUtils.setField(printingService, "shopService", shopService);
        ReflectionTestUtils.setField(printingService, "orderService", orderService);
        ReflectionTestUtils.setField(printingService, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(printingService, "printTemplateEngine", templateEngine);
        ReflectionTestUtils.setField(printingService, "objectMapper", objectMapper);

        // 统一组装规则：设计器预览走真实调度器的同一渲染内核（真实打印同源）
        printDispatcherService = new PrintDispatcherServiceImpl();
        ReflectionTestUtils.setField(printDispatcherService, "deviceMapper", deviceMapper);
        ReflectionTestUtils.setField(printDispatcherService, "ruleMapper", ruleMapper);
        ReflectionTestUtils.setField(printDispatcherService, "jobMapper", jobMapper);
        ReflectionTestUtils.setField(printDispatcherService, "templateMapper", templateMapper);
        ReflectionTestUtils.setField(printDispatcherService, "feieyunService", feieyunService);
        ReflectionTestUtils.setField(printDispatcherService, "templateEngine", templateEngine);
        ReflectionTestUtils.setField(printDispatcherService, "shopService", shopService);
        ReflectionTestUtils.setField(printingService, "printDispatcherService", printDispatcherService);

        // 默认生效规则与云设备（设计器预览与真实打印同路径）
        PrintingRule defRule = new PrintingRule();
        defRule.setId(1L);
        defRule.setShop_id(1);
        defRule.setDevice_id(10L);
        defRule.setScenario("ORDER");
        defRule.setCopies(1);
        defRule.setEnabled(1);
        org.mockito.Mockito.lenient().when(ruleMapper.selectList(any())).thenReturn(Collections.singletonList(defRule));
        PrintingDevice defDev = new PrintingDevice();
        defDev.setId(10L);
        defDev.setShop_id(1);
        defDev.setName("飞鹅云打印机(测试)");
        defDev.setTransport("CLOUD");
        defDev.setBrand("飞鹅");
        defDev.setStatus("ONLINE");
        defDev.setConnection_json("{\"paperSize\":\"58mm\",\"sn\":\"987654321\",\"user\":\"u\",\"ukey\":\"k\"}");
        org.mockito.Mockito.lenient().when(deviceMapper.selectById(10L)).thenReturn(defDev);

        Shop shop = new Shop();
        shop.setId(1);
        shop.setName("老肥油边王(松源海鲜街)");
        org.mockito.Mockito.lenient().when(shopService.getById(1)).thenReturn(shop);

        // 默认自动 Mock 模板库返回标准 DSL 模板
        org.mockito.Mockito.lenient().when(templateMapper.selectOne(any())).thenAnswer(inv -> {
            PrintingTemplate pt = new PrintingTemplate();
            pt.setId(99L);
            pt.setShop_id(0);
            pt.setScenario("ORDER");
            pt.setTemplate_code("tpl_sys_order");
            pt.setTemplate_name("系统默认前台结账单");
            try {
                pt.setTemplate_json(objectMapper.writeValueAsString(templateEngine.buildDefaultDsl("ORDER", "58mm")));
            } catch (Exception e) {
                pt.setTemplate_json("{}");
            }
            return pt;
        });
    }

    private void mockTemplateForScenario(String scenario) {
        when(templateMapper.selectOne(any())).thenAnswer(inv -> {
            PrintingTemplate pt = new PrintingTemplate();
            pt.setId(100L);
            pt.setShop_id(0);
            pt.setScenario(scenario);
            pt.setTemplate_code("tpl_sys_" + scenario.toLowerCase());
            pt.setTemplate_name("系统默认模板");
            try {
                pt.setTemplate_json(objectMapper.writeValueAsString(templateEngine.buildDefaultDsl(scenario, "58mm")));
            } catch (Exception e) {
                pt.setTemplate_json("{}");
            }
            return pt;
        });
    }

    @Test
    void testParser_toPlainText() {
        String raw = "<CB>老肥油边王</CB><BR><CB>结账单</CB><BR>--------------------------------<BR>名称　　　　　 单价  数量  金额<BR>";
        String plain = PrintTicketParser.toPlainText(raw);
        assertFalse(plain.contains("<CB>"));
        assertFalse(plain.contains("<BR>"));
        assertTrue(plain.contains("老肥油边王"));
        assertTrue(plain.contains("结账单"));
    }

    @Test
    void testParser_parseElements() {
        String raw = "<CB>老肥油边王</CB><BR><CB>结账单</CB><BR>--------------------------------<BR>"
                + "名称　　　　　 单价  数量  金额<BR>"
                + "炭烤羊肉串　　  5.00   10  50.00<BR>"
                + "--------------------------------<BR>"
                + "原价金额: ￥50.00<BR>"
                + "<B>实付金额: ￥50.00</B><BR>"
                + "<QR>https://example.com/pay</QR><BR>"
                + "<CUT>";

        List<PrintPreviewResult.PrintPreviewElement> elements = PrintTicketParser.parseElements(raw);
        assertNotNull(elements);
        assertFalse(elements.isEmpty());

        boolean hasHeader = false;
        boolean hasQr = false;
        boolean hasCut = false;
        for (PrintPreviewResult.PrintPreviewElement el : elements) {
            if ("HEADER".equals(el.getType())) hasHeader = true;
            if ("QRCODE".equals(el.getType())) hasQr = true;
            if ("CUT".equals(el.getType())) hasCut = true;
        }
        assertTrue(hasHeader);
        assertTrue(hasQr);
        assertTrue(hasCut);
    }

    @Test
    void previewPrint_orderScenarioDefault() {
        Map<String, Object> params = new LinkedHashMap<>();
        params.put("scenario", "ORDER");

        PrintPreviewResult result = printingService.previewPrint(1, params);

        assertNotNull(result);
        assertEquals("ORDER", result.getScenario());
        assertEquals("58mm", result.getPaperSize());
        assertEquals(58, result.getPaperWidthMm());
        assertEquals(32, result.getPaperWidthChars());
        assertEquals("老肥油边王(松源海鲜街)", result.getShopName());
        assertEquals(1, result.getTotalTickets());

        PrintPreviewResult.TicketPreviewItem ticket = result.getTickets().get(0);
        assertNotNull(ticket);
        assertTrue(ticket.getRawContent().contains("老肥油边王(松源海鲜街)"));
        assertTrue(ticket.getRawContent().contains("结账单"));
        assertTrue(ticket.getPlainText().contains("结账单"));
        assertFalse(ticket.getElements().isEmpty());
    }

    @Test
    void previewPrint_orderScenario80mm() {
        Map<String, Object> params = new LinkedHashMap<>();
        params.put("scenario", "ORDER");
        params.put("paperSize", "80mm");

        PrintPreviewResult result = printingService.previewPrint(1, params);
        assertNotNull(result);
        assertEquals("80mm", result.getPaperSize());
        assertEquals(80, result.getPaperWidthMm());
        assertEquals(48, result.getPaperWidthChars());
    }

    @Test
    void previewPrint_kitchenScenarioMock_splitsTickets() {
        mockTemplateForScenario("KITCHEN");
        Map<String, Object> params = new LinkedHashMap<>();
        params.put("scenario", "KITCHEN");

        PrintPreviewResult result = printingService.previewPrint(1, params);
        assertNotNull(result);
        assertEquals("KITCHEN", result.getScenario());
        assertTrue(result.getTotalTickets() >= 1);
        for (PrintPreviewResult.TicketPreviewItem item : result.getTickets()) {
            assertTrue(item.getRawContent().contains("厨房小票") || item.getRawContent().contains("后厨"));
            assertFalse(item.getElements().isEmpty());
        }
    }

    @Test
    void previewPrint_serveScenarioMock() {
        mockTemplateForScenario("EXPEDITE");
        Map<String, Object> params = new LinkedHashMap<>();
        params.put("scenario", "EXPEDITE");
        params.put("serveQty", 3);

        PrintPreviewResult result = printingService.previewPrint(1, params);
        assertNotNull(result);
        assertEquals("EXPEDITE", result.getScenario());
        assertEquals(1, result.getTotalTickets());
        assertTrue(result.getTickets().get(0).getRawContent().contains("传菜单") || result.getTickets().get(0).getRawContent().contains("传菜"));
    }

    @Test
    void previewPrint_refundScenarioMock() {
        mockTemplateForScenario("REFUND");
        Map<String, Object> params = new LinkedHashMap<>();
        params.put("scenario", "REFUND");

        PrintPreviewResult result = printingService.previewPrint(1, params);
        assertNotNull(result);
        assertEquals("REFUND", result.getScenario());
        assertEquals(1, result.getTotalTickets());
        assertTrue(result.getTickets().get(0).getRawContent().contains("退款"));
    }

    @Test
    void previewPrint_shiftScenarioMock() {
        mockTemplateForScenario("SHIFT");
        Map<String, Object> params = new LinkedHashMap<>();
        params.put("scenario", "SHIFT");

        PrintPreviewResult result = printingService.previewPrint(1, params);
        assertNotNull(result);
        assertEquals("SHIFT", result.getScenario());
        assertEquals(1, result.getTotalTickets());
        assertTrue(result.getTickets().get(0).getRawContent().contains("交接班"));
    }

    @Test
    void previewPrint_labelScenarioMock() {
        mockTemplateForScenario("LABEL");
        Map<String, Object> params = new LinkedHashMap<>();
        params.put("scenario", "LABEL");

        PrintPreviewResult result = printingService.previewPrint(1, params);
        assertNotNull(result);
        assertEquals("LABEL", result.getScenario());
        assertEquals(1, result.getTotalTickets());
    }

    @Test
    void previewPrint_testScenarioMock() {
        mockTemplateForScenario("TEST");
        Map<String, Object> params = new LinkedHashMap<>();
        params.put("scenario", "TEST");
        params.put("testType", "STANDARD_RECEIPT");

        PrintPreviewResult result = printingService.previewPrint(1, params);
        assertNotNull(result);
        assertEquals("TEST", result.getScenario());
        assertEquals(1, result.getTotalTickets());
        assertTrue(result.getTickets().get(0).getRawContent().contains("打印测试单"));
    }

    @Test
    void previewPrint_whenTemplateMissing_throwsApiException() {
        when(templateMapper.selectOne(any())).thenReturn(null); // DB 找不到模板
        Map<String, Object> params = new LinkedHashMap<>();
        params.put("scenario", "CUSTOM_SCENARIO");

        ApiException ex = assertThrows(ApiException.class, () -> printingService.previewPrint(1, params));
        assertEquals(404, ex.getHttpStatus());
        assertEquals("PRINTING_TEMPLATE_NOT_FOUND", ex.getErrorCode());
        assertTrue(ex.getMessage().contains("未配置小票打印模板"));
    }

    @Test
    void previewPrint_customContent() {
        Map<String, Object> params = new LinkedHashMap<>();
        params.put("customContent", "<CB>自定义测试小票</CB><BR>测试内容行<BR>");

        PrintPreviewResult result = printingService.previewPrint(1, params);
        assertNotNull(result);
        assertEquals(1, result.getTotalTickets());
        assertEquals("<CB>自定义测试小票</CB><BR>测试内容行<BR>", result.getTickets().get(0).getRawContent());
        assertEquals("自定义测试小票\n测试内容行\n", result.getTickets().get(0).getPlainText());
    }

    @Test
    void previewPrint_withRealOrder() {
        Order order = new Order();
        order.setId(10086);
        order.setShop_id(1);
        order.setOrder_no("DD202608319999");
        order.setTable_number("VIP 1包厢");
        order.setSett_amount(388.00);
        order.setTransac_status("success");
        order.setOrder_time(new Date());

        OrderDetail d = new OrderDetail();
        d.setId(8801);
        d.setMId(10086);
        d.setName("极品牛肋条(斤)");
        d.setQuantity("2");
        d.setTotal_price(256.00);

        when(orderService.getById(10086)).thenReturn(order);
        when(orderDetailService.list(any())).thenReturn(Collections.singletonList(d));

        Map<String, Object> params = new LinkedHashMap<>();
        params.put("scenario", "ORDER");
        params.put("orderId", 10086);

        PrintPreviewResult result = printingService.previewPrint(1, params);
        assertNotNull(result);
        assertTrue(result.getTickets().get(0).getRawContent().contains("VIP 1包厢"));
        assertTrue(result.getTickets().get(0).getRawContent().contains("极品牛肋")); // 菜品名统一 4 字以内
    }
    @Test
    void previewPrint_realOrderWithoutDetails_returns409() {
        Order order = new Order();
        order.setId(20001);
        order.setShop_id(1);
        order.setOrder_no("DD202609010001");
        order.setTable_number("A09");
        order.setSett_amount(66.0);
        order.setTransac_status("success");
        order.setOrder_time(new Date());
        when(orderService.getById(20001)).thenReturn(order);
        when(orderDetailService.list(any())).thenReturn(Collections.emptyList());

        Map<String, Object> params = new LinkedHashMap<>();
        params.put("scenario", "ORDER");
        params.put("orderId", 20001);

        ApiException ex = assertThrows(ApiException.class, () -> printingService.previewPrint(1, params));
        assertEquals(409, ex.getHttpStatus());
        assertEquals("PRINTING_PREVIEW_ORDER_DETAILS_REQUIRED", ex.getErrorCode());
    }

    @Test
    void previewPrint_designerAndExact_shareAssembler() {
        Order order = new Order();
        order.setId(30001);
        order.setShop_id(1);
        order.setOrder_no("DD202609020002");
        order.setTable_number("A10");
        order.setSett_amount(48.0);
        order.setDiscount_amount(0.0);
        order.setTransac_status("success");
        order.setOrder_time(new Date());
        OrderDetail d = new OrderDetail();
        d.setId(9001);
        d.setMId(30001);
        d.setName("炭烤羊腰子");
        d.setQuantity("1");
        d.setTotal_price(48.0);
        when(orderService.getById(30001)).thenReturn(order);
        when(orderDetailService.list(any())).thenReturn(Collections.singletonList(d));

        Map<String, Object> params = new LinkedHashMap<>();
        params.put("scenario", "ORDER");
        params.put("orderId", 30001);
        String designerCombined = printingService.previewPrint(1, params).getRawCombinedContent();
        String exactCombined = printingService.previewExact(1, params).getRawCombinedContent();
        assertTrue(designerCombined.contains("炭烤羊腰")); // 菜品名统一 4 字以内
        assertEquals(exactCombined, designerCombined);
    }
}

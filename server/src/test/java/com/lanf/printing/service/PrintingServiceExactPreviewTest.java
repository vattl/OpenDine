package com.lanf.printing.service;

import com.lanf.common.ApiException;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.Shift;
import com.lanf.printing.model.PrintContext;
import com.lanf.printing.model.PrintPreviewResult;
import com.lanf.printing.model.PrintResolvedPreview;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShiftService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * D002 精确打印预览一致性 — 服务层严格真实上下文回归测试。
 *
 * <p>验收线：精确预览只接受真实订单/班次/明细/退款上下文；拒绝样例回退与任何人工
 * 业务数据覆盖（customContent/templateDsl/templateJson/templateId/statistics/refundInfo/
 * contextOverrides/TEST）；每张票据携带可追溯的 ruleId/deviceId/deviceName/templateId/
 * templateCode 票源元数据。
 */
class PrintingServiceExactPreviewTest {

    private PrintingService service;
    private IOrderService orderService;
    private IOrderDetailService orderDetailService;
    private IShiftService shiftService;
    private PrintDispatcherService dispatcher;

    @BeforeEach
    void setUp() {
        orderService = mock(IOrderService.class);
        orderDetailService = mock(IOrderDetailService.class);
        shiftService = mock(IShiftService.class);
        dispatcher = mock(PrintDispatcherService.class);

        service = new PrintingService();
        ReflectionTestUtils.setField(service, "orderService", orderService);
        ReflectionTestUtils.setField(service, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(service, "shiftService", shiftService);
        ReflectionTestUtils.setField(service, "printDispatcherService", dispatcher);
    }

    private static Map<String, Object> params(String scenario, Integer orderId) {
        Map<String, Object> p = new LinkedHashMap<>();
        p.put("scenario", scenario);
        if (orderId != null) {
            p.put("orderId", orderId);
        }
        return p;
    }

    private static Order orderWithDetail(int id, int shopId, Double refundAmount) {
        Order order = new Order();
        order.setId(id);
        order.setShop_id(shopId);
        order.setTransac_status("success");
        order.setRefund_amount(refundAmount);
        OrderDetail detail = new OrderDetail();
        detail.setId(5);
        List<OrderDetail> details = new ArrayList<>();
        details.add(detail);
        order.setGoods_list(details);
        return order;
    }

    private static PrintResolvedPreview preview(long ruleId, long deviceId, String deviceName, String templateCode, String raw) {
        PrintResolvedPreview p = new PrintResolvedPreview();
        p.setRuleId(ruleId);
        p.setDeviceId(deviceId);
        p.setDeviceName(deviceName);
        p.setTemplateId(101L);
        p.setTemplateCode(templateCode);
        p.setContents(Collections.singletonList(raw));
        return p;
    }

    @Test
    void exactPreviewRejectsAllMockOrArbitraryBusinessOverrides() {
        Map<String, Object> base = params("ORDER", 100);
        for (String forbidden : Arrays.asList("customContent", "templateDsl", "templateJson",
                "templateId", "statistics", "refundInfo", "contextOverrides")) {
            Map<String, Object> p = new LinkedHashMap<>(base);
            p.put(forbidden, "anything");
            ApiException ex = assertThrows(ApiException.class, () -> service.previewExact(1, p));
            assertEquals(400, ex.getHttpStatus(), forbidden);
            assertEquals("PRINTING_EXACT_OVERRIDE_FORBIDDEN", ex.getErrorCode(), forbidden);
        }
        // TEST 场景也不允许走精确预览（属于样例自检）
        ApiException ex = assertThrows(ApiException.class, () -> service.previewExact(1, params("TEST", 100)));
        assertEquals("PRINTING_EXACT_OVERRIDE_FORBIDDEN", ex.getErrorCode());
        verify(dispatcher, never()).previewExact(anyInt(), anyString(), any(), any(), any());
    }

    @Test
    void exactPreviewRequiresRealOrderForNonShiftScenario() {
        ApiException ex = assertThrows(ApiException.class, () -> service.previewExact(1, params("ORDER", null)));
        assertEquals(400, ex.getHttpStatus());
        assertEquals("PRINTING_EXACT_ORDER_REQUIRED", ex.getErrorCode());
    }

    @Test
    void exactPreviewRequiresRealShiftForShiftScenario() {
        ApiException ex = assertThrows(ApiException.class, () -> service.previewExact(1, params("SHIFT", null)));
        assertEquals(400, ex.getHttpStatus());
        assertEquals("PRINTING_EXACT_SHIFT_REQUIRED", ex.getErrorCode());
    }

    @Test
    void exactPreviewRejectsOrderOfAnotherShop() {
        Order foreign = new Order();
        foreign.setId(100);
        foreign.setShop_id(2);
        foreign.setTransac_status("success");
        when(orderService.getById(100)).thenReturn(foreign);
        ApiException ex = assertThrows(ApiException.class, () -> service.previewExact(1, params("ORDER", 100)));
        assertEquals(403, ex.getHttpStatus());
        assertEquals("ORDER_FORBIDDEN", ex.getErrorCode());
    }

    @Test
    void exactPreviewRequiresRealOrderDetails() {
        Order order = new Order();
        order.setId(100);
        order.setShop_id(1);
        order.setTransac_status("success");
        when(orderService.getById(100)).thenReturn(order);
        when(orderDetailService.list(any())).thenReturn(Collections.emptyList());
        ApiException ex = assertThrows(ApiException.class, () -> service.previewExact(1, params("ORDER", 100)));
        assertEquals(409, ex.getHttpStatus());
        assertEquals("PRINTING_EXACT_ORDER_DETAILS_REQUIRED", ex.getErrorCode());
    }

    @Test
    void exactPreviewExpediteRequiresRealDetailAndServeQty() {
        Order order = orderWithDetail(100, 1, null);
        when(orderService.getById(100)).thenReturn(order);
        when(orderDetailService.list(any())).thenReturn(order.getGoods_list());

        // 缺 detailId
        ApiException noDetail = assertThrows(ApiException.class, () -> service.previewExact(1, params("EXPEDITE", 100)));
        assertEquals(400, noDetail.getHttpStatus());
        assertEquals("PRINTING_EXACT_DETAIL_REQUIRED", noDetail.getErrorCode());

        // detailId 不属于该订单
        Map<String, Object> foreignDetail = params("EXPEDITE", 100);
        foreignDetail.put("detailId", 999);
        ApiException notFound = assertThrows(ApiException.class, () -> service.previewExact(1, foreignDetail));
        assertEquals(404, notFound.getHttpStatus());
        assertEquals("PRINTING_EXACT_DETAIL_NOT_FOUND", notFound.getErrorCode());

        // 缺 serveQty
        Map<String, Object> noQty = params("EXPEDITE", 100);
        noQty.put("detailId", 5);
        ApiException noServe = assertThrows(ApiException.class, () -> service.previewExact(1, noQty));
        assertEquals(400, noServe.getHttpStatus());
        assertEquals("PRINTING_EXACT_SERVE_QTY_INVALID", noServe.getErrorCode());

        // serveQty 非法
        Map<String, Object> badQty = params("EXPEDITE", 100);
        badQty.put("detailId", 5);
        badQty.put("serveQty", 0);
        ApiException badServe = assertThrows(ApiException.class, () -> service.previewExact(1, badQty));
        assertEquals("PRINTING_EXACT_SERVE_QTY_INVALID", badServe.getErrorCode());
    }

    @Test
    void exactPreviewRefundRequiresRealRefundData() {
        Order order = orderWithDetail(100, 1, 0d); // 无真实退款金额
        when(orderService.getById(100)).thenReturn(order);
        when(orderDetailService.list(any())).thenReturn(order.getGoods_list());
        ApiException ex = assertThrows(ApiException.class, () -> service.previewExact(1, params("REFUND", 100)));
        assertEquals(409, ex.getHttpStatus());
        assertEquals("PRINTING_EXACT_REFUND_REQUIRED", ex.getErrorCode());
    }

    @Test
    void exactPreviewOrderHappyPathResolvesRealContextAndSourceMetadata() {
        Order order = orderWithDetail(100, 1, null);
        when(orderService.getById(100)).thenReturn(order);
        when(orderDetailService.list(any())).thenReturn(order.getGoods_list());
        String raw = "<CB>结账单</CB>\n<CUT>";
        when(dispatcher.previewExact(eq(1), eq("CHECKOUT"), any(), isNull(), isNull()))
                .thenReturn(Collections.singletonList(preview(7L, 10L, "前台小票机", "tmpl_checkout", raw)));

        PrintPreviewResult result = service.previewExact(1, params("ORDER", 100));

        assertEquals("checkout", result.getScenario(), "成功订单归一为结账单规范码");
        assertEquals("结账单", result.getScenarioName());
        assertEquals(1, result.getTotalTickets());
        PrintPreviewResult.TicketPreviewItem ticket = result.getTickets().get(0);
        assertEquals(raw, ticket.getRawContent());
        assertEquals(raw, result.getRawCombinedContent());
        assertEquals(7L, ticket.getRuleId());
        assertEquals(10L, ticket.getDeviceId());
        assertEquals("前台小票机", ticket.getDeviceName());
        assertEquals(101L, ticket.getTemplateId());
        assertEquals("tmpl_checkout", ticket.getTemplateCode());

        ArgumentCaptor<PrintContext> ctxCaptor = ArgumentCaptor.forClass(PrintContext.class);
        verify(dispatcher).previewExact(eq(1), eq("CHECKOUT"), ctxCaptor.capture(), isNull(), isNull());
        assertSame(order, ctxCaptor.getValue().getOrder());
        assertFalse(ctxCaptor.getValue().isAddDishes());
    }

    @Test
    void exactPreviewForwardsOptionalRuleAndDeviceFilters() {
        Order order = orderWithDetail(100, 1, null);
        when(orderService.getById(100)).thenReturn(order);
        when(orderDetailService.list(any())).thenReturn(order.getGoods_list());
        when(dispatcher.previewExact(eq(1), eq("CHECKOUT"), any(), eq(7L), eq(10L)))
                .thenReturn(Collections.singletonList(preview(7L, 10L, "前台小票机", "tmpl_checkout", "<CB>x</CB>")));

        Map<String, Object> p = params("ORDER", 100);
        p.put("ruleId", 7L);
        p.put("deviceId", 10L);
        PrintPreviewResult result = service.previewExact(1, p);

        assertEquals(1, result.getTotalTickets());
        assertEquals(7L, result.getTickets().get(0).getRuleId());
        verify(dispatcher).previewExact(eq(1), eq("CHECKOUT"), any(), eq(7L), eq(10L));
    }

    @Test
    void exactPreviewShiftHappyPathResolvesRealShiftContext() {
        Shift shift = new Shift();
        shift.setId(88L);
        shift.setShop_id(1);
        shift.setOrder_count(12);
        shift.setTotal_amount(BigDecimal.valueOf(888.00));
        when(shiftService.getById(88L)).thenReturn(shift);
        when(dispatcher.previewExact(eq(1), eq("SHIFT"), any(), isNull(), isNull()))
                .thenReturn(Collections.singletonList(preview(9L, 11L, "前台小票机", "tmpl_shift", "<CB>交接班报表</CB>")));

        Map<String, Object> p = new LinkedHashMap<>();
        p.put("scenario", "SHIFT");
        p.put("shiftId", 88L);

        PrintPreviewResult result = service.previewExact(1, p);

        assertEquals("shift", result.getScenario());
        assertEquals(1, result.getTotalTickets());
        ArgumentCaptor<PrintContext> ctxCaptor = ArgumentCaptor.forClass(PrintContext.class);
        verify(dispatcher).previewExact(eq(1), eq("SHIFT"), ctxCaptor.capture(), isNull(), isNull());
        assertSame(shift, ctxCaptor.getValue().getShift());
        assertEquals(12, ctxCaptor.getValue().getExtra().get("orderCount"));
    }

    @Test
    void exactPreviewShiftNotBelongingToShopRejected() {
        Shift shift = new Shift();
        shift.setId(88L);
        shift.setShop_id(2);
        when(shiftService.getById(88L)).thenReturn(shift);
        Map<String, Object> p = new LinkedHashMap<>();
        p.put("scenario", "SHIFT");
        p.put("shiftId", 88L);
        ApiException ex = assertThrows(ApiException.class, () -> service.previewExact(1, p));
        assertEquals(403, ex.getHttpStatus());
        assertEquals("SHIFT_FORBIDDEN", ex.getErrorCode());
    }
}

package com.lanf.kds.service;

import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.printing.model.PrintDispatchResult;
import com.lanf.printing.service.PrintDispatcherService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.jdbc.core.JdbcTemplate;

import java.lang.reflect.Method;
import java.util.Collections;
import java.util.List;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.never;

class KdsServePrintServiceTest {

    @Test
    void mergeQuantitiesCombinesSameDetail() throws Exception {
        Method m = KdsServePrintService.class.getDeclaredMethod("mergeQuantities", List.class);
        m.setAccessible(true);
        @SuppressWarnings("unchecked")
        java.util.Map<Integer, Integer> merged = (java.util.Map<Integer, Integer>) m.invoke(null,
                java.util.Arrays.asList(
                        new KdsServePrintService.ServeLine(10, 2),
                        new KdsServePrintService.ServeLine(10, 1),
                        new KdsServePrintService.ServeLine(11, 3)
                ));
        assertEquals(3, merged.get(10));
        assertEquals(3, merged.get(11));
    }

    @Test
    void manualPrintPropagatesPrinterFailureInsteadOfReportingSuccess() throws Exception {
        KdsServePrintService service = new KdsServePrintService();
        IOrderService orders = mock(IOrderService.class);
        IOrderDetailService details = mock(IOrderDetailService.class);
        PrintDispatcherService dispatcher = mock(PrintDispatcherService.class);
        ReflectionTestUtils.setField(service, "orderService", orders);
        ReflectionTestUtils.setField(service, "orderDetailService", details);
        ReflectionTestUtils.setField(service, "printDispatcherService", dispatcher);

        OrderDetail detail = new OrderDetail();
        detail.setId(21);
        detail.setMId(31);
        detail.setName("油边王");
        Order order = new Order();
        order.setId(31);
        order.setShop_id(7);
        order.setTable_number("A01");
        when(details.getById(21)).thenReturn(detail);
        when(orders.getById(31)).thenReturn(order);
        when(dispatcher.dispatch(anyInt(), anyString(), any()))
                .thenReturn(Collections.singletonList(PrintDispatchResult.failed(101, "printer offline")));

        assertThrows(IllegalStateException.class, () -> service.printManual(
                7, null, null, null,
                Collections.singletonList(Collections.<String, Object>singletonMap("detail_id", 21))));
    }

    @Test
    void automaticPrintPersistsAndDeduplicatesTheSameServedTotal() throws Exception {
        KdsServePrintService service = new KdsServePrintService();
        IOrderService orders = mock(IOrderService.class);
        IOrderDetailService details = mock(IOrderDetailService.class);
        PrintDispatcherService dispatcher = mock(PrintDispatcherService.class);
        KdsConfigService config = mock(KdsConfigService.class);
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        ReflectionTestUtils.setField(service, "orderService", orders);
        ReflectionTestUtils.setField(service, "orderDetailService", details);
        ReflectionTestUtils.setField(service, "printDispatcherService", dispatcher);
        ReflectionTestUtils.setField(service, "configService", config);
        ReflectionTestUtils.setField(service, "jdbc", jdbc);

        OrderDetail detail = new OrderDetail();
        detail.setId(21);
        detail.setMId(31);
        detail.setName("油边王");
        Order order = new Order();
        order.setId(31);
        order.setShop_id(7);
        order.setTable_number("A01");
        Map<String, Object> job = new HashMap<>();
        job.put("shop_id", 7);
        job.put("detail_id", 21);
        job.put("quantity", 1);
        when(config.isServePrintEnabled(7)).thenReturn(true);
        when(jdbc.update(org.mockito.ArgumentMatchers.startsWith("UPDATE t_kds_serve_print_job SET status='PROCESSING'"),
                org.mockito.ArgumentMatchers.<Object>any())).thenReturn(1, 0);
        when(jdbc.queryForMap(any(), org.mockito.ArgumentMatchers.<Object>any())).thenReturn(job);
        when(details.getById(21)).thenReturn(detail);
        when(orders.getById(31)).thenReturn(order);
        when(dispatcher.dispatch(anyInt(), anyString(), any()))
                .thenReturn(Collections.singletonList(PrintDispatchResult.sent(101, 501)));

        service.printDetailLine(7, 21, 1, 1);
        service.printDetailLine(7, 21, 1, 1);

        verify(dispatcher, times(1)).dispatch(anyInt(), anyString(), any());
    }

    @Test
    void manualPrintThrowsWhenServePrintDisabledInKdsConfig() {
        KdsServePrintService service = new KdsServePrintService();
        KdsConfigService config = mock(KdsConfigService.class);
        ReflectionTestUtils.setField(service, "configService", config);
        when(config.isServePrintEnabled(7)).thenReturn(false);

        IllegalStateException ex = assertThrows(IllegalStateException.class, () -> service.printManual(
                7, null, 21, 1, null));
        assertEquals("当前门店待传菜打印功能未启用(serve_print_enabled=0)", ex.getMessage());
    }

    @Test
    void automaticPrintMarksJobSkippedWhenNoRulesMatchedWithoutInfiniteRetry() throws Exception {
        KdsServePrintService service = new KdsServePrintService();
        IOrderService orders = mock(IOrderService.class);
        IOrderDetailService details = mock(IOrderDetailService.class);
        PrintDispatcherService dispatcher = mock(PrintDispatcherService.class);
        KdsConfigService config = mock(KdsConfigService.class);
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        ReflectionTestUtils.setField(service, "orderService", orders);
        ReflectionTestUtils.setField(service, "orderDetailService", details);
        ReflectionTestUtils.setField(service, "printDispatcherService", dispatcher);
        ReflectionTestUtils.setField(service, "configService", config);
        ReflectionTestUtils.setField(service, "jdbc", jdbc);

        OrderDetail detail = new OrderDetail();
        detail.setId(21);
        detail.setMId(31);
        detail.setName("油边王");
        Order order = new Order();
        order.setId(31);
        order.setShop_id(7);
        order.setTable_number("A01");
        Map<String, Object> job = new HashMap<>();
        job.put("shop_id", 7);
        job.put("detail_id", 21);
        job.put("quantity", 1);
        when(config.isServePrintEnabled(7)).thenReturn(true);
        when(jdbc.update(org.mockito.ArgumentMatchers.startsWith("UPDATE t_kds_serve_print_job SET status='PROCESSING'"),
                org.mockito.ArgumentMatchers.<Object>any())).thenReturn(1, 0);
        when(jdbc.queryForMap(any(), org.mockito.ArgumentMatchers.<Object>any())).thenReturn(job);
        when(details.getById(21)).thenReturn(detail);
        when(orders.getById(31)).thenReturn(order);
        // 关键断言点：调度引擎返回空列表（代表无规则或已被禁用出票）
        when(dispatcher.dispatch(anyInt(), anyString(), any())).thenReturn(Collections.emptyList());

        service.printDetailLine(7, 21, 1, 1);

        // 验证执行了 SKIPPED 状态标记，而不是进入 RETRY
        verify(jdbc).update(org.mockito.ArgumentMatchers.contains("status='SKIPPED'"),
                eq("未配置生效的传菜出票规则或已被禁用，跳过出票"), any());
        verify(jdbc, never()).update(org.mockito.ArgumentMatchers.contains("status='RETRY'"),
                any(), any());
    }
}

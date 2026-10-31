package com.lanf.printing.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.common.ApiException;
import com.lanf.entity.Admin;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.Shift;
import com.lanf.printing.entity.PrintingDevice;
import com.lanf.printing.mapper.PrintingDeviceMapper;
import com.lanf.printing.model.PrintContext;
import com.lanf.printing.model.PrintDispatchResult;
import com.lanf.printing.model.PrintScenario;
import com.lanf.printing.model.UnifiedPrintRequest;
import com.lanf.printing.model.UnifiedPrintResponse;
import com.lanf.printing.service.impl.UnifiedPrintServiceImpl;
import com.lanf.service.IAdminService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShiftService;
import com.lanf.service.ITakeoutDeliveryService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

class UnifiedPrintServiceTest {

    private UnifiedPrintServiceImpl service;
    private IOrderService orderService;
    private IOrderDetailService orderDetailService;
    private IShiftService shiftService;
    private IAdminService adminService;
    private ITakeoutDeliveryService takeoutDeliveryService;
    private PrintDispatcherService printDispatcherService;
    private PrintingDeviceMapper deviceMapper;

    @BeforeEach
    void setUp() {
        orderService = mock(IOrderService.class);
        orderDetailService = mock(IOrderDetailService.class);
        shiftService = mock(IShiftService.class);
        adminService = mock(IAdminService.class);
        takeoutDeliveryService = mock(ITakeoutDeliveryService.class);
        printDispatcherService = mock(PrintDispatcherService.class);
        deviceMapper = mock(PrintingDeviceMapper.class);

        service = new UnifiedPrintServiceImpl();
        ReflectionTestUtils.setField(service, "orderService", orderService);
        ReflectionTestUtils.setField(service, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(service, "shiftService", shiftService);
        ReflectionTestUtils.setField(service, "adminService", adminService);
        ReflectionTestUtils.setField(service, "takeoutDeliveryService", takeoutDeliveryService);
        ReflectionTestUtils.setField(service, "printDispatcherService", printDispatcherService);
        ReflectionTestUtils.setField(service, "deviceMapper", deviceMapper);
    }

    private Order createSampleOrder(Integer id, String orderNo, Integer shopId) {
        Order o = new Order();
        o.setId(id);
        o.setOrder_no(orderNo);
        o.setShop_id(shopId);
        o.setTable_number("A08");
        o.setDineInOrTakeOut("堂食");
        o.setOrder_time(new Date());
        o.setTransac_status("success");
        o.setSett_amount(88.0);
        return o;
    }

    private OrderDetail createSampleDetail(Integer id, Integer orderId, String cid, String name) {
        OrderDetail d = new OrderDetail();
        d.setId(id);
        d.setMId(orderId);
        d.setCid(cid);
        d.setName(name);
        d.setQuantity("2");
        d.setTotal_price(30.0);
        d.setLine_status("NORMAL");
        return d;
    }

    @Test
    void testDispatch_KitchenReprint_OnlyOrderNo() {
        Order order = createSampleOrder(101, "ORDER_20261005_001", 1);
        when(orderService.getOne(any())).thenReturn(order);

        OrderDetail d1 = createSampleDetail(1, 101, "1", "烤牛油");
        when(orderDetailService.list(any())).thenReturn(Collections.singletonList(d1));

        Admin admin = new Admin();
        admin.setId(10);
        admin.setRealName("张店长");
        when(adminService.getById(10)).thenReturn(admin);

        PrintDispatchResult dispatchResult = new PrintDispatchResult();
        dispatchResult.setJobId(1001L);
        dispatchResult.setDeviceId(5L);
        dispatchResult.setDeviceName("后厨打印机");
        dispatchResult.setTransport("CLOUD");
        dispatchResult.setStatus("SENT");
        dispatchResult.setSuccess(true);
        when(printDispatcherService.dispatch(eq(1), eq(PrintScenario.KITCHEN), any(PrintContext.class)))
                .thenReturn(Collections.singletonList(dispatchResult));

        UnifiedPrintRequest req = UnifiedPrintRequest.builder()
                .orderNo("ORDER_20261005_001")
                .build();

        UnifiedPrintResponse response = service.dispatch(req, 10, 1);

        assertNotNull(response);
        assertEquals("ORDER_20261005_001", response.getOrderNo());
        assertEquals("kitchen", response.getScenario());
        assertEquals("厨房小票", response.getScenarioName());
        assertTrue(response.isReprint());
        assertEquals(1, response.getJobCount());
        assertEquals(1, response.getSuccessCount());
        assertEquals(0, response.getFailedCount());
        assertEquals("成功下发 1 个打印任务", response.getSummary());

        ArgumentCaptor<PrintContext> captor = ArgumentCaptor.forClass(PrintContext.class);
        verify(printDispatcherService).dispatch(eq(1), eq(PrintScenario.KITCHEN), captor.capture());
        PrintContext ctx = captor.getValue();
        assertEquals(order, ctx.getOrder());
        assertEquals(1, ctx.getOrder().getGoods_list().size());
        assertEquals("【补打】", ctx.getExtra().get("reprint_badge"));
        assertEquals("张店长", ctx.getExtra().get("reprint_operator"));
        assertNotNull(ctx.getExtra().get("reprint_time"));
    }

    @Test
    void testDispatch_WithCidList() {
        Order order = createSampleOrder(102, "ORDER_20261005_002", 1);
        when(orderService.getOne(any())).thenReturn(order);

        when(printDispatcherService.dispatch(anyInt(), anyString(), any(PrintContext.class)))
                .thenReturn(Collections.emptyList());

        UnifiedPrintRequest req = UnifiedPrintRequest.builder()
                .orderNo("ORDER_20261005_002")
                .cidList(Arrays.asList("1", "3"))
                .build();

        service.dispatch(req, null, 1);

        ArgumentCaptor<PrintContext> captor = ArgumentCaptor.forClass(PrintContext.class);
        verify(printDispatcherService).dispatch(eq(1), eq(PrintScenario.KITCHEN), captor.capture());
        PrintContext ctx = captor.getValue();
        assertNotNull(ctx.getCidFilter());
        assertTrue(ctx.getCidFilter().contains("1"));
        assertTrue(ctx.getCidFilter().contains("3"));
    }

    @Test
    void testDispatch_ExplicitCheckoutScenario_NotReprint() {
        Order order = createSampleOrder(103, "ORDER_20261005_003", 1);
        when(orderService.getOne(any())).thenReturn(order);

        when(printDispatcherService.dispatch(anyInt(), anyString(), any(PrintContext.class)))
                .thenReturn(Collections.emptyList());

        UnifiedPrintRequest req = UnifiedPrintRequest.builder()
                .orderNo("ORDER_20261005_003")
                .scenario("checkout")
                .isReprint(false)
                .build();

        UnifiedPrintResponse response = service.dispatch(req, null, 1);

        assertEquals("checkout", response.getScenario());
        assertEquals("结账单", response.getScenarioName());
        assertFalse(response.isReprint());

        ArgumentCaptor<PrintContext> captor = ArgumentCaptor.forClass(PrintContext.class);
        verify(printDispatcherService).dispatch(eq(1), eq(PrintScenario.CHECKOUT), captor.capture());
        PrintContext ctx = captor.getValue();
        assertNull(ctx.getExtra().get("reprint_badge"));
    }

    @Test
    void testDispatch_ShiftScenario() {
        Shift shift = new Shift();
        shift.setId(55L);
        shift.setShop_id(1);
        shift.setOrder_count(42);
        shift.setTotal_amount(new BigDecimal("3500.00"));
        when(shiftService.getById(55L)).thenReturn(shift);

        when(printDispatcherService.dispatch(anyInt(), anyString(), any(PrintContext.class)))
                .thenReturn(Collections.emptyList());

        UnifiedPrintRequest req = UnifiedPrintRequest.builder()
                .scenario("shift")
                .shiftId(55L)
                .build();

        UnifiedPrintResponse response = service.dispatch(req, null, 1);

        assertEquals("shift", response.getScenario());
        assertEquals("收银交接班报表", response.getScenarioName());

        ArgumentCaptor<PrintContext> captor = ArgumentCaptor.forClass(PrintContext.class);
        verify(printDispatcherService).dispatch(eq(1), eq(PrintScenario.SHIFT), captor.capture());
        PrintContext ctx = captor.getValue();
        assertEquals(shift, ctx.getShift());
        assertEquals(42, ctx.getExtra().get("orderCount"));
    }

    @Test
    void testDispatch_DeviceOverride() {
        Order order = createSampleOrder(104, "ORDER_20261005_004", 1);
        when(orderService.getOne(any())).thenReturn(order);

        PrintingDevice dev = new PrintingDevice();
        dev.setId(88L);
        dev.setShop_id(1);
        dev.setName("测试出票机");
        when(deviceMapper.selectById(88L)).thenReturn(dev);

        when(printDispatcherService.dispatch(anyInt(), anyString(), any(PrintContext.class)))
                .thenReturn(Collections.emptyList());

        UnifiedPrintRequest req = UnifiedPrintRequest.builder()
                .orderNo("ORDER_20261005_004")
                .deviceId(88L)
                .templateId(303L)
                .copies(2)
                .build();

        service.dispatch(req, null, 1);

        ArgumentCaptor<PrintContext> captor = ArgumentCaptor.forClass(PrintContext.class);
        verify(printDispatcherService).dispatch(eq(1), eq(PrintScenario.KITCHEN), captor.capture());
        PrintContext ctx = captor.getValue();
        assertEquals(88L, ctx.getExtra().get("target_device_id"));
        assertEquals(303L, ctx.getExtra().get("template_id_override"));
        assertEquals(2, ctx.getExtra().get("copies_override"));
    }

    @Test
    void testDispatch_OrderNotFound_Throws404() {
        when(orderService.getOne(any())).thenReturn(null);

        UnifiedPrintRequest req = UnifiedPrintRequest.builder()
                .orderNo("ORDER_NOT_FOUND")
                .build();

        ApiException ex = assertThrows(ApiException.class, () -> service.dispatch(req, null, 1));
        assertEquals(404, ex.getHttpStatus());
        assertEquals("ORDER_NOT_FOUND", ex.getErrorCode());
    }

    @Test
    void testDispatch_ShopScopeMismatch_Throws403() {
        Order foreignOrder = createSampleOrder(105, "ORDER_FOREIGN", 2);
        when(orderService.getOne(any())).thenReturn(foreignOrder);

        UnifiedPrintRequest req = UnifiedPrintRequest.builder()
                .orderNo("ORDER_FOREIGN")
                .build();

        ApiException ex = assertThrows(ApiException.class, () -> service.dispatch(req, null, 1));
        assertEquals(403, ex.getHttpStatus());
        assertEquals("SHOP_SCOPE_MISMATCH", ex.getErrorCode());
    }

    @Test
    void testDispatch_CustomContent() {
        when(printDispatcherService.dispatch(anyInt(), anyString(), any(PrintContext.class)))
                .thenReturn(Collections.emptyList());

        UnifiedPrintRequest req = UnifiedPrintRequest.builder()
                .customContent("自定义出票文本")
                .build();

        UnifiedPrintResponse resp = service.dispatch(req, null, 1);
        assertEquals("checkout", resp.getScenario());

        ArgumentCaptor<PrintContext> captor = ArgumentCaptor.forClass(PrintContext.class);
        verify(printDispatcherService).dispatch(eq(1), eq(PrintScenario.CHECKOUT), captor.capture());
        PrintContext ctx = captor.getValue();
        assertEquals("自定义出票文本", ctx.getCustomContent());
    }

    @Test
    void testDispatch_CheckoutUnsettledOrder_ThrowsException() {
        Order unsettledOrder = createSampleOrder(106, "ORDER_UNSETTLED", 1);
        unsettledOrder.setTransac_status("unsettled");
        when(orderService.getOne(any())).thenReturn(unsettledOrder);

        UnifiedPrintRequest req = UnifiedPrintRequest.builder()
                .orderNo("ORDER_UNSETTLED")
                .scenario("checkout")
                .build();

        ApiException ex = assertThrows(ApiException.class, () -> service.dispatch(req, null, 1));
        assertEquals(400, ex.getHttpStatus());
        assertEquals("ORDER_NOT_CHECKED_OUT", ex.getErrorCode());
        assertEquals("订单尚未结账，不能打印结账单，未结账订单只能打印预结单", ex.getMessage());
    }

    @Test
    void testDispatch_PreCheckoutUnsettledOrder_Success() {
        Order unsettledOrder = createSampleOrder(107, "ORDER_UNSETTLED_PRE", 1);
        unsettledOrder.setTransac_status("unsettled");
        when(orderService.getOne(any())).thenReturn(unsettledOrder);

        when(printDispatcherService.dispatch(anyInt(), anyString(), any(PrintContext.class)))
                .thenReturn(Collections.emptyList());

        UnifiedPrintRequest req = UnifiedPrintRequest.builder()
                .orderNo("ORDER_UNSETTLED_PRE")
                .scenario("pre_checkout")
                .build();

        UnifiedPrintResponse resp = service.dispatch(req, null, 1);
        assertEquals("pre_checkout", resp.getScenario());
        assertEquals("预结单", resp.getScenarioName());

        ArgumentCaptor<PrintContext> captor = ArgumentCaptor.forClass(PrintContext.class);
        verify(printDispatcherService).dispatch(eq(1), eq(PrintScenario.PRE_CHECKOUT), captor.capture());
        PrintContext ctx = captor.getValue();
        assertEquals(unsettledOrder, ctx.getOrder());
    }
}

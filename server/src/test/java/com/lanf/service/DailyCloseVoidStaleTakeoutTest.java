package com.lanf.service;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.kds.service.KdsOrderHook;
import com.lanf.mapper.DailyCloseSnapshotMapper;
import com.lanf.mapper.DrawerSessionMapper;
import com.lanf.mapper.PaymentLedgerMapper;
import com.lanf.payment.service.CashierCollectionIntentService;
import com.lanf.payment.service.OrderLedgerConsistencyService;
import com.lanf.security.JwtTokenService;
import com.lanf.security.SecurityAuditService;
import com.lanf.service.impl.DailyCloseServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class DailyCloseVoidStaleTakeoutTest {

    private DailyCloseServiceImpl service;
    private IOrderService orderService;
    private IShopService shopService;
    private DrawerSessionMapper drawerSessionMapper;
    private PaymentLedgerMapper paymentLedgerMapper;
    private DailyCloseSnapshotMapper snapshotMapper;
    private IDishShopStockService dishShopStockService;
    private IOrderDetailService orderDetailService;
    private KdsOrderHook kdsOrderHook;
    private ITakeoutDeliveryService takeoutDeliveryService;
    private CashierCollectionIntentService collectionIntentService;
    private SecurityAuditService securityAuditService;

    private Shop shop;

    @BeforeEach
    void setUp() {
        service = new DailyCloseServiceImpl();
        orderService = mock(IOrderService.class);
        shopService = mock(IShopService.class);
        drawerSessionMapper = mock(DrawerSessionMapper.class);
        paymentLedgerMapper = mock(PaymentLedgerMapper.class);
        snapshotMapper = mock(DailyCloseSnapshotMapper.class);
        dishShopStockService = mock(IDishShopStockService.class);
        orderDetailService = mock(IOrderDetailService.class);
        kdsOrderHook = mock(KdsOrderHook.class);
        takeoutDeliveryService = mock(ITakeoutDeliveryService.class);
        collectionIntentService = mock(CashierCollectionIntentService.class);
        securityAuditService = mock(SecurityAuditService.class);

        ReflectionTestUtils.setField(service, "orderService", orderService);
        ReflectionTestUtils.setField(service, "shopService", shopService);
        ReflectionTestUtils.setField(service, "drawerSessionMapper", drawerSessionMapper);
        com.lanf.mapper.CashMovementMapper cashMovementMapper = mock(com.lanf.mapper.CashMovementMapper.class);
        ReflectionTestUtils.setField(service, "cashMovementMapper", cashMovementMapper);
        ReflectionTestUtils.setField(service, "paymentLedgerMapper", paymentLedgerMapper);
        ReflectionTestUtils.setField(service, "snapshotMapper", snapshotMapper);
        ReflectionTestUtils.setField(service, "dishShopStockService", dishShopStockService);
        ReflectionTestUtils.setField(service, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(service, "kdsOrderHook", kdsOrderHook);
        ReflectionTestUtils.setField(service, "takeoutDeliveryService", takeoutDeliveryService);
        ReflectionTestUtils.setField(service, "collectionIntentService", collectionIntentService);
        ReflectionTestUtils.setField(service, "securityAuditService", securityAuditService);
        IPaymentService paymentService = mock(IPaymentService.class);
        when(paymentService.list(any())).thenReturn(Collections.emptyList());
        ReflectionTestUtils.setField(service, "paymentService", paymentService);
        IMemberRechargeService memberRechargeService = mock(IMemberRechargeService.class);
        when(memberRechargeService.summarizeSuccessfulByWindow(any(), any(), any()))
                .thenReturn(com.lanf.service.MemberRechargeSummary.empty());
        ReflectionTestUtils.setField(service, "memberRechargeService", memberRechargeService);
        ReflectionTestUtils.setField(service, "jwtTokenService", new JwtTokenService("0123456789abcdef0123456789abcdef", ""));
        ReflectionTestUtils.setField(service, "objectMapper", new ObjectMapper());
        OrderLedgerConsistencyService consistencyService = mock(OrderLedgerConsistencyService.class);
        when(consistencyService.audit(any())).thenReturn(Collections.emptyList());
        ReflectionTestUtils.setField(service, "orderLedgerConsistencyService", consistencyService);

        shop = new Shop();
        shop.setId(1);
        shop.setName("测试分店");
        shop.setSettle_time("04:00");
        when(shopService.getById(1)).thenReturn(shop);
        when(shopService.getOne(any(), anyBoolean())).thenReturn(shop);
    }

    @Test
    void precheck_identifiesStalePackAndTakeoutOrders() {
        when(drawerSessionMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(paymentLedgerMapper.selectCount(any())).thenReturn(0);

        long now = System.currentTimeMillis();
        // 订单1: 打包，下单时间 45 分钟前（超时可作废）
        Order o1 = new Order();
        o1.setId(101);
        o1.setOrder_no("ORD-PACK-STALE");
        o1.setTransac_status("unsettled");
        o1.setDineInOrTakeOut("打包");
        o1.setSett_amount(38.0);
        o1.setOrder_time(new Date(now - 45 * 60 * 1000L));

        // 订单2: 外卖，下单时间 10 分钟前（未超时不可作废）
        Order o2 = new Order();
        o2.setId(102);
        o2.setOrder_no("ORD-TAKEOUT-FRESH");
        o2.setTransac_status("unsettled");
        o2.setDineInOrTakeOut("外卖");
        o2.setSett_amount(50.0);
        o2.setOrder_time(new Date(now - 10 * 60 * 1000L));

        // 订单3: 堂食，下单时间 60 分钟前（堂食严禁可作废）
        Order o3 = new Order();
        o3.setId(103);
        o3.setOrder_no("ORD-DINEIN-STALE");
        o3.setTransac_status("unsettled");
        o3.setDineInOrTakeOut("堂食");
        o3.setSett_amount(120.0);
        o3.setOrder_time(new Date(now - 60 * 60 * 1000L));

        when(orderService.count(any())).thenReturn(3);
        when(orderService.list(any(Wrapper.class))).thenReturn(Arrays.asList(o1, o2, o3), Collections.emptyList());

        Map<String, Object> res = service.precheck(1, 1, "2026-10-13", 30);

        assertFalse((Boolean) res.get("can_settle"));
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> blockers = (List<Map<String, Object>>) res.get("blockers");
        assertEquals(1, blockers.size());
        Map<String, Object> openBlocker = blockers.get(0);
        assertEquals("OPEN_ORDERS", openBlocker.get("code"));

        @SuppressWarnings("unchecked")
        Map<String, Object> voidable = (Map<String, Object>) openBlocker.get("voidable_pack_takeout");
        assertNotNull(voidable);
        assertEquals(1, voidable.get("count"));
        assertEquals(38.0, (Double) voidable.get("amount"), 0.001);
        assertEquals(30, voidable.get("threshold_minutes"));
        assertTrue((Boolean) voidable.get("can_one_click_void"));

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> orders = (List<Map<String, Object>>) voidable.get("orders");
        assertEquals(1, orders.size());
        assertEquals("ORD-PACK-STALE", orders.get(0).get("order_no"));

        // 检查顶层输出
        @SuppressWarnings("unchecked")
        Map<String, Object> topVoidable = (Map<String, Object>) res.get("voidable_stale_pack_takeout");
        assertNotNull(topVoidable);
        assertEquals(1, topVoidable.get("count"));
    }

    @Test
    void voidStalePackTakeoutOrders_voidsOnlyStaleTakeoutAndTriggersSideEffects() {
        long now = System.currentTimeMillis();
        // 订单1: 打包，40 分钟前
        Order o1 = new Order();
        o1.setId(201);
        o1.setOrder_no("ORD-PACK-201");
        o1.setTransac_status("unsettled");
        o1.setDineInOrTakeOut("打包");
        o1.setSett_amount(45.0);
        o1.setOrder_time(new Date(now - 40 * 60 * 1000L));

        // 订单2: 堂食，50 分钟前（不应作废）
        Order o2 = new Order();
        o2.setId(202);
        o2.setOrder_no("ORD-DINE-202");
        o2.setTransac_status("unsettled");
        o2.setDineInOrTakeOut("堂食");
        o2.setSett_amount(88.0);
        o2.setOrder_time(new Date(now - 50 * 60 * 1000L));

        when(orderService.list(any(Wrapper.class))).thenReturn(Arrays.asList(o1, o2));
        when(orderService.update(any())).thenReturn(true);

        OrderDetail detail = new OrderDetail();
        detail.setId(1001);
        detail.setName("烤生蚝");
        detail.setQuantity("2");
        when(orderDetailService.list(any())).thenReturn(Collections.singletonList(detail));

        Map<String, Object> res = service.voidStalePackTakeoutOrders(1, 9, "2026-10-13", 30);

        assertEquals(1, res.get("voided_count"));
        assertEquals(45.0, (Double) res.get("voided_amount"), 0.001);
        @SuppressWarnings("unchecked")
        List<String> voidedNos = (List<String>) res.get("voided_order_nos");
        assertEquals(Collections.singletonList("ORD-PACK-201"), voidedNos);

        // 验证副作用：库存回退、KDS 通知、配送单取消、意向清理、审计记录
        verify(dishShopStockService).restoreForDetail(detail, 1);
        verify(kdsOrderHook).afterOrderCancelled(o1);
        verify(takeoutDeliveryService).markCancelledIfPresent("ORD-PACK-201");
        verify(collectionIntentService).cancelAllForOrder(1, "ORD-PACK-201");
        verify(securityAuditService).recordPrivilegedAction(
                isNull(), eq(1), eq("order"), eq("BATCH_VOID_STALE_TAKEOUT"),
                eq("COUNT:1"), eq(9), anyMap(), contains("一键作废"));
    }
}

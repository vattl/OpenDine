package com.lanf.controller;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.config.ServiceFeeConfig;
import com.lanf.dto.OrderDTO;
import com.lanf.entity.Dish;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.entity.Table;
import com.lanf.interceptor.UserIdentityInterceptor;
import com.lanf.order.OrderRevisionService;
import com.lanf.kds.delivery.CashierKdsProjectionService;
import com.lanf.mapper.DishShopMapper;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.service.IComboMealService;
import com.lanf.service.IDishService;
import com.lanf.service.IDishShopStockService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderLogService;
import com.lanf.service.IOrderService;
import com.lanf.service.ITableService;
import com.lanf.service.ITakeoutDeliveryService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class OrderControllerCompanionAddDishesTest {

    private OrderController orderController;
    private IOrderService orderService;
    private ITableService tableService;
    private IOrderDetailService orderDetailService;
    private IDishService dishService;
    private IComboMealService comboMealService;
    private IDishShopStockService dishShopStockService;
    private CashierKdsProjectionService cashierKdsProjectionService;
    private ServiceFeeConfig serviceFeeConfig;
    private IOrderLogService orderLogService;
    private com.lanf.service.IShopService shopService;
    private UserCouponMapper userCouponMapper;
    private com.lanf.kds.service.KdsOrderHook kdsOrderHook;
    private DishShopMapper dishShopMapper;
    private ITakeoutDeliveryService takeoutDeliveryService;
    private com.lanf.kds.service.KdsDetailStatusResolver kdsDetailStatusResolver;
    private com.lanf.payment.service.WechatJsapiPaymentService wechatJsapiPaymentService;
    private OrderRevisionService orderRevisionService;

    @BeforeEach
    void setUp() {
        orderController = new OrderController();
        orderService = mock(IOrderService.class);
        tableService = mock(ITableService.class);
        orderDetailService = mock(IOrderDetailService.class);
        dishService = mock(IDishService.class);
        comboMealService = mock(IComboMealService.class);
        dishShopStockService = mock(IDishShopStockService.class);
        cashierKdsProjectionService = mock(CashierKdsProjectionService.class);
        serviceFeeConfig = mock(ServiceFeeConfig.class);
        orderLogService = mock(IOrderLogService.class);
        shopService = mock(com.lanf.service.IShopService.class);
        userCouponMapper = mock(UserCouponMapper.class);
        kdsOrderHook = mock(com.lanf.kds.service.KdsOrderHook.class);
        dishShopMapper = mock(DishShopMapper.class);
        takeoutDeliveryService = mock(ITakeoutDeliveryService.class);
        kdsDetailStatusResolver = mock(com.lanf.kds.service.KdsDetailStatusResolver.class);
        wechatJsapiPaymentService = mock(com.lanf.payment.service.WechatJsapiPaymentService.class);
        orderRevisionService = mock(OrderRevisionService.class);
        when(wechatJsapiPaymentService.prepareForAmountMutation(any(Order.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        com.lanf.entity.Shop shop = new com.lanf.entity.Shop();
        shop.setId(1);
        shop.setStatus(1);
        when(shopService.getById(1)).thenReturn(shop);

        com.lanf.entity.DishShop ds = new com.lanf.entity.DishShop();
        ds.setShop_id(1);
        ds.setStock(100);
        ds.setOnsale_override(1);
        ds.setSold_out(0);
        when(dishShopMapper.selectOne(any(QueryWrapper.class))).thenReturn(ds);

        ReflectionTestUtils.setField(orderController, "orderService", orderService);
        ReflectionTestUtils.setField(orderController, "tableService", tableService);
        ReflectionTestUtils.setField(orderController, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(orderController, "dishService", dishService);
        ReflectionTestUtils.setField(orderController, "comboMealService", comboMealService);
        ReflectionTestUtils.setField(orderController, "dishShopStockService", dishShopStockService);
        ReflectionTestUtils.setField(orderController, "cashierKdsProjectionService", cashierKdsProjectionService);
        ReflectionTestUtils.setField(orderController, "serviceFeeConfig", serviceFeeConfig);
        ReflectionTestUtils.setField(orderController, "orderLogService", orderLogService);
        ReflectionTestUtils.setField(orderController, "shopService", shopService);
        ReflectionTestUtils.setField(orderController, "UserCouponMapper", userCouponMapper);
        ReflectionTestUtils.setField(orderController, "kdsOrderHook", kdsOrderHook);
        ReflectionTestUtils.setField(orderController, "dishShopMapper", dishShopMapper);
        ReflectionTestUtils.setField(orderController, "takeoutDeliveryService", takeoutDeliveryService);
        ReflectionTestUtils.setField(orderController, "kdsDetailStatusResolver", kdsDetailStatusResolver);
        ReflectionTestUtils.setField(orderController, "objectMapper", new ObjectMapper());
        ReflectionTestUtils.setField(orderController, "wechatJsapiPaymentService", wechatJsapiPaymentService);
        ReflectionTestUtils.setField(orderController, "orderRevisionService", orderRevisionService);
    }

    private Order createSampleOrder() {
        Order existingOrder = new Order();
        existingOrder.setId(100);
        existingOrder.setOrder_no("ORD-TABLE5-001");
        existingOrder.setShop_id(1);
        existingOrder.setTable_number("5");
        existingOrder.setOpenid("user_A");
        existingOrder.setTransac_status("unsettled");
        existingOrder.setDineInOrTakeOut("堂食");
        existingOrder.setSett_amount(50.0);
        existingOrder.setOrderNumber(1);
        existingOrder.setOrder_receiving("rec_order");
        return existingOrder;
    }

    private Table createSampleTable() {
        Table table = new Table();
        table.setId(5);
        table.setShop_id(1);
        table.setNumber("5");
        table.setAmount(50.0);
        table.setStatus(1);
        return table;
    }

    @Test
    void addDishes_whenCompanionAddsDishesToSameTableUnsettledOrder_shouldSucceed() {
        Order existingOrder = createSampleOrder();
        Table table = createSampleTable();

        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(existingOrder);
        when(tableService.getOne(any(QueryWrapper.class))).thenReturn(table);
        when(orderDetailService.list(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        when(serviceFeeConfig.isServiceFeeCharged()).thenReturn(false);
        when(orderService.updateById(any(Order.class))).thenReturn(true);
        when(tableService.updateById(any(Table.class))).thenReturn(true);
        when(orderDetailService.save(any(OrderDetail.class))).thenAnswer(inv -> {
            OrderDetail d = inv.getArgument(0);
            d.setId(2001);
            return true;
        });

        Dish dish = new Dish();
        dish.setId(10);
        dish.setName("烤油边");
        dish.setUnit("串");
        dish.setTypeId(1);
        dish.setOnsale(true);
        dish.setUnitprice(15.0f);
        when(dishService.getById(10)).thenReturn(dish);

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(UserIdentityInterceptor.ATTR_USER_OPENID, "user_B");
        request.addHeader("X-Shop-Id", "1");

        OrderDTO dto = new OrderDTO();
        dto.setOrder_no("ORD-TABLE5-001");
        dto.setTable_number("5");
        dto.setOpenid("user_B");
        dto.setShop_id(1);
        dto.setSett_amount(30.0);

        List<OrderDetail> goodsList = new ArrayList<>();
        OrderDetail item = new OrderDetail();
        item.setDish_id(10);
        item.setName("烤油边");
        item.setQuantity("2");
        item.setTotal_price(30.0);
        item.setUnit("串");
        item.setCid("1");
        goodsList.add(item);
        dto.setGoods_list(goodsList);

        R r = orderController.addDishes(dto, request);
        assertEquals(0, r.get("code"), "Companion B adding dishes to Table 5 unsettled order should succeed: " + r.get("msg"));
    }

    @Test
    void addDishes_whenMergedTableHasMultipleUnsettledOrders_shouldAggregateAllUnsettledOrdersNetRevenueForTable() {
        Order existingOrderA = createSampleOrder();
        existingOrderA.setSett_amount(100.0);

        Order existingOrderB = new Order();
        existingOrderB.setId(101);
        existingOrderB.setOrder_no("ORD-TABLE5-002");
        existingOrderB.setShop_id(1);
        existingOrderB.setTable_number("5");
        existingOrderB.setOpenid("user_B");
        existingOrderB.setTransac_status("unsettled");
        existingOrderB.setDineInOrTakeOut("堂食");
        existingOrderB.setSett_amount(40.0);

        Table table = createSampleTable();
        table.setAmount(140.0);

        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(existingOrderA);
        when(tableService.getOne(any(QueryWrapper.class))).thenReturn(table);
        when(orderDetailService.list(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        when(serviceFeeConfig.isServiceFeeCharged()).thenReturn(false);
        when(orderService.updateById(any(Order.class))).thenReturn(true);
        when(tableService.updateById(any(Table.class))).thenReturn(true);
        when(orderDetailService.save(any(OrderDetail.class))).thenAnswer(inv -> {
            OrderDetail d = inv.getArgument(0);
            d.setId(2002);
            return true;
        });

        // After adding dishes, unsettled orders on Table 5 are Order A (updated to 120.0) and Order B (40.0)
        when(orderService.list(any(QueryWrapper.class))).thenAnswer(inv -> {
            Order updatedA = createSampleOrder();
            updatedA.setSett_amount(120.0);
            return java.util.Arrays.asList(updatedA, existingOrderB);
        });

        Dish dish = new Dish();
        dish.setId(11);
        dish.setName("牛肉串");
        dish.setUnit("串");
        dish.setTypeId(1);
        dish.setOnsale(true);
        dish.setUnitprice(20.0f);
        when(dishService.getById(11)).thenReturn(dish);

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(UserIdentityInterceptor.ATTR_USER_OPENID, "user_A");
        request.addHeader("X-Shop-Id", "1");

        OrderDTO dto = new OrderDTO();
        dto.setOrder_no("ORD-TABLE5-001");
        dto.setTable_number("5");
        dto.setOpenid("user_A");
        dto.setShop_id(1);
        dto.setSett_amount(20.0);

        List<OrderDetail> goodsList = new ArrayList<>();
        OrderDetail item = new OrderDetail();
        item.setDish_id(11);
        item.setName("牛肉串");
        item.setQuantity("1");
        item.setTotal_price(20.0);
        item.setUnit("串");
        item.setCid("1");
        goodsList.add(item);
        dto.setGoods_list(goodsList);

        R r = orderController.addDishes(dto, request);
        assertEquals(0, r.get("code"));
        // Table amount must aggregate both orders: 120 + 40 = 160.0
        assertEquals(160.0, table.getAmount(), 0.001);
    }

    @Test
    void addDishes_whenStrangerAddsDishesToDifferentTable_shouldReturn403() {
        Order existingOrder = createSampleOrder();
        Table table = createSampleTable();

        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(existingOrder);
        when(tableService.getOne(any(QueryWrapper.class))).thenReturn(table);

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(UserIdentityInterceptor.ATTR_USER_OPENID, "user_B");
        request.addHeader("X-Shop-Id", "1");

        OrderDTO dto = new OrderDTO();
        dto.setOrder_no("ORD-TABLE5-001");
        dto.setTable_number("6"); // Different table
        dto.setOpenid("user_B");
        dto.setShop_id(1);
        dto.setExpectedVersion(0);

        R r = orderController.addDishes(dto, request);
        assertEquals(403, r.get("code"));
        assertEquals("无权给该订单加菜", r.get("msg"));
        verify(orderRevisionService, never()).assertExpected(any(Order.class), any());
    }

    @Test
    void get_whenCompanionQueriesTableUnsettledOrder_shouldReturnOrder() {
        Order existingOrder = createSampleOrder();
        when(orderService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(existingOrder));
        when(orderDetailService.list(any(QueryWrapper.class))).thenReturn(Collections.emptyList());

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(UserIdentityInterceptor.ATTR_USER_OPENID, "user_B");
        request.addHeader("X-Shop-Id", "1");

        R r = orderController.get("5", "unsettled", request);
        assertEquals(0, r.get("code"), "Companion B should be able to view Table 5 unsettled order");
        assertNotNull(r.get("menu"));
    }

    @Test
    void getOrder_whenCompanionQueriesOrderNoForUnsettledDineIn_shouldReturnOrder() {
        Order existingOrder = createSampleOrder();
        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(existingOrder);
        when(orderDetailService.list(any(QueryWrapper.class))).thenReturn(Collections.emptyList());

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(UserIdentityInterceptor.ATTR_USER_OPENID, "user_B");
        request.addHeader("X-Shop-Id", "1");

        R r = orderController.get("ORD-TABLE5-001", request);
        assertEquals(0, r.get("code"), "Companion B should be able to view unsettled dine-in order by order_no");
        assertNotNull(r.get("menu"));
    }

    @Test
    void getTableInfo_whenCompanionQueriesTableWithUnsettledOrder_shouldReturnActiveOrder() {
        Order existingOrder = createSampleOrder();
        Table table = createSampleTable();

        when(tableService.getOne(any(Wrapper.class))).thenReturn(table);
        // First call with openid=user_B returns null; second call without openid restriction returns existingOrder
        when(orderService.getOne(any(Wrapper.class))).thenAnswer(inv -> {
            QueryWrapper<?> qw = inv.getArgument(0);
            qw.getSqlSegment();
            if (qw.getParamNameValuePairs() != null && qw.getParamNameValuePairs().containsValue("user_B")) {
                return null;
            }
            return existingOrder;
        });

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute(UserIdentityInterceptor.ATTR_USER_OPENID, "user_B");
        request.addHeader("X-Shop-Id", "1");

        R r = orderController.getTableInfo("5", request);
        assertEquals(0, r.get("code"));
        assertEquals("ORD-TABLE5-001", r.get("orderNo"));
    }
}

package com.lanf.controller;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.config.ServiceFeeConfig;
import com.lanf.dto.OrderDTO;
import com.lanf.entity.Dish;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.entity.Table;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.order.OrderRevisionService;
import com.lanf.kds.delivery.CashierKdsProjectionService;
import com.lanf.service.IComboMealService;
import com.lanf.service.IDishService;
import com.lanf.service.IDishShopStockService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderLogService;
import com.lanf.service.IOrderService;
import com.lanf.service.ITableService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class OrderControllerAddDishesComboTest {

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
    private com.lanf.mapper.DishShopMapper dishShopMapper;
    private com.lanf.payment.service.WechatJsapiPaymentService wechatJsapiPaymentService;

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
        dishShopMapper = mock(com.lanf.mapper.DishShopMapper.class);
        wechatJsapiPaymentService = mock(com.lanf.payment.service.WechatJsapiPaymentService.class);
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
        ReflectionTestUtils.setField(orderController, "objectMapper", new ObjectMapper());
        ReflectionTestUtils.setField(orderController, "wechatJsapiPaymentService", wechatJsapiPaymentService);
        ReflectionTestUtils.setField(orderController, "orderRevisionService", mock(OrderRevisionService.class));
    }

    @Test
    void addDishes_withCombo_shouldNormalizeAndPersistSuccessfully() {
        Date originalOrderTime = new Date(1_760_000_000_000L);
        Order existingOrder = new Order();
        existingOrder.setId(100);
        existingOrder.setOrder_no("ORD20260912154554756");
        existingOrder.setShop_id(1);
        existingOrder.setTable_number("20");
        existingOrder.setOpenid("user_test_openid");
        existingOrder.setTransac_status("unsettled");
        existingOrder.setDineInOrTakeOut("堂食");
        existingOrder.setSett_amount(100.0);
        existingOrder.setOrderNumber(1);
        existingOrder.setOrder_receiving("rec_order");
        existingOrder.setOrder_time(originalOrderTime);

        Table table = new Table();
        table.setId(20);
        table.setNumber("20");
        table.setAmount(100.0);

        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(existingOrder);
        when(orderService.list(any(QueryWrapper.class))).thenReturn(Collections.singletonList(existingOrder));
        when(tableService.getOne(any(QueryWrapper.class))).thenReturn(table);
        when(orderDetailService.list(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        when(serviceFeeConfig.isServiceFeeCharged()).thenReturn(false);
        when(orderService.updateById(any(Order.class))).thenReturn(true);
        when(tableService.updateById(any(Table.class))).thenReturn(true);
        when(orderDetailService.save(any(OrderDetail.class))).thenAnswer(inv -> {
            OrderDetail d = inv.getArgument(0);
            d.setId(1001);
            return true;
        });

        Dish headerDish = new Dish();
        headerDish.setId(139);
        headerDish.setName("单人油边套餐");
        headerDish.setUnit("份");
        headerDish.setTypeId(10);
        headerDish.setOnsale(true);
        headerDish.setUnitprice(68.0f);
        when(dishService.getById(139)).thenReturn(headerDish);

        Dish compDish = new Dish();
        compDish.setId(201);
        compDish.setName("烤油边");
        compDish.setUnit("串");
        compDish.setTypeId(1);
        compDish.setOnsale(true);
        compDish.setUnitprice(15.0f);
        when(dishService.getById(201)).thenReturn(compDish);

        doAnswer(inv -> {
            List<OrderDetail> lines = inv.getArgument(0);
            lines.clear();

            OrderDetail h = new OrderDetail();
            h.setName("单人油边套餐");
            h.setQuantity("1");
            h.setUnit("份");
            h.setCid("10");
            h.setTotal_price(68.0);
            h.setLine_type("combo_header");
            h.setCombo_id(8L);
            h.setCombo_instance_id("inst-123");
            h.setDish_id(139);

            OrderDetail c = new OrderDetail();
            c.setName("烤油边");
            c.setQuantity("2");
            c.setUnit("串");
            c.setCid("1");
            c.setTotal_price(0.0);
            c.setLine_type("combo_component");
            c.setCombo_id(8L);
            c.setCombo_instance_id("inst-123");
            c.setDish_id(201);

            lines.add(h);
            lines.add(c);
            return null;
        }).when(comboMealService).normalizeCartLines(anyList(), anyInt());
        doAnswer(invocation -> {
            List<OrderDetail> lines = invocation.getArgument(0);
            OrderDetail h = new OrderDetail();
            h.setName("单人油边套餐");
            h.setQuantity("1");
            h.setUnit("份");
            h.setCid("10");
            h.setTotal_price(68.0);
            h.setLine_type("combo_header");
            h.setCombo_id(8L);
            h.setCombo_instance_id("inst-123");
            h.setDish_id(139);

            OrderDetail c = new OrderDetail();
            c.setName("烤油边");
            c.setQuantity("2");
            c.setUnit("串");
            c.setCid("1");
            c.setTotal_price(0.0);
            c.setLine_type("combo_component");
            c.setCombo_id(8L);
            c.setCombo_instance_id("inst-123");
            c.setDish_id(201);

            lines.add(h);
            lines.add(c);
            return null;
        }).when(comboMealService).normalizeCartLines(anyList(), anyInt(), any(), any(), anyBoolean());

        OrderDTO dto = new OrderDTO();
        dto.setOrder_no("ORD20260912154554756");
        dto.setTable_number("20");
        dto.setOpenid("user_test_openid");
        dto.setShop_id(1);
        dto.setSett_amount(68.0);

        OrderDetail reqLine = new OrderDetail();
        reqLine.setDish_id(139);
        reqLine.setName("单人油边套餐");
        reqLine.setQuantity("1");
        reqLine.setUnit("份");
        reqLine.setCid("10");
        reqLine.setTotal_price(68.0);
        reqLine.setLine_type("combo");
        reqLine.setCombo_id(8L);

        List<OrderDetail> goodsList = new ArrayList<>();
        goodsList.add(reqLine);
        dto.setGoods_list(goodsList);

        MockHttpServletRequest request = new MockHttpServletRequest();
        R result = orderController.addDishes(dto, request);

        assertEquals(0, result.get("code"), "Failed with message: " + result.get("msg"));
        assertEquals("加菜成功", result.get("msg"));
        assertEquals(168.0, existingOrder.getSett_amount());
        assertEquals(2, existingOrder.getOrderNumber());
        assertEquals(originalOrderTime, existingOrder.getOrder_time(),
                "加菜不能改变订单首次下单时间");
    }

    @Test
    void addDishes_afterTableMerge_shouldKeepAllUnsettledOrdersInTableAmount() {
        Order existingOrder = new Order();
        existingOrder.setId(100);
        existingOrder.setOrder_no("ORD-MERGED-A");
        existingOrder.setShop_id(1);
        existingOrder.setTable_number("20");
        existingOrder.setOpenid("user_test_openid");
        existingOrder.setTransac_status("unsettled");
        existingOrder.setDineInOrTakeOut("堂食");
        existingOrder.setSett_amount(100d);
        existingOrder.setService_fee(0d);
        existingOrder.setDiscount_amount(0d);
        existingOrder.setOrderNumber(1);
        existingOrder.setOrder_receiving("rec_order");

        Order mergedOrder = new Order();
        mergedOrder.setId(101);
        mergedOrder.setOrder_no("ORD-MERGED-B");
        mergedOrder.setShop_id(1);
        mergedOrder.setTable_number("20");
        mergedOrder.setTransac_status("unsettled");
        mergedOrder.setSett_amount(40d);
        mergedOrder.setService_fee(0d);
        mergedOrder.setDiscount_amount(0d);

        Table table = new Table();
        table.setId(20);
        table.setShop_id(1);
        table.setNumber("20");
        table.setAmount(140d);

        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(existingOrder);
        when(orderService.list(any(QueryWrapper.class))).thenReturn(Arrays.asList(existingOrder, mergedOrder));
        when(tableService.getOne(any(QueryWrapper.class))).thenReturn(table);
        when(orderDetailService.list(any(QueryWrapper.class))).thenReturn(Collections.emptyList());
        when(serviceFeeConfig.isServiceFeeCharged()).thenReturn(false);
        when(orderService.updateById(any(Order.class))).thenReturn(true);
        when(tableService.updateById(any(Table.class))).thenReturn(true);
        when(orderDetailService.save(any(OrderDetail.class))).thenAnswer(invocation -> {
            OrderDetail detail = invocation.getArgument(0);
            detail.setId(1002);
            return true;
        });

        Dish addedDish = new Dish();
        addedDish.setId(301);
        addedDish.setName("加菜");
        addedDish.setUnit("份");
        addedDish.setTypeId(1);
        addedDish.setOnsale(true);
        addedDish.setUnitprice(20f);
        when(dishService.getById(301)).thenReturn(addedDish);

        OrderDetail requestLine = new OrderDetail();
        requestLine.setDish_id(301);
        requestLine.setName("加菜");
        requestLine.setQuantity("1");
        requestLine.setUnit("份");
        requestLine.setCid("1");
        requestLine.setTotal_price(20d);

        OrderDTO dto = new OrderDTO();
        dto.setOrder_no("ORD-MERGED-A");
        dto.setTable_number("20");
        dto.setOpenid("user_test_openid");
        dto.setShop_id(1);
        dto.setSett_amount(20d);
        dto.setGoods_list(Collections.singletonList(requestLine));

        R result = orderController.addDishes(dto, new MockHttpServletRequest());

        assertEquals(0, result.get("code"), "Failed with message: " + result.get("msg"));
        assertEquals(120d, existingOrder.getSett_amount());
        assertEquals(160d, table.getAmount(),
                "并台后加菜必须保留同桌其他未结订单金额");
    }

    @Test
    void addDishes_withComboValidationError_shouldTransparentlyReturnErrorMsg() {
        Order existingOrder = new Order();
        existingOrder.setId(100);
        existingOrder.setOrder_no("ORD20260912154554756");
        existingOrder.setShop_id(1);
        existingOrder.setTable_number("20");
        existingOrder.setOpenid("user_test_openid");
        existingOrder.setTransac_status("unsettled");
        existingOrder.setDineInOrTakeOut("堂食");

        when(orderService.getOne(any(QueryWrapper.class))).thenReturn(existingOrder);
        when(tableService.getOne(any(QueryWrapper.class))).thenReturn(new Table());
        doThrow(new RuntimeException("套餐组「饮品」须选 1~1 项")).when(comboMealService).normalizeCartLines(anyList(), anyInt());
        doThrow(new RuntimeException("套餐组「饮品」须选 1~1 项")).when(comboMealService).normalizeCartLines(anyList(), anyInt(), any(), any(), anyBoolean());

        OrderDTO dto = new OrderDTO();
        dto.setOrder_no("ORD20260912154554756");
        dto.setTable_number("20");
        dto.setOpenid("user_test_openid");
        dto.setShop_id(1);

        OrderDetail reqLine = new OrderDetail();
        reqLine.setDish_id(139);
        reqLine.setName("单人油边套餐");
        reqLine.setLine_type("combo");
        reqLine.setCombo_id(8L);

        List<OrderDetail> goodsList = new ArrayList<>();
        goodsList.add(reqLine);
        dto.setGoods_list(goodsList);

        MockHttpServletRequest request = new MockHttpServletRequest();
        R result = orderController.addDishes(dto, request);

        assertEquals(500, result.get("code"));
        assertEquals("套餐组「饮品」须选 1~1 项", result.get("msg"));
    }
}

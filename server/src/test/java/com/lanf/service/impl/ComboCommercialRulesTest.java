package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Combo;
import com.lanf.entity.ComboFixedItem;
import com.lanf.entity.Dish;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.mapper.ComboFixedItemMapper;
import com.lanf.mapper.ComboGroupItemMapper;
import com.lanf.mapper.ComboGroupMapper;
import com.lanf.mapper.ComboMapper;
import com.lanf.mapper.DishShopMapper;
import com.lanf.mapper.OrderDetailMapper;
import com.lanf.order.OrderDetailLineStatus;
import com.lanf.service.IDishService;
import com.lanf.service.IDishShopStockService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.OrderAmountRecalculationService;
import com.lanf.payment.service.WechatJsapiPaymentService;
import com.lanf.kds.service.KdsOrderHook;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

class ComboCommercialRulesTest {

    private ComboMealServiceImpl comboMealService;
    private ComboMapper comboMapper;
    private ComboFixedItemMapper comboFixedItemMapper;
    private ComboGroupMapper comboGroupMapper;
    private ComboGroupItemMapper comboGroupItemMapper;
    private IDishService dishService;
    private DishShopMapper dishShopMapper;
    private OrderDetailMapper orderDetailMapper;
    private ObjectMapper objectMapper;

    @BeforeEach
    void setUp() {
        comboMealService = new ComboMealServiceImpl();
        comboMapper = mock(ComboMapper.class);
        comboFixedItemMapper = mock(ComboFixedItemMapper.class);
        comboGroupMapper = mock(ComboGroupMapper.class);
        comboGroupItemMapper = mock(ComboGroupItemMapper.class);
        dishService = mock(IDishService.class);
        dishShopMapper = mock(DishShopMapper.class);
        orderDetailMapper = mock(OrderDetailMapper.class);
        objectMapper = new ObjectMapper();

        ReflectionTestUtils.setField(comboMealService, "comboMapper", comboMapper);
        ReflectionTestUtils.setField(comboMealService, "comboFixedItemMapper", comboFixedItemMapper);
        ReflectionTestUtils.setField(comboMealService, "comboGroupMapper", comboGroupMapper);
        ReflectionTestUtils.setField(comboMealService, "comboGroupItemMapper", comboGroupItemMapper);
        ReflectionTestUtils.setField(comboMealService, "dishService", dishService);
        ReflectionTestUtils.setField(comboMealService, "dishShopMapper", dishShopMapper);
        ReflectionTestUtils.setField(comboMealService, "orderDetailMapper", orderDetailMapper);
        ReflectionTestUtils.setField(comboMealService, "objectMapper", objectMapper);
    }

    @Test
    void testLimitPerOrderExceeded() {
        Combo c = new Combo();
        c.setId(101L);
        c.setDish_id(1);
        c.setStatus(1);
        c.setLimit_per_order(1);

        Dish d = new Dish();
        d.setId(1);
        d.setName("超值双人餐");
        d.setUnitprice(48f);

        when(comboMapper.selectById(101L)).thenReturn(c);
        when(dishService.getById(1)).thenReturn(d);

        RuntimeException ex = assertThrows(RuntimeException.class, () ->
                comboMealService.validateComboCommercialRules(101L, 1, 2, "user_123", "堂食"));
        assertTrue(ex.getMessage().contains("单单限购 1 份"));
    }

    @Test
    void testLimitPerUserExceeded() {
        Combo c = new Combo();
        c.setId(102L);
        c.setDish_id(2);
        c.setStatus(1);
        c.setLimit_per_user(2);
        c.setLimit_cycle("daily");

        Dish d = new Dish();
        d.setId(2);
        d.setName("引流特惠餐");
        d.setUnitprice(9.9f);

        when(comboMapper.selectById(102L)).thenReturn(c);
        when(dishService.getById(2)).thenReturn(d);
        // 用户今天已经购买了 1 份
        when(orderDetailMapper.sumUserPurchasedComboQty(eq("user_abc"), eq(102L), any())).thenReturn(1);

        // 再买 2 份 -> 1 + 2 = 3 > 2，应抛出异常
        RuntimeException ex = assertThrows(RuntimeException.class, () ->
                comboMealService.validateComboCommercialRules(102L, 1, 2, "user_abc", "堂食"));
        assertTrue(ex.getMessage().contains("每日每人限购 2 份（您已购买 1 份）"));
    }

    @Test
    void testDiningTypeRestriction() {
        Combo c = new Combo();
        c.setId(103L);
        c.setDish_id(3);
        c.setStatus(1);
        c.setApply_dining_type("dine_in");

        Dish d = new Dish();
        d.setId(3);
        d.setName("仅堂食烤肉套");
        d.setUnitprice(88f);

        when(comboMapper.selectById(103L)).thenReturn(c);
        when(dishService.getById(3)).thenReturn(d);

        // 打包/外卖下单应被拦截
        RuntimeException ex = assertThrows(RuntimeException.class, () ->
                comboMealService.validateComboCommercialRules(103L, 1, 1, "user_abc", "打包"));
        assertTrue(ex.getMessage().contains("仅限堂食使用"));
    }

    @Test
    void testDateRangeNotStarted() {
        Combo c = new Combo();
        c.setId(104L);
        c.setDish_id(4);
        c.setStatus(1);
        // 未来开始
        c.setStart_time(new Date(System.currentTimeMillis() + 3600_000));

        Dish d = new Dish();
        d.setId(4);
        d.setName("未来活动套餐");
        d.setUnitprice(50f);

        when(comboMapper.selectById(104L)).thenReturn(c);
        when(dishService.getById(4)).thenReturn(d);

        RuntimeException ex = assertThrows(RuntimeException.class, () ->
                comboMealService.validateComboCommercialRules(104L, 1, 1, "user_abc", "堂食"));
        assertTrue(ex.getMessage().contains("活动尚未开始"));
    }

    @Test
    void testOriginalPriceAndSavedAmountCalculated() {
        Combo c = new Combo();
        c.setId(105L);
        c.setDish_id(5);
        c.setStatus(1);
        c.setCombo_type("fixed");

        Dish header = new Dish();
        header.setId(5);
        header.setName("五一特惠餐");
        header.setUnitprice(50f); // 售价 50 元
        header.setOnsale(true);

        when(comboMapper.selectById(105L)).thenReturn(c);
        when(dishService.getById(5)).thenReturn(header);

        // 固定子项 1：烤羊肉 2 串，每串 20 元 = 40 元
        ComboFixedItem f1 = new ComboFixedItem();
        f1.setComponent_dish_id(11);
        f1.setQty_per_combo(2);
        Dish sub1 = new Dish();
        sub1.setId(11);
        sub1.setName("烤羊肉");
        sub1.setUnitprice(20f);
        when(dishService.getById(11)).thenReturn(sub1);

        // 固定子项 2：酸梅汤 2 杯，每杯 15 元 = 30 元
        ComboFixedItem f2 = new ComboFixedItem();
        f2.setComponent_dish_id(12);
        f2.setQty_per_combo(2);
        Dish sub2 = new Dish();
        sub2.setId(12);
        sub2.setName("酸梅汤");
        sub2.setUnitprice(15f);
        when(dishService.getById(12)).thenReturn(sub2);

        when(comboFixedItemMapper.selectList(any())).thenReturn(Arrays.asList(f1, f2));
        when(comboGroupMapper.selectList(any())).thenReturn(Collections.emptyList());

        Map<String, Object> payload = comboMealService.buildCustomerComboPayload(105L, 1);
        assertNotNull(payload);
        assertEquals(70.0, payload.get("originalPrice")); // 40 + 30 = 70 元
        assertEquals(20.0, payload.get("savedAmount"));   // 70 - 50 = 20 元立省
        assertTrue((Boolean) payload.get("isAvailableNow"));
    }

    @Test
    void testRefundComboHeaderCascadesComponents() {
        OrderDetailRefundService refundService = new OrderDetailRefundService();
        IOrderDetailService orderDetailService = mock(IOrderDetailService.class);
        IDishShopStockService dishShopStockService = mock(IDishShopStockService.class);
        KdsOrderHook kdsOrderHook = mock(KdsOrderHook.class);
        OrderAmountRecalculationService recalcService = mock(OrderAmountRecalculationService.class);
        WechatJsapiPaymentService paymentService = mock(WechatJsapiPaymentService.class);

        ReflectionTestUtils.setField(refundService, "orderDetailService", orderDetailService);
        ReflectionTestUtils.setField(refundService, "dishShopStockService", dishShopStockService);
        ReflectionTestUtils.setField(refundService, "kdsOrderHook", kdsOrderHook);
        ReflectionTestUtils.setField(refundService, "orderAmountRecalculationService", recalcService);
        ReflectionTestUtils.setField(refundService, "wechatJsapiPaymentService", paymentService);

        Order order = new Order();
        order.setId(888);
        order.setShop_id(1);
        order.setTransac_status("unsettled");
        when(paymentService.prepareForAmountMutation(any())).thenReturn(order);

        // 套餐头行
        OrderDetail header = new OrderDetail();
        header.setId(1001);
        header.setName("情侣双人套餐");
        header.setQuantity("1");
        header.setLine_type("combo_header");
        header.setCombo_instance_id("inst_uuid_999");
        header.setTotal_price(88.0);

        // 套餐子菜行
        OrderDetail comp1 = new OrderDetail();
        comp1.setId(1002);
        comp1.setName("烤鸡翅");
        comp1.setQuantity("2");
        comp1.setLine_type("combo_component");
        comp1.setCombo_instance_id("inst_uuid_999");
        comp1.setTotal_price(0.0);

        when(orderDetailService.list(any())).thenReturn(Collections.singletonList(comp1));

        refundService.refundFullLine(header, order);

        // 验证头行与子行均被标记为 REFUNDED
        assertEquals(OrderDetailLineStatus.REFUNDED, header.getLine_status());
        assertEquals(OrderDetailLineStatus.REFUNDED, comp1.getLine_status());
        // 验证 KDS 均被作废
        verify(kdsOrderHook).afterRefundDetails(eq(1), eq(Collections.singletonList(1001)));
        verify(kdsOrderHook).afterRefundDetails(eq(1), eq(Collections.singletonList(1002)));
    }

    @Test
    void testCashierBypassesCommercialRestrictions() {
        Combo c = new Combo();
        c.setId(201L);
        c.setDish_id(10);
        c.setStatus(1);
        c.setLimit_per_order(1);
        c.setLimit_per_user(1);
        c.setLimit_cycle("daily");
        c.setApply_dining_type("dine_in");
        c.setAvailable_days("1"); // 假设施加了周一限制
        c.setTime_range_start("02:00:00");
        c.setTime_range_end("03:00:00"); // 凌晨时段
        c.setStart_time(new Date(System.currentTimeMillis() + 86400_000L)); // 明天才开始

        when(comboMapper.selectById(201L)).thenReturn(c);

        // 1. isCashier = true 显式传参：全部放行，不抛任何异常
        assertDoesNotThrow(() ->
                comboMealService.validateComboCommercialRules(201L, 1, 5, "user_regular", "打包", true));

        // 2. openid = "cashier_system"：即便 isCashier = false，也自动放行
        assertDoesNotThrow(() ->
                comboMealService.validateComboCommercialRules(201L, 1, 10, "cashier_system", "打包", false));

        // 3. 收银端依然拦截已停用或不存在的套餐
        Combo deactivated = new Combo();
        deactivated.setId(202L);
        deactivated.setStatus(0);
        when(comboMapper.selectById(202L)).thenReturn(deactivated);

        RuntimeException ex = assertThrows(RuntimeException.class, () ->
                comboMealService.validateComboCommercialRules(202L, 1, 1, "cashier_system", "堂食", true));
        assertEquals("套餐不存在或已停用", ex.getMessage());
    }

    @Test
    void testCustomerSelfOrderingStillBlockedByCommercialRules() {
        Combo c = new Combo();
        c.setId(301L);
        c.setDish_id(20);
        c.setStatus(1);
        c.setLimit_per_order(2);

        Dish d = new Dish();
        d.setId(20);
        d.setName("限购特惠单人餐");
        when(comboMapper.selectById(301L)).thenReturn(c);
        when(dishService.getById(20)).thenReturn(d);

        // 普通 C 端顾客点 3 份超限
        RuntimeException ex = assertThrows(RuntimeException.class, () ->
                comboMealService.validateComboCommercialRules(301L, 1, 3, "user_customer_openid", "堂食", false));
        assertTrue(ex.getMessage().contains("单单限购 2 份"));
    }
}

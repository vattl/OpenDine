package com.lanf.order;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.config.ServiceFeeConfig;
import com.lanf.controller.OrderController;
import com.lanf.dto.OrderDTO;
import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.entity.Table;
import com.lanf.entity.User;
import com.lanf.kds.service.KdsConfigService;
import com.lanf.kds.service.KdsOrderHook;
import com.lanf.mapper.DishShopMapper;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.service.IComboMealService;
import com.lanf.service.IDishService;
import com.lanf.service.IDishShopStockService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.service.ITableService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.service.IUserService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.Collections;
import java.util.Date;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

public class SameTableMultipleOrdersKdsAuditTest {

    @Test
    void creatingSecondOrderOnSameTableDoesNotForcePreviousOrderToOffOrder() {
        OrderController controller = new OrderController();
        IOrderService orderService = mock(IOrderService.class);
        IOrderDetailService detailService = mock(IOrderDetailService.class);
        ITableService tableService = mock(ITableService.class);
        IUserService userService = mock(IUserService.class);
        IShopService shopService = mock(IShopService.class);
        IDishService dishService = mock(IDishService.class);
        IDishShopStockService stockService = mock(IDishShopStockService.class);
        DishShopMapper dishShopMapper = mock(DishShopMapper.class);
        UserCouponMapper userCouponMapper = mock(UserCouponMapper.class);
        KdsOrderHook kdsOrderHook = mock(KdsOrderHook.class);
        KdsConfigService kdsConfigService = mock(KdsConfigService.class);
        ITakeoutDeliveryService deliveryService = mock(ITakeoutDeliveryService.class);
        IComboMealService comboMealService = mock(IComboMealService.class);
        ServiceFeeConfig serviceFeeConfig = mock(ServiceFeeConfig.class);

        ReflectionTestUtils.setField(controller, "orderService", orderService);
        ReflectionTestUtils.setField(controller, "orderDetailService", detailService);
        ReflectionTestUtils.setField(controller, "tableService", tableService);
        ReflectionTestUtils.setField(controller, "userService", userService);
        ReflectionTestUtils.setField(controller, "shopService", shopService);
        ReflectionTestUtils.setField(controller, "dishService", dishService);
        ReflectionTestUtils.setField(controller, "dishShopStockService", stockService);
        ReflectionTestUtils.setField(controller, "dishShopMapper", dishShopMapper);
        ReflectionTestUtils.setField(controller, "UserCouponMapper", userCouponMapper);
        ReflectionTestUtils.setField(controller, "kdsOrderHook", kdsOrderHook);
        ReflectionTestUtils.setField(controller, "kdsConfigService", kdsConfigService);
        ReflectionTestUtils.setField(controller, "takeoutDeliveryService", deliveryService);
        ReflectionTestUtils.setField(controller, "comboMealService", comboMealService);
        ReflectionTestUtils.setField(controller, "serviceFeeConfig", serviceFeeConfig);
        doNothing().when(stockService).validateCanDeduct(any(), any());
        doNothing().when(stockService).deductForDetails(any(), any());

        Shop shop = new Shop();
        shop.setId(1);
        shop.setStatus(1);
        when(shopService.getById(1)).thenReturn(shop);

        Dish dish = new Dish();
        dish.setId(1);
        dish.setName("羊肉串");
        dish.setUnitprice(5.0f);
        dish.setOnsale(true);
        when(dishService.getById(1)).thenReturn(dish);
        when(dishService.getOne(any(Wrapper.class))).thenReturn(dish);
        when(dishService.list(any(Wrapper.class))).thenReturn(Collections.singletonList(dish));

        DishShop link = new DishShop();
        link.setShop_id(1);
        link.setDish_id(1);
        link.setStock(100);
        link.setSold_out(0);
        link.setStock_enabled(1);
        link.setUnitprice(new BigDecimal("5.00"));
        when(dishShopMapper.selectOne(any())).thenReturn(link);

        // First order on Table A01 (Paid, still being cooked in KDS)
        Order order1 = new Order();
        order1.setId(1001);
        order1.setOrder_no("ORD-001");
        order1.setShop_id(1);
        order1.setTable_number("A01");
        order1.setDineInOrTakeOut("堂食");
        order1.setTransac_status("success");
        order1.setOrder_receiving("rec_order");
        assertNull(order1.getOff_time());

        // Table A01 currently points to ORD-001 (status=2: checked out waiting for clear/dishes)
        Table table = new Table();
        table.setId(1);
        table.setShop_id(1);
        table.setNumber("A01");
        table.setStatus(2);
        table.setOrder_no("ORD-001");
        table.setOpen_time(new Date(System.currentTimeMillis() - 600000));

        when(tableService.getOne(any(Wrapper.class))).thenReturn(table);
        when(tableService.updateById(any(Table.class))).thenReturn(true);
        when(orderService.save(any(Order.class))).thenAnswer(inv -> {
            Order o = inv.getArgument(0);
            o.setId(1002);
            return true;
        });
        when(orderService.updateById(any(Order.class))).thenReturn(true);
        when(detailService.save(any(OrderDetail.class))).thenReturn(true);
        when(detailService.saveBatch(any())).thenReturn(true);
        when(userService.getUserByOpenid("user_test")).thenReturn(new User());

        // New order DTO for Table A01 (ORD-002)
        OrderDTO order2Dto = new OrderDTO();
        order2Dto.setOrder_no("ORD-002");
        order2Dto.setShop_id(1);
        order2Dto.setTable_number("A01");
        order2Dto.setDineInOrTakeOut("堂食");
        order2Dto.setNumber_of_diners("2");
        order2Dto.setSett_amount(25.0);
        order2Dto.setDiscount_amount(0.0);
        order2Dto.setOpenid("user_test");
        OrderDetail detail = new OrderDetail();
        detail.setDish_id(1);
        detail.setName("羊肉串");
        detail.setUnit("串");
        detail.setCid("cid-1");
        detail.setQuantity("5");
        detail.setTotal_price(25.0);
        order2Dto.setGoods_list(Collections.singletonList(detail));

        MockHttpServletRequest request = new MockHttpServletRequest();
        R result = controller.create(order2Dto, request);

        assertEquals(0, result.get("code"), "Result code should be 0: " + result.get("msg"));

        // Verify that order1 was NEVER updated to off_order
        assertEquals("rec_order", order1.getOrder_receiving());
        assertNull(order1.getOff_time());
        verify(orderService, never()).updateById(order1);

        // Verify table now points to ORD-002 and is active (status=1)
        assertEquals("ORD-002", table.getOrder_no());
        assertEquals(1, table.getStatus());
    }
}

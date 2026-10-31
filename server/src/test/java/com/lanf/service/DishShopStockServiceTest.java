package com.lanf.service;

import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import com.lanf.entity.DishStockLog;
import com.lanf.entity.OrderDetail;
import com.lanf.mapper.DishShopMapper;
import com.lanf.mapper.DishStockLogMapper;
import com.lanf.order.RefundStockAction;
import com.lanf.service.impl.DishShopStockServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class DishShopStockServiceTest {

    private DishShopStockServiceImpl stockService;
    private IDishService dishService;
    private DishShopMapper dishShopMapper;
    private DishStockLogMapper dishStockLogMapper;
    private DishMenuPushService pushService;

    @BeforeEach
    void setUp() {
        stockService = new DishShopStockServiceImpl();
        dishService = mock(IDishService.class);
        dishShopMapper = mock(DishShopMapper.class);
        dishStockLogMapper = mock(DishStockLogMapper.class);
        pushService = mock(DishMenuPushService.class);

        ReflectionTestUtils.setField(stockService, "dishService", dishService);
        ReflectionTestUtils.setField(stockService, "dishShopMapper", dishShopMapper);
        ReflectionTestUtils.setField(stockService, "dishStockLogMapper", dishStockLogMapper);
        ReflectionTestUtils.setField(stockService, "dishMenuPushService", pushService);

        Dish dish = new Dish();
        dish.setId(101);
        dish.setName("招牌烤肉");
        dish.setOnsale(true);
        when(dishService.getById(101)).thenReturn(dish);
    }

    private DishShop mockDishShop(int stock, int soldOut, int stockEnabled) {
        DishShop ds = new DishShop();
        ds.setId(1L);
        ds.setShop_id(1);
        ds.setDish_id(101);
        ds.setStock(stock);
        ds.setSold_out(soldOut);
        ds.setStock_enabled(stockEnabled);
        ds.setOnsale_override(1);
        when(dishShopMapper.selectOne(any())).thenReturn(ds);
        return ds;
    }

    @Test
    void testRestoreStockActionIncreasesStockAndLogs() {
        mockDishShop(5, 0, 1);

        OrderDetail detail = new OrderDetail();
        detail.setId(1001);
        detail.setDish_id(101);
        detail.setName("招牌烤肉");
        detail.setQuantity("2");
        detail.setMorder_no("ORD-001");

        stockService.handleRefundStock(detail, 1, 2, RefundStockAction.RESTORE, "cashier:1", "点错未做");

        verify(dishShopMapper).update(isNull(), any());
        ArgumentCaptor<DishStockLog> logCaptor = ArgumentCaptor.forClass(DishStockLog.class);
        verify(dishStockLogMapper).insert(logCaptor.capture());

        DishStockLog log = logCaptor.getValue();
        assertNotNull(log);
        assertEquals("REFUND_RESTORE", log.getChange_type());
        assertEquals(2, log.getDelta());
        assertEquals(5, log.getStock_before());
        assertEquals(7, log.getStock_after());
        assertEquals("ORD-001", log.getOrder_no());
        assertEquals("点错未做", log.getRemark());
    }

    @Test
    void testNoRestoreStockActionDoesNotUpdateShopStockButLogsWaste() {
        mockDishShop(5, 0, 1);

        OrderDetail detail = new OrderDetail();
        detail.setId(1002);
        detail.setDish_id(101);
        detail.setName("招牌烤肉");
        detail.setQuantity("1");
        detail.setMorder_no("ORD-002");

        stockService.handleRefundStock(detail, 1, 1, RefundStockAction.NO_RESTORE, "admin", "菜品变质损耗");

        // 绝不更新 t_dish_shop
        verify(dishShopMapper, never()).update(any(), any());
        ArgumentCaptor<DishStockLog> logCaptor = ArgumentCaptor.forClass(DishStockLog.class);
        verify(dishStockLogMapper).insert(logCaptor.capture());

        DishStockLog log = logCaptor.getValue();
        assertNotNull(log);
        assertEquals("REFUND_NO_RESTORE", log.getChange_type());
        assertEquals(0, log.getDelta());
        assertEquals(5, log.getStock_before());
        assertEquals(5, log.getStock_after());
        assertEquals("菜品变质损耗", log.getRemark());
    }

    @Test
    void testOutOfStockActionSetsStockZeroAndSoldOut() {
        mockDishShop(3, 0, 1);

        OrderDetail detail = new OrderDetail();
        detail.setId(1003);
        detail.setDish_id(101);
        detail.setName("招牌烤肉");
        detail.setQuantity("1");
        detail.setMorder_no("ORD-003");

        stockService.handleRefundStock(detail, 1, 1, RefundStockAction.OUT_OF_STOCK, "cashier:2", "食材用尽缺货估清");

        verify(dishShopMapper).update(isNull(), any());
        verify(pushService).notifyCatalogChanged(eq("stock_sold_out"), eq(101), eq("招牌烤肉"), eq(true));

        ArgumentCaptor<DishStockLog> logCaptor = ArgumentCaptor.forClass(DishStockLog.class);
        verify(dishStockLogMapper).insert(logCaptor.capture());

        DishStockLog log = logCaptor.getValue();
        assertNotNull(log);
        assertEquals("REFUND_OUT_OF_STOCK", log.getChange_type());
        assertEquals(-3, log.getDelta());
        assertEquals(3, log.getStock_before());
        assertEquals(0, log.getStock_after());
        assertEquals("食材用尽缺货估清", log.getRemark());
    }

    @Test
    void testComboHeaderLineIsSkippedFromStockOperation() {
        mockDishShop(10, 0, 1);

        OrderDetail header = new OrderDetail();
        header.setId(2001);
        header.setName("超值双人套餐");
        header.setLine_type("combo_header");
        header.setQuantity("1");

        stockService.handleRefundStock(header, 1, 1, RefundStockAction.RESTORE, "cashier:1", "退整单");

        // combo_header 必须跳过
        verify(dishShopMapper, never()).update(any(), any());
        verify(dishStockLogMapper, never()).insert(any());
    }
}

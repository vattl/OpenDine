package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.baomidou.mybatisplus.core.conditions.AbstractWrapper;
import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import com.lanf.mapper.DishShopMapper;
import com.lanf.service.DishMenuPushService;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collection;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsLackAvailabilityInvariantTest {

    @Test
    void lackSoldOutClearsShopStockAndEnablesTracking() {
        DishShopMapper mapper = mock(DishShopMapper.class);
        DishShop link = new DishShop();
        link.setShop_id(7);
        link.setDish_id(101);
        link.setStock(5);
        when(mapper.selectOne(any())).thenReturn(link);

        KdsLackService service = new KdsLackService();
        ReflectionTestUtils.setField(service, "dishShopMapper", mapper);
        ReflectionTestUtils.setField(service, "dishMenuPushService", mock(DishMenuPushService.class));

        Dish dish = new Dish();
        dish.setId(101);
        dish.setName("测试菜品");
        dish.setOnsale(true);
        ReflectionTestUtils.invokeMethod(service, "markDishSoldOut", 7, dish);

        @SuppressWarnings("rawtypes")
        ArgumentCaptor<Wrapper> update = ArgumentCaptor.forClass(Wrapper.class);
        verify(mapper).update(isNull(), update.capture());
        String sqlSet = update.getValue().getSqlSet();
        assertTrue(sqlSet.contains("stock="));
        assertTrue(sqlSet.contains("stock_enabled="));
        assertTrue(sqlSet.contains("sold_out="));
        Collection<Object> values = ((AbstractWrapper<?, ?, ?>) update.getValue())
                .getParamNameValuePairs().values();
        assertTrue(values.contains(0));
        assertTrue(values.contains(1));
    }
}

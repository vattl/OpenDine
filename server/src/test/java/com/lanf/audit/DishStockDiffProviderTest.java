package com.lanf.audit;

import com.lanf.audit.diff.DishStockDiffProvider;
import com.lanf.entity.DishShop;
import com.lanf.entity.OrderDetail;
import com.lanf.mapper.DishShopMapper;
import com.lanf.service.IOrderDetailService;
import org.junit.Test;
import org.mockito.Mockito;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Map;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/** DishStockDiffProvider：退菜库存前后态捕获。 */
public class DishStockDiffProviderTest {

    @Test
    public void captureReturnsStockState() {
        IOrderDetailService detailService = mock(IOrderDetailService.class);
        DishShopMapper mapper = mock(DishShopMapper.class);

        OrderDetail detail = new OrderDetail();
        detail.setId(1);
        detail.setDish_id(5);
        detail.setQuantity("2");
        when(detailService.getById(1)).thenReturn(detail);

        DishShop shop = new DishShop();
        shop.setDish_id(5);
        shop.setStock(8);
        shop.setStock_enabled(1);
        when(mapper.selectOne(any())).thenReturn(shop);

        DishStockDiffProvider provider = new DishStockDiffProvider();
        ReflectionTestUtils.setField(provider, "orderDetailService", detailService);
        ReflectionTestUtils.setField(provider, "dishShopMapper", mapper);

        Map<String, Object> before = provider.captureBefore("1");
        assertNotNull(before);
        assertEquals(5, before.get("dishId"));
        assertEquals(8, before.get("stock"));
        assertEquals("2", before.get("quantity"));

        Map<String, Object> after = provider.captureAfter("1");
        assertEquals(8, after.get("stock"));
    }

    @Test
    public void missingDetailReturnsNull() {
        IOrderDetailService detailService = mock(IOrderDetailService.class);
        when(detailService.getById(999)).thenReturn(null);
        DishStockDiffProvider provider = new DishStockDiffProvider();
        ReflectionTestUtils.setField(provider, "orderDetailService", detailService);
        ReflectionTestUtils.setField(provider, "dishShopMapper", mock(DishShopMapper.class));

        assertNull(provider.captureBefore("999"));
    }

    @Test
    public void invalidIdReturnsNull() {
        DishStockDiffProvider provider = new DishStockDiffProvider();
        assertNull(provider.captureBefore("abc"));
        assertNull(provider.captureBefore(""));
        assertNull(provider.captureBefore(null));
    }
}

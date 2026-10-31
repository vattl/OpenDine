package com.lanf.util;

import com.lanf.entity.Shop;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class ShopOrderingOpenHelperTest {

    @Test
    void isOrderingOpen_nullShop() {
        assertFalse(ShopOrderingOpenHelper.isOrderingOpen(null));
    }

    @Test
    void isOrderingOpen_openWhenNotZero() {
        Shop shop = new Shop();
        shop.setOrdering_open(1);
        assertTrue(ShopOrderingOpenHelper.isOrderingOpen(shop));
        shop.setOrdering_open(null);
        assertTrue(ShopOrderingOpenHelper.isOrderingOpen(shop));
    }

    @Test
    void isOrderingOpen_closedWhenZero() {
        Shop shop = new Shop();
        shop.setOrdering_open(0);
        assertFalse(ShopOrderingOpenHelper.isOrderingOpen(shop));
    }
}

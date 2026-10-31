package com.lanf.util;

import com.lanf.entity.Shop;

/**
 * 门店 C 端「营业接单」状态（{@code t_shop.ordering_open}）。
 */
public final class ShopOrderingOpenHelper {

    private ShopOrderingOpenHelper() {}

    /** {@code ordering_open != 0} 视为营业中（与 {@code GET /order/getBusiness} 一致）。 */
    public static boolean isOrderingOpen(Shop shop) {
        return shop != null && !Integer.valueOf(0).equals(shop.getOrdering_open());
    }
}

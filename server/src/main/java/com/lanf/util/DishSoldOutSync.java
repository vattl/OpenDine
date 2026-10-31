package com.lanf.util;

import com.lanf.entity.Dish;

/**
 * 根据可售库存同步「已售罄」标记：有限库存且库存为 0（或负数，异常兜底）时 {@code sold_out=1}；否则 {@code sold_out=0}。
 * {@code stock} 为 {@code null} 或 {@code <0} 表示不限量，不标售罄。
 */
public final class DishSoldOutSync {

    private DishSoldOutSync() {}

    public static void applyFromStock(Dish d) {
        if (d == null) {
            return;
        }
        Integer s = d.getStock();
        if (s == null || s < 0) {
            d.setSold_out(0);
            return;
        }
        if (s <= 0) {
            d.setSold_out(1);
        } else {
            d.setSold_out(0);
        }
    }
}

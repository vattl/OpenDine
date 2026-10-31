package com.lanf.payment.support;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Table;

/** 桌台查询门店范围（与 {@code OrderController#appendTableShopScope} 一致）。 */
public final class PaymentTableScopeUtil {

    private PaymentTableScopeUtil() {
    }

    public static void appendTableShopScope(QueryWrapper<Table> qw, Integer shopId) {
        if (qw == null || shopId == null) {
            return;
        }
        if (Integer.valueOf(1).equals(shopId)) {
            qw.and(w -> w.eq("shop_id", 1).or(w2 -> w2.isNull("shop_id")));
        } else {
            qw.eq("shop_id", shopId);
        }
    }
}

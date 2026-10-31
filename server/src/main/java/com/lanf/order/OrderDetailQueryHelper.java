package com.lanf.order;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.OrderDetail;

/**
 * 订单明细查询：有效行 vs 已退菜。
 */
public final class OrderDetailQueryHelper {

    private OrderDetailQueryHelper() {
    }

    public static void onlyActive(QueryWrapper<OrderDetail> q) {
        if (q == null) {
            return;
        }
        q.and(w -> w.isNull("line_status")
                .or()
                .eq("line_status", OrderDetailLineStatus.NORMAL));
    }

    public static boolean isActiveLine(OrderDetail detail) {
        return detail != null && OrderDetailLineStatus.isActive(detail.getLine_status());
    }

    /** 是否参与门店库存扣减/回退（跳过套餐头行）。 */
    public static boolean countsForShopStock(OrderDetail detail) {
        if (!isActiveLine(detail)) {
            return false;
        }
        String lt = detail.getLine_type();
        return lt == null || !"combo_header".equalsIgnoreCase(lt.trim());
    }
}

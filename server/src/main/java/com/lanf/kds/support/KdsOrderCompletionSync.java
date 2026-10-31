package com.lanf.kds.support;

import com.lanf.entity.Order;
import org.springframework.util.StringUtils;

/** 厨显整单完成（40）且门店开启 {@code auto_off_order_on_kds_done} 时，将订单头置为清台（{@code off_order}）。 */
public final class KdsOrderCompletionSync {

    private KdsOrderCompletionSync() {
    }

    public static boolean shouldMarkOffOrder(Order order) {
        if (order == null) {
            return false;
        }
        if ("cancelled".equals(order.getTransac_status())) {
            return false;
        }
        String r = order.getOrder_receiving();
        if (!StringUtils.hasText(r)) {
            return false;
        }
        String t = r.trim();
        if ("off_order".equals(t)) {
            return false;
        }
        return "rec_order".equals(t);
    }
}

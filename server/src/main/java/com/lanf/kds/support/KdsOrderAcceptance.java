package com.lanf.kds.support;

import com.lanf.entity.Order;
import org.springframework.util.StringUtils;

/** KDS 工单是否可对订单推送：须订单头已接单（{@code order_receiving=rec_order}）。 */
public final class KdsOrderAcceptance {

    private KdsOrderAcceptance() {
    }

    public static boolean isAccepted(Order order) {
        if (order == null) {
            return false;
        }
        String r = order.getOrder_receiving();
        return StringUtils.hasText(r) && "rec_order".equals(r.trim());
    }
}

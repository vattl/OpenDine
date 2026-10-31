package com.lanf.service;

import com.lanf.entity.TakeoutDelivery;
import org.springframework.stereotype.Service;

/**
 * 外卖配送履约状态变更时推送 /ws/menu，避免前端/运营端仍显示旧 takeout_dispatch_status。
 */
@Service
public class TakeoutDeliveryStatusNotifier {

    private final DishMenuPushService dishMenuPushService;

    public TakeoutDeliveryStatusNotifier(DishMenuPushService dishMenuPushService) {
        this.dishMenuPushService = dishMenuPushService;
    }

    public void notifyIfChanged(TakeoutDelivery before, TakeoutDelivery after) {
        if (after == null) {
            return;
        }
        if (before != null && statusSame(before, after)) {
            return;
        }
        notifyChanged(after);
    }

    public void notifyChanged(TakeoutDelivery delivery) {
        if (delivery == null || delivery.getOrder_id() == null) {
            return;
        }
        dishMenuPushService.notifyTakeoutDispatchChanged(
                delivery.getShop_id(),
                delivery.getOrder_id(),
                delivery.getOrder_no(),
                delivery.getDispatch_status(),
                delivery.getZsq_dispatch_status(),
                delivery.getZsq_phase());
    }

    private static boolean statusSame(TakeoutDelivery before, TakeoutDelivery after) {
        return eq(before.getDispatch_status(), after.getDispatch_status())
                && eq(before.getZsq_dispatch_status(), after.getZsq_dispatch_status())
                && eq(before.getZsq_phase(), after.getZsq_phase());
    }

    private static boolean eq(String a, String b) {
        return normalize(a).equals(normalize(b));
    }

    private static String normalize(String s) {
        return s == null ? "" : s.trim().toLowerCase();
    }
}

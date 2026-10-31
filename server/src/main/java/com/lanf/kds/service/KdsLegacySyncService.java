package com.lanf.kds.service;

import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsOrderStatus;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.support.KdsOrderCompletionSync;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

/**
 * KDS 状态回写：可选将单品划菜同步至 {@code order_rece}（{@code sync_legacy_rece=1}）；
 * 厨显整单完成（40）时自动清台（{@code order_receiving=off_order}）。
 * 清台不升格厨显为 90（已关闭），90 仅用于结账/取消。
 */
@Service
public class KdsLegacySyncService {

    private static final Logger log = LoggerFactory.getLogger(KdsLegacySyncService.class);

    @Autowired
    private KdsConfigService configService;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private IOrderService orderService;

    public void afterItemStatusChange(int shopId, int orderId, int detailId, int itemStatus) {
        KdsShopConfig cfg = configService.getOrDefault(shopId);
        if (cfg.getSync_legacy_rece() == null || cfg.getSync_legacy_rece() != 1) {
            return;
        }
        if (itemStatus == KdsItemStatus.DONE) {
            OrderDetail detail = orderDetailService.getById(detailId);
            if (detail != null) {
                detail.setOrder_rece("rec_order");
                orderDetailService.updateById(detail);
            }
        }
    }

    public void afterOrderKdsStatus(int shopId, int orderId, int kdsOrderStatus) {
        KdsShopConfig cfg = configService.getOrDefault(shopId);
        if (kdsOrderStatus == KdsOrderStatus.ALL_DONE
                && cfg.getAuto_off_order_on_kds_done() != null
                && cfg.getAuto_off_order_on_kds_done() == 1) {
            markOrderCompleted(orderId);
        }
        if (cfg.getSync_legacy_rece() == null || cfg.getSync_legacy_rece() != 1) {
            return;
        }
        if (kdsOrderStatus == KdsOrderStatus.COOKING || kdsOrderStatus == KdsOrderStatus.PARTIAL) {
            Order order = orderService.getById(orderId);
            if (order != null && !"rec_order".equals(order.getOrder_receiving())) {
                order.setOrder_receiving("rec_order");
                orderService.updateById(order);
            }
        }
    }

    private void markOrderCompleted(int orderId) {
        Order order = orderService.getById(orderId);
        if (!KdsOrderCompletionSync.shouldMarkOffOrder(order)) {
            return;
        }
        order.setOrder_receiving("off_order");
        if (order.getOff_time() == null) {
            order.setOff_time(new java.util.Date());
        }
        orderService.updateById(order);
        log.info("[kds] 厨显整单完成，订单已自动清台: order_no={}", order.getOrder_no());
    }
}

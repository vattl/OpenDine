package com.lanf.kds.event;

import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsOrderStatus;
import com.lanf.kds.delivery.CashierKdsProjectionService;
import com.lanf.kds.service.KdsPushService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * KDS 领域事件 → 副作用（WS 广播）。
 * 统一在事务提交后触发，主流程只发布事件，推送副作用收敛于此，可插拔、可独立测试。
 */
@Component
public class KdsEventListener {

    private static final Logger log = LoggerFactory.getLogger(KdsEventListener.class);

    @Autowired
    private KdsPushService pushService;
    @Autowired
    private CashierKdsProjectionService cashierKdsProjectionService;
    @Autowired(required = false)
    private com.lanf.kds.service.KdsWorkflowV2Service kdsWorkflowV2Service;
    @Autowired(required = false)
    private com.lanf.kds.service.KdsCustomerPickupNoticeService customerPickupNoticeService;
    @Autowired(required = false)
    private com.lanf.service.ITakeoutZsqIntegrationService takeoutZsqIntegrationService;

    /**
     * 整单状态变化 → 广播 {@code order_status_changed}。
     * 补齐差距 A：此前 {@code orderStatusChanged} 已定义却无调用点，整单进度无法实时触达订阅端。
     */
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT, fallbackExecution = true)
    public void onOrderStatusChanged(KdsOrderStatusChangedEvent e) {
        try {
            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("order_id", e.getOrderId());
            payload.put("order_no", e.getOrderNo());
            payload.put("from_status", e.getFromStatus());
            payload.put("kds_order_status", e.getToStatus());
            // screenTag=null 由 pushService 内部扇出到全部订阅桶
            pushService.orderStatusChanged(e.getShopId(), null, e.getToStatus(), payload);
            if (e.getToStatus() == KdsOrderStatus.ALL_DONE) {
                if (customerPickupNoticeService != null) {
                    try {
                        customerPickupNoticeService.notifyCustomerPickup(e.getShopId(), e.getOrderId());
                    } catch (Exception ex) {
                        log.warn("[kds] 全部菜品完成自动通知客户取餐异常 order={}: {}", e.getOrderId(), ex.getMessage());
                    }
                }
                if (takeoutZsqIntegrationService != null) {
                    try {
                        takeoutZsqIntegrationService.tryAutoDispatchOnKdsCompleted(e.getOrderId());
                    } catch (Exception ex) {
                        log.warn("[kds] 全部菜品完成外卖自动叫骑手异常 order={}: {}", e.getOrderId(), ex.getMessage());
                    }
                }
            }
        } catch (Exception ex) {
            log.warn("[kds] order_status_changed push failed order={}: {}", e.getOrderId(), ex.getMessage());
        }
    }

    @TransactionalEventListener(phase = TransactionPhase.BEFORE_COMMIT, fallbackExecution = true)
    public void recordOrderClosed(KdsOrderStatusChangedEvent e) {
        if (e.getToStatus() == KdsOrderStatus.ALL_DONE) {
            cashierKdsProjectionService.publishAfterCommit(e.getOrderId(), "ORDER_CLOSED", null, null, null);
        }
    }

    /**
     * 单品/队列变化 → 广播 {@code update_order}（void 时 {@code cancel_item}）。
     */
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT, fallbackExecution = true)
    public void onItemStatusChanged(KdsItemStatusChangedEvent e) {
        try {
            Map<String, Object> payload = new LinkedHashMap<>(e.getPayload());
            payload.putIfAbsent("detail_id", e.getDetailId());
            if (e.getOrderId() != null) {
                payload.putIfAbsent("order_id", e.getOrderId());
            }
            if (e.getWorkflowQueue() != null) {
                payload.putIfAbsent("workflow_queue", e.getWorkflowQueue());
            }
            if (e.getToStatus() == KdsItemStatus.VOID) {
                pushService.cancelItem(e.getShopId(), e.getScreenTag(), payload);
            } else {
                pushService.updateOrder(e.getShopId(), e.getScreenTag(), payload);
            }
        } catch (Exception ex) {
            log.warn("[kds] item status push failed detail={}: {}", e.getDetailId(), ex.getMessage());
        }
    }

    /**
     * 配置变化 → 广播 {@code config_changed}，厨显端收到后刷新本机设置。
     */
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT, fallbackExecution = true)
    public void onConfigChanged(KdsConfigChangedEvent e) {
        try {
            Map<String, Object> payload = new LinkedHashMap<>(e.getChangedFields());
            pushService.configChanged(e.getShopId(), payload);
            if (kdsWorkflowV2Service != null) {
                kdsWorkflowV2Service.broadcastConfigChanged(e.getShopId(), payload);
            }
        } catch (Exception ex) {
            log.warn("[kds] config_changed push failed shop={}: {}", e.getShopId(), ex.getMessage());
        }
    }
}

package com.lanf.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.event.DishCatalogChangedEvent;
import com.lanf.notify.service.UnifiedNotificationService;
import com.lanf.realtime.DishMenuWebSocketHub;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.Map;

/**
 * 向点餐端 WebSocket（/ws/menu）推送：菜品变更、营业状态、自动接单开关等，
 * 并双轨同步桥接至统一实时消息通道（/ws/v1/notify）。
 */
@Service
public class DishMenuPushService {

    private static final Logger log = LoggerFactory.getLogger(DishMenuPushService.class);

    /** 推送专用，不依赖 HTTP 层的 Jackson 配置 */
    private final ObjectMapper pushJsonMapper = new ObjectMapper();

    @Autowired
    private ApplicationEventPublisher eventPublisher;

    @Autowired
    private DishMenuWebSocketHub webSocketHub;

    @Autowired(required = false)
    private UnifiedNotificationService unifiedNotificationService;

    public void setUnifiedNotificationService(UnifiedNotificationService unifiedNotificationService) {
        this.unifiedNotificationService = unifiedNotificationService;
    }

    /**
     * @param action   如 updateOnSale、save_update、save_new、delete、sort
     * @param dishId   可为 null（如 sort 仅刷新）
     * @param dishName 可为 null
     * @param onsale   下架 false / 上架 true；删除或非上下架场景可为 null
     */
    public void notifyCatalogChanged(String action, Integer dishId, String dishName, Boolean onsale) {
        if (eventPublisher != null) {
            eventPublisher.publishEvent(new DishCatalogChangedEvent(this, action, dishId, dishName, onsale));
        }
        if (unifiedNotificationService != null) {
            try {
                unifiedNotificationService.publishDishCatalogChanged(action, dishId, dishName, onsale);
            } catch (Exception e) {
                log.warn("[ws-menu] unified bridge dish_catalog_changed failed: {}", e.getMessage());
            }
        }
        Map<String, Object> extra = new HashMap<>();
        extra.put("action", action);
        extra.put("dishId", dishId);
        extra.put("dishName", dishName);
        extra.put("onsale", onsale);
        broadcastTyped("dish_catalog_changed", extra);
    }

    /**
     * 营业状态变更（对应 {@code POST /order/ChangeBusiness}，body.bus=1 营业 / 其它 休息）。
     *
     * @param shopId 门店 id，推送载荷中带 {@code shopId} 供多端按店过滤；可为 null（不推荐）
     */
    public void notifyBusinessChanged(boolean business, Integer shopId) {
        if (unifiedNotificationService != null) {
            try {
                unifiedNotificationService.publishShopBusinessChanged(business, shopId);
            } catch (Exception e) {
                log.warn("[ws-menu] unified bridge business_changed failed: {}", e.getMessage());
            }
        }
        Map<String, Object> extra = new HashMap<>();
        extra.put("business", business);
        if (shopId != null) {
            extra.put("shopId", shopId);
        }
        broadcastTyped("business_changed", extra);
    }

    /**
     * @deprecated v1.2.71 起自动接单随门店营业状态，不再使用独立开关。
     */
    @Deprecated
    public void notifyAutoAcceptChanged(boolean enabled) {
        Map<String, Object> extra = new HashMap<>();
        extra.put("enabled", enabled);
        broadcastTyped("auto_accept_changed", extra);
    }

    /**
     * 外卖配送异常告警（如真省钱骑手取消），运营端可监听 /ws/menu 的 takeout_dispatch_alert。
     */
    public void notifyTakeoutDispatchAlert(String alertType, Integer shopId, Integer orderId,
                                           String orderNo, String message, Long zsqOpenOrderId) {
        if (unifiedNotificationService != null) {
            try {
                unifiedNotificationService.publishTakeoutDispatchAlert(
                        alertType, shopId, orderId, orderNo, message, zsqOpenOrderId);
            } catch (Exception e) {
                log.warn("[ws-menu] unified bridge takeout_dispatch_alert failed: {}", e.getMessage());
            }
        }
        Map<String, Object> extra = new HashMap<>();
        extra.put("alertType", alertType);
        if (shopId != null) {
            extra.put("shopId", shopId);
        }
        if (orderId != null) {
            extra.put("orderId", orderId);
        }
        if (orderNo != null) {
            extra.put("orderNo", orderNo);
        }
        if (message != null) {
            extra.put("message", message);
        }
        if (zsqOpenOrderId != null) {
            extra.put("zsqOpenOrderId", zsqOpenOrderId);
        }
        broadcastTyped("takeout_dispatch_alert", extra);
    }

    /**
     * 外卖配送履约状态变更（接单/配送中/完成/取消/异常等），客户端宜刷新订单或 delivery 摘要。
     */
    public void notifyTakeoutDispatchChanged(Integer shopId, Integer orderId, String orderNo,
                                             String dispatchStatus, String zsqDispatchStatus, String zsqPhase) {
        if (unifiedNotificationService != null) {
            try {
                unifiedNotificationService.publishTakeoutDispatchChanged(
                        shopId, orderId, orderNo, dispatchStatus, zsqDispatchStatus, zsqPhase);
            } catch (Exception e) {
                log.warn("[ws-menu] unified bridge takeout_dispatch_changed failed: {}", e.getMessage());
            }
        }
        Map<String, Object> extra = new HashMap<>();
        if (shopId != null) {
            extra.put("shopId", shopId);
        }
        if (orderId != null) {
            extra.put("orderId", orderId);
        }
        if (orderNo != null) {
            extra.put("orderNo", orderNo);
        }
        if (dispatchStatus != null) {
            extra.put("dispatchStatus", dispatchStatus);
            extra.put("takeout_dispatch_status", dispatchStatus);
        }
        if (zsqDispatchStatus != null) {
            extra.put("zsqDispatchStatus", zsqDispatchStatus);
        }
        if (zsqPhase != null) {
            extra.put("zsqPhase", zsqPhase);
        }
        broadcastTyped("takeout_dispatch_changed", extra);
    }

    /**
     * 全部菜品制作并出餐完成，广播取餐就绪通知至点餐端 /ws/menu。
     */
    public void notifyMealPickupReady(Integer shopId, Integer orderId, String orderNo,
                                      String tableNumber, String dineInOrTakeOut, String pickupCode) {
        if (unifiedNotificationService != null) {
            try {
                unifiedNotificationService.publishMealPickupReady(
                        shopId, orderId, orderNo, tableNumber, dineInOrTakeOut, pickupCode);
            } catch (Exception e) {
                log.warn("[ws-menu] unified bridge meal_pickup_ready failed: {}", e.getMessage());
            }
        }
        Map<String, Object> extra = new HashMap<>();
        if (shopId != null) {
            extra.put("shopId", shopId);
        }
        if (orderId != null) {
            extra.put("orderId", orderId);
        }
        if (orderNo != null) {
            extra.put("orderNo", orderNo);
        }
        if (tableNumber != null) {
            extra.put("tableNumber", tableNumber);
        }
        if (dineInOrTakeOut != null) {
            extra.put("dineInOrTakeOut", dineInOrTakeOut);
        }
        if (pickupCode != null) {
            extra.put("pickupCode", pickupCode);
        }
        extra.put("notice", 1);
        extra.put("status", "ready_for_pickup");
        extra.put("message", "您的餐品已制作完成，请取餐");
        broadcastTyped("meal_pickup_ready", extra);
    }

    private void broadcastTyped(String type, Map<String, Object> fields) {
        try {
            Map<String, Object> payload = new HashMap<>();
            if (fields != null) {
                payload.putAll(fields);
            }
            payload.put("type", type);
            payload.put("ts", System.currentTimeMillis());
            String json = pushJsonMapper.writeValueAsString(payload);
            webSocketHub.broadcast(json);
        } catch (Exception e) {
            log.warn("[ws-menu] broadcast type={} failed: {}", type, e.getMessage());
        }
    }
}

package com.lanf.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.TakeoutDelivery;
import com.lanf.integration.web.dto.ZsqRiderTrackingResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 外卖配送异常告警：写 t_operation_log，并经 /ws/menu 推送运营端。
 */
@Service
public class TakeoutDispatchAlertService {

    private static final Logger log = LoggerFactory.getLogger(TakeoutDispatchAlertService.class);

    public static final String MODULE_TAKEOUT = "takeout";
    public static final String ACTION_RIDER_CANCELLED = "zsq_rider_cancelled";
    public static final String ACTION_ORDER_MISSING = "zsq_order_missing";

    private final IOperationLogService operationLogService;
    private final DishMenuPushService dishMenuPushService;
    private final ObjectMapper objectMapper;

    public TakeoutDispatchAlertService(IOperationLogService operationLogService,
                                       DishMenuPushService dishMenuPushService,
                                       ObjectMapper objectMapper) {
        this.operationLogService = operationLogService;
        this.dishMenuPushService = dishMenuPushService;
        this.objectMapper = objectMapper;
    }

    /**
     * 真省钱侧骑手/平台取消配送（首次识别为 rider_cancelled 时调用）。
     */
    public void onRiderCancelled(TakeoutDelivery delivery, ZsqRiderTrackingResponse tracking) {
        if (delivery == null) {
            return;
        }
        String orderNo = delivery.getOrder_no();
        String message = delivery.getZsq_last_error() != null
                ? delivery.getZsq_last_error()
                : "骑手或平台取消配送，可重发配送";

        Map<String, Object> snapshot = new LinkedHashMap<>();
        snapshot.put("orderId", delivery.getOrder_id());
        snapshot.put("orderNo", orderNo);
        snapshot.put("shopId", delivery.getShop_id());
        snapshot.put("zsqOpenOrderId", delivery.getZsq_open_order_id());
        snapshot.put("zsqPhase", tracking != null ? tracking.getPhase() : delivery.getZsq_phase());
        snapshot.put("deliverySendStatus", tracking != null ? tracking.getDeliverySendStatus() : delivery.getZsq_delivery_send_status());
        if (tracking != null && tracking.getRider() != null) {
            snapshot.put("riderName", tracking.getRider().getName());
            snapshot.put("riderPhone", tracking.getRider().getPhone());
        } else {
            snapshot.put("riderName", delivery.getZsq_rider_name());
            snapshot.put("riderPhone", delivery.getZsq_rider_phone());
        }
        snapshot.put("message", message);

        String snapshotJson = toJson(snapshot);
        try {
            operationLogService.recordSystem(
                    delivery.getShop_id(),
                    MODULE_TAKEOUT,
                    ACTION_RIDER_CANCELLED,
                    orderNo,
                    snapshotJson);
        } catch (Exception e) {
            log.warn("骑手取消操作日志写入失败 orderNo={}: {}", orderNo, e.getMessage());
        }

        dishMenuPushService.notifyTakeoutDispatchAlert(
                "rider_cancelled",
                delivery.getShop_id(),
                delivery.getOrder_id(),
                orderNo,
                message,
                delivery.getZsq_open_order_id());

        log.warn("外卖配送被骑手/平台取消 orderNo={} zsqOpenOrderId={} shopId={}",
                orderNo, delivery.getZsq_open_order_id(), delivery.getShop_id());
    }

    /** 真省钱侧订单被删除或已不存在（首次识别时调用）。 */
    public void onRemoteOrderMissing(TakeoutDelivery delivery, Long missingOpenOrderId) {
        if (delivery == null) {
            return;
        }
        String message = delivery.getZsq_last_error() != null
                ? delivery.getZsq_last_error()
                : "真省钱配送订单不存在或已删除，可重新下单配送";
        Map<String, Object> snapshot = new LinkedHashMap<>();
        snapshot.put("orderId", delivery.getOrder_id());
        snapshot.put("orderNo", delivery.getOrder_no());
        snapshot.put("shopId", delivery.getShop_id());
        snapshot.put("zsqOpenOrderId", missingOpenOrderId);
        snapshot.put("zsqPhase", delivery.getZsq_phase());
        snapshot.put("message", message);

        try {
            operationLogService.recordSystem(
                    delivery.getShop_id(), MODULE_TAKEOUT, ACTION_ORDER_MISSING,
                    delivery.getOrder_no(), toJson(snapshot));
        } catch (Exception e) {
            log.warn("真省钱订单失效操作日志写入失败 orderNo={}: {}",
                    delivery.getOrder_no(), e.getMessage());
        }

        dishMenuPushService.notifyTakeoutDispatchAlert(
                "order_missing", delivery.getShop_id(), delivery.getOrder_id(),
                delivery.getOrder_no(), message, missingOpenOrderId);
        log.warn("真省钱配送订单不存在或已删除 orderNo={} zsqOpenOrderId={} shopId={}",
                delivery.getOrder_no(), missingOpenOrderId, delivery.getShop_id());
    }

    private String toJson(Map<String, Object> map) {
        try {
            return objectMapper.writeValueAsString(map);
        } catch (JsonProcessingException e) {
            return map.toString();
        }
    }
}

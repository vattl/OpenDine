package com.lanf.notify.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.ActivityPopup;
import com.lanf.entity.Announcement;
import com.lanf.entity.Coupon;
import com.lanf.entity.Order;
import com.lanf.entity.QueueTicket;
import com.lanf.entity.RealtimeNotification;
import com.lanf.entity.UserCoupon;
import com.lanf.mapper.RealtimeNotificationMapper;
import com.lanf.realtime.UnifiedMessageEnvelope;
import com.lanf.realtime.UnifiedSessionRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.util.StringUtils;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 统一实时消息发布、持久化发件箱、增量同步（Sync）与跨终端确认消除（ACK）核心服务。
 */
@Service
public class UnifiedNotificationService {

    private static final Logger log = LoggerFactory.getLogger(UnifiedNotificationService.class);

    public static final long DEFAULT_TTL_P0_MS = 24 * 60 * 60 * 1000L; // 24h
    public static final long DEFAULT_TTL_P1_MS = 12 * 60 * 60 * 1000L; // 12h
    public static final long DEFAULT_TTL_P2_MS = 2 * 60 * 60 * 1000L;  // 2h

    private final RealtimeNotificationMapper notificationMapper;
    private final UnifiedSessionRegistry sessionRegistry;
    private final WechatCouponSubscribePushService wechatCouponSubscribePushService;
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final AtomicLong fallbackSeqGenerator = new AtomicLong(1000L);

    @Autowired
    public UnifiedNotificationService(@Autowired(required = false) RealtimeNotificationMapper notificationMapper,
                                      UnifiedSessionRegistry sessionRegistry,
                                      @Autowired(required = false) WechatCouponSubscribePushService wechatCouponSubscribePushService) {
        this.notificationMapper = notificationMapper;
        this.sessionRegistry = sessionRegistry;
        this.wechatCouponSubscribePushService = wechatCouponSubscribePushService;
    }

    /**
     * 获取当前全局或门店最新 seq_id 游标。
     */
    public long currentServerHeadSeqId(Integer shopId) {
        if (notificationMapper != null) {
            try {
                Long max = (shopId != null && shopId > 0)
                        ? notificationMapper.selectShopMaxSeqId(shopId)
                        : notificationMapper.selectMaxSeqId();
                if (max != null && max > 0) {
                    return max;
                }
            } catch (Exception ignored) {
                // Fallback to in-memory sequence in unit tests without DB
            }
        }
        return fallbackSeqGenerator.get();
    }

    /**
     * 检验 message_id 是否已持久化（用于超时巡检幂等去重）。
     */
    public boolean existsByMessageId(String messageId) {
        if (!StringUtils.hasText(messageId) || notificationMapper == null) {
            return false;
        }
        try {
            Integer cnt = notificationMapper.selectCount(
                    new QueryWrapper<RealtimeNotification>().eq("message_id", messageId.trim()));
            return cnt != null && cnt > 0;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * 核心发布入口：持久化 P0/P1/P2 消息，并在事务提交后（afterCommit）通过 WebSocket 推送。
     */
    public UnifiedMessageEnvelope publish(UnifiedMessageEnvelope envelope) {
        if (envelope == null) {
            return null;
        }
        long nowMs = System.currentTimeMillis();
        if (envelope.getFrame_type() == null) {
            envelope.setFrame_type("EVENT");
        }
        if (!StringUtils.hasText(envelope.getMessage_id())) {
            envelope.setMessage_id("ntf_" + UUID.randomUUID().toString().replace("-", ""));
        }
        if (envelope.getTimestamp() == null || envelope.getTimestamp() <= 0) {
            envelope.setTimestamp(nowMs);
        }
        String priority = StringUtils.hasText(envelope.getPriority()) ? envelope.getPriority().trim().toUpperCase() : "P2";
        envelope.setPriority(priority);
        if (envelope.getRequire_ack() == null) {
            envelope.setRequire_ack("P0".equals(priority) || "P1".equals(priority));
        }
        if (envelope.getExpire_at() == null || envelope.getExpire_at() <= 0) {
            long ttl = "P0".equals(priority) ? DEFAULT_TTL_P0_MS
                    : ("P1".equals(priority) ? DEFAULT_TTL_P1_MS : DEFAULT_TTL_P2_MS);
            envelope.setExpire_at(nowMs + ttl);
        }

        // P3 瞬态广播不落库，直接推送
        if ("P3".equals(priority)) {
            envelope.setSeq_id(0L);
            runAfterCommitOrNow(() -> dispatchEnvelope(envelope, null));
            return envelope;
        }

        // 幂等检查：若相同 message_id 已存在则直接返回已有记录，避免重复落库与重复轰炸
        if (notificationMapper != null) {
            try {
                RealtimeNotification existing = notificationMapper.selectOne(
                        new QueryWrapper<RealtimeNotification>()
                                .eq("message_id", envelope.getMessage_id())
                                .last("LIMIT 1"));
                if (existing != null) {
                    envelope.setSeq_id(existing.getSeq_id());
                    return envelope;
                }
            } catch (Exception e) {
                log.debug("[notify] idempotency lookup skipped for message_id={}: {}", envelope.getMessage_id(), e.getMessage());
            }
        }

        RealtimeNotification record = toEntity(envelope, nowMs);
        Long seqId = null;
        if (notificationMapper != null) {
            try {
                notificationMapper.insert(record);
                seqId = record.getSeq_id();
            } catch (Exception e) {
                log.warn("[notify] insert t_realtime_notification failed message_id={}: {}", envelope.getMessage_id(), e.getMessage());
            }
        }
        if (seqId == null || seqId <= 0) {
            seqId = fallbackSeqGenerator.incrementAndGet();
        }
        envelope.setSeq_id(seqId);

        runAfterCommitOrNow(() -> dispatchEnvelope(envelope, null));
        return envelope;
    }

    /**
     * 业务事件 1：新订单支付成功通知（P1，收银端顶部横幅 + 语音播报）。
     */
    public UnifiedMessageEnvelope publishNewOrderPaid(Order order, double paidYuan) {
        if (order == null || !StringUtils.hasText(order.getOrder_no())) {
            return null;
        }
        String orderNo = order.getOrder_no().trim();
        int shopId = order.getShop_id() != null && order.getShop_id() > 0 ? order.getShop_id() : 1;
        String diningType = StringUtils.hasText(order.getDineInOrTakeOut()) ? order.getDineInOrTakeOut().trim() : "堂食";
        String tableNumber = StringUtils.hasText(order.getTable_number()) ? order.getTable_number().trim() : "";

        String ttsText = StringUtils.hasText(tableNumber)
                ? String.format("您有新的%s订单，桌号%s，实付%.2f元，请及时处理", diningType, tableNumber, paidYuan)
                : String.format("您有新的%s订单，实付%.2f元，请及时处理", diningType, paidYuan);

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("order_id", order.getId());
        payload.put("order_no", orderNo);
        payload.put("shop_id", shopId);
        payload.put("table_number", tableNumber);
        payload.put("dine_in_or_take_out", diningType);
        payload.put("paid_amount", Math.round(paidYuan * 100.0) / 100.0);
        payload.put("payment_method", order.getPayment_method());
        payload.put("order_channel", order.getOrder_channel());

        UnifiedMessageEnvelope envelope = UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id("ntf_order_paid_" + orderNo)
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope("SHOP")
                        .shop_id(shopId)
                        .client_type(UnifiedSessionRegistry.CLIENT_TYPE_CASHIER)
                        .build())
                .business_type("ORDER")
                .event_type("NEW_ORDER_PAID")
                .priority("P1")
                .require_ack(true)
                .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                        .ui_type("TOP_BANNER_AND_VOICE")
                        .sound("VOICE_NEW_ORDER")
                        .tts_text(ttsText)
                        .duration_ms(8000L)
                        .repeat_interval_ms(0L)
                        .action_text("查看订单")
                        .action_route("/cashier/orders?orderNo=" + orderNo)
                        .build())
                .payload(payload)
                .build();

        return publish(envelope);
    }

    /**
     * 业务事件 2：订单出餐超时告警（P0，基于后台门店动态阈值触发，常驻告警条 + 循环语音提醒）。
     */
    public UnifiedMessageEnvelope publishOrderPrepTimeout(Order order, int timeoutThresholdMinutes,
                                                          int elapsedMinutes, int repeatIntervalSeconds) {
        if (order == null || !StringUtils.hasText(order.getOrder_no())) {
            return null;
        }
        String orderNo = order.getOrder_no().trim();
        int shopId = order.getShop_id() != null && order.getShop_id() > 0 ? order.getShop_id() : 1;
        String diningType = StringUtils.hasText(order.getDineInOrTakeOut()) ? order.getDineInOrTakeOut().trim() : "堂食";
        String tableNumber = StringUtils.hasText(order.getTable_number()) ? order.getTable_number().trim() : "";

        String locationLabel = StringUtils.hasText(tableNumber) ? ("桌号" + tableNumber) : ("订单尾号" + tail4(orderNo));
        String ttsText = String.format("注意，%s已超过%d分钟未出餐，请及时处理", locationLabel, timeoutThresholdMinutes);

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("order_id", order.getId());
        payload.put("order_no", orderNo);
        payload.put("shop_id", shopId);
        payload.put("table_number", tableNumber);
        payload.put("dine_in_or_take_out", diningType);
        payload.put("pay_time", order.getPay_time() != null ? order.getPay_time().getTime() : null);
        payload.put("timeout_threshold_minutes", timeoutThresholdMinutes);
        payload.put("elapsed_minutes", elapsedMinutes);

        long repeatMs = Math.max(15, repeatIntervalSeconds) * 1000L;

        UnifiedMessageEnvelope envelope = UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id("ntf_timeout_" + orderNo + "_stage1")
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope("SHOP")
                        .shop_id(shopId)
                        .client_type(UnifiedSessionRegistry.CLIENT_TYPE_CASHIER)
                        .build())
                .business_type("ORDER")
                .event_type("ORDER_PREP_TIMEOUT")
                .priority("P0")
                .require_ack(true)
                .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                        .ui_type("PERSISTENT_ALERT_BANNER")
                        .sound("VOICE_TIMEOUT_ALERT")
                        .tts_text(ttsText)
                        .duration_ms(0L)
                        .repeat_interval_ms(repeatMs)
                        .action_text("立即处理")
                        .action_route("/cashier/orders?orderNo=" + orderNo)
                        .build())
                .payload(payload)
                .build();

        return publish(envelope);
    }

    /**
     * 业务事件 3：新优惠券到账实时通知（P1，C端在线走 WebSocket 弹窗/横幅 + 800ms 聚合，离线降级微信订阅消息）。
     */
    public UnifiedMessageEnvelope publishCouponGranted(UserCoupon userCoupon, Coupon coupon) {
        if (userCoupon == null || !StringUtils.hasText(userCoupon.getUser_openid())) {
            return null;
        }
        String openid = userCoupon.getUser_openid().trim();
        String couponName = (coupon != null && StringUtils.hasText(coupon.getCoupon_name()))
                ? coupon.getCoupon_name().trim()
                : "专属优惠券";
        String couponType = coupon != null ? coupon.getCoupon_type() : "full_reduction";
        Double discountValue = (coupon != null && coupon.getDiscount_value() != null)
                ? coupon.getDiscount_value().doubleValue()
                : null;
        Double minAmount = (coupon != null && coupon.getMin_amount() != null)
                ? coupon.getMin_amount().doubleValue()
                : 0.0;
        String expireTimeStr = userCoupon.getExpire_time() != null
                ? new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(userCoupon.getExpire_time())
                : (coupon != null && coupon.getEnd_time() != null
                        ? new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(coupon.getEnd_time())
                        : "-");

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("user_coupon_id", userCoupon.getId());
        payload.put("coupon_id", userCoupon.getCoupon_id());
        payload.put("coupon_name", couponName);
        payload.put("coupon_type", couponType);
        payload.put("discount_value", discountValue);
        payload.put("min_amount", minAmount);
        payload.put("expire_time", expireTimeStr);
        payload.put("grant_count", 1);

        String messageId = userCoupon.getId() != null
                ? "ntf_coupon_" + userCoupon.getId()
                : "ntf_coupon_" + UUID.randomUUID().toString().replace("-", "");

        UnifiedMessageEnvelope envelope = UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id(messageId)
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope("USER")
                        .openid(openid)
                        .client_type(UnifiedSessionRegistry.CLIENT_TYPE_MINI_PROGRAM)
                        .build())
                .business_type("COUPON")
                .event_type("COUPON_GRANTED")
                .priority("P1")
                .require_ack(true)
                .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                        .ui_type("COUPON_MODAL_OR_TOAST")
                        .sound("SOUND_COUPON")
                        .duration_ms(6000L)
                        .repeat_interval_ms(0L)
                        .aggregation_key("COUPON_GRANTED")
                        .aggregation_window_ms(800L)
                        .action_text("去使用")
                        .action_route("/pages/coupons/index")
                        .build())
                .payload(payload)
                .build();

        long nowMs = System.currentTimeMillis();
        envelope.setTimestamp(nowMs);
        envelope.setExpire_at(nowMs + DEFAULT_TTL_P1_MS);

        RealtimeNotification record = toEntity(envelope, nowMs);
        Long seqId = null;
        if (notificationMapper != null) {
            try {
                notificationMapper.insert(record);
                seqId = record.getSeq_id();
            } catch (Exception e) {
                log.warn("[notify] insert coupon notification failed message_id={}: {}", messageId, e.getMessage());
            }
        }
        if (seqId == null || seqId <= 0) {
            seqId = fallbackSeqGenerator.incrementAndGet();
        }
        envelope.setSeq_id(seqId);

        final String discountDesc = formatCouponDiscountDesc(couponType, discountValue, minAmount);
        runAfterCommitOrNow(() -> {
            int sent = sessionRegistry.sendToUser(openid, null, envelope);
            if (sent <= 0 && wechatCouponSubscribePushService != null) {
                wechatCouponSubscribePushService.sendCouponGrantedSubscribeMessage(
                        openid, couponName, discountDesc, expireTimeStr, "优惠券已放入您的卡包，点击立即使用");
            }
        });
        return envelope;
    }

    /**
     * 业务事件 4：优惠券即将过期临期提醒（P2，C端在线展示底部悬浮 SnackBar，离线降级微信订阅消息）。
     */
    public UnifiedMessageEnvelope publishCouponExpiringSoon(UserCoupon userCoupon, Coupon coupon, long remainingMinutes) {
        if (userCoupon == null || !StringUtils.hasText(userCoupon.getUser_openid())) {
            return null;
        }
        String openid = userCoupon.getUser_openid().trim();
        String couponName = (coupon != null && StringUtils.hasText(coupon.getCoupon_name()))
                ? coupon.getCoupon_name().trim()
                : "专属优惠券";
        String couponType = coupon != null ? coupon.getCoupon_type() : "full_reduction";
        Double discountValue = (coupon != null && coupon.getDiscount_value() != null)
                ? coupon.getDiscount_value().doubleValue()
                : null;
        Double minAmount = (coupon != null && coupon.getMin_amount() != null)
                ? coupon.getMin_amount().doubleValue()
                : 0.0;
        String expireTimeStr = userCoupon.getExpire_time() != null
                ? new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(userCoupon.getExpire_time())
                : "-";

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("user_coupon_id", userCoupon.getId());
        payload.put("coupon_id", userCoupon.getCoupon_id());
        payload.put("coupon_name", couponName);
        payload.put("coupon_type", couponType);
        payload.put("discount_value", discountValue);
        payload.put("min_amount", minAmount);
        payload.put("expire_time", expireTimeStr);
        payload.put("remaining_minutes", Math.max(1L, remainingMinutes));

        String messageId = userCoupon.getId() != null
                ? "ntf_coupon_exp_" + userCoupon.getId()
                : "ntf_coupon_exp_" + UUID.randomUUID().toString().replace("-", "");

        UnifiedMessageEnvelope envelope = UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id(messageId)
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope("USER")
                        .openid(openid)
                        .client_type(UnifiedSessionRegistry.CLIENT_TYPE_MINI_PROGRAM)
                        .build())
                .business_type("COUPON")
                .event_type("COUPON_EXPIRING_SOON")
                .priority("P2")
                .require_ack(true)
                .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                        .ui_type("BOTTOM_SNACKBAR")
                        .sound("NONE")
                        .duration_ms(6000L)
                        .repeat_interval_ms(0L)
                        .action_text("去使用")
                        .action_route("/pages/index/index")
                        .build())
                .payload(payload)
                .build();

        long nowMs = System.currentTimeMillis();
        envelope.setTimestamp(nowMs);
        envelope.setExpire_at(userCoupon.getExpire_time() != null
                ? userCoupon.getExpire_time().getTime()
                : (nowMs + DEFAULT_TTL_P2_MS));

        RealtimeNotification record = toEntity(envelope, nowMs);
        Long seqId = null;
        if (notificationMapper != null) {
            try {
                notificationMapper.insert(record);
                seqId = record.getSeq_id();
            } catch (Exception e) {
                log.warn("[notify] insert expiring coupon notification failed message_id={}: {}", messageId, e.getMessage());
            }
        }
        if (seqId == null || seqId <= 0) {
            seqId = fallbackSeqGenerator.incrementAndGet();
        }
        envelope.setSeq_id(seqId);

        final String discountDesc = formatCouponDiscountDesc(couponType, discountValue, minAmount);
        runAfterCommitOrNow(() -> {
            int sent = sessionRegistry.sendToUser(openid, null, envelope);
            if (sent <= 0 && wechatCouponSubscribePushService != null) {
                wechatCouponSubscribePushService.sendCouponExpiringSubscribeMessage(
                        openid, couponName, discountDesc, expireTimeStr, "优惠券即将到期，快去点餐使用吧");
            }
        });
        return envelope;
    }

    /**
     * 桥接事件：收银端 KDS 投递游标唤醒（P2，静默触发增量同步）。
     */
    public UnifiedMessageEnvelope publishKdsDeliveryAvailable(int shopId, long headCursor) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("type", "kds_delivery_available");
        payload.put("shopId", shopId);
        payload.put("headCursor", headCursor);

        UnifiedMessageEnvelope envelope = UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id("ntf_kds_wake_" + shopId + "_" + headCursor)
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope("SHOP")
                        .shop_id(shopId)
                        .client_type(UnifiedSessionRegistry.CLIENT_TYPE_CASHIER)
                        .build())
                .business_type("KDS")
                .event_type("KDS_DELIVERY_AVAILABLE")
                .priority("P2")
                .require_ack(false)
                .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                        .ui_type("SILENT_INVALIDATE")
                        .sound("NONE")
                        .duration_ms(0L)
                        .build())
                .payload(payload)
                .build();
        return publish(envelope);
    }

    /**
     * 桥接事件：桌台订单状态变更（P2，静默刷新桌台图与订单列表）。
     */
    public UnifiedMessageEnvelope publishTableOrderChanged(int shopId, String tableNumber, String orderNo, int diners) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("type", "table_order_changed");
        payload.put("shopId", shopId);
        payload.put("tableNumber", tableNumber != null ? tableNumber : "");
        payload.put("orderNo", orderNo != null ? orderNo : "");
        payload.put("diners", diners);

        UnifiedMessageEnvelope envelope = UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id("ntf_table_" + shopId + "_" + (orderNo != null ? orderNo : "") + "_" + System.nanoTime())
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope("SHOP")
                        .shop_id(shopId)
                        .client_type(UnifiedSessionRegistry.CLIENT_TYPE_ALL)
                        .build())
                .business_type("TABLE")
                .event_type("TABLE_ORDER_CHANGED")
                .priority("P2")
                .require_ack(false)
                .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                        .ui_type("SILENT_INVALIDATE")
                        .sound("NONE")
                        .duration_ms(0L)
                        .build())
                .payload(payload)
                .build();
        return publish(envelope);
    }

    /**
     * 桥接事件：菜品目录/上下架/沽清变更（P3 瞬态广播）。
     */
    public UnifiedMessageEnvelope publishDishCatalogChanged(String action, Integer dishId, String dishName, Boolean onsale) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("type", "dish_catalog_changed");
        payload.put("action", action);
        payload.put("dishId", dishId);
        payload.put("dishName", dishName);
        payload.put("onsale", onsale);

        UnifiedMessageEnvelope envelope = UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id("ntf_dish_" + (dishId != null ? dishId : "all") + "_" + System.nanoTime())
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope("BROADCAST")
                        .shop_id(0)
                        .client_type(UnifiedSessionRegistry.CLIENT_TYPE_ALL)
                        .build())
                .business_type("MENU")
                .event_type("DISH_CATALOG_CHANGED")
                .priority("P3")
                .require_ack(false)
                .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                        .ui_type("SILENT_INVALIDATE")
                        .sound("NONE")
                        .duration_ms(0L)
                        .build())
                .payload(payload)
                .build();
        return publish(envelope);
    }

    /**
     * 桥接事件：门店营业状态变更（P2）。
     */
    public UnifiedMessageEnvelope publishShopBusinessChanged(boolean business, Integer shopId) {
        int normalizedShopId = shopId != null && shopId > 0 ? shopId : 0;
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("type", "business_changed");
        payload.put("business", business);
        if (shopId != null) {
            payload.put("shopId", shopId);
        }

        UnifiedMessageEnvelope envelope = UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id("ntf_shop_bus_" + normalizedShopId + "_" + System.nanoTime())
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope(normalizedShopId > 0 ? "SHOP" : "BROADCAST")
                        .shop_id(normalizedShopId)
                        .client_type(UnifiedSessionRegistry.CLIENT_TYPE_ALL)
                        .build())
                .business_type("SYSTEM")
                .event_type("SHOP_BUSINESS_CHANGED")
                .priority("P2")
                .require_ack(false)
                .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                        .ui_type("SILENT_INVALIDATE")
                        .sound("NONE")
                        .duration_ms(0L)
                        .build())
                .payload(payload)
                .build();
        return publish(envelope);
    }

    /**
     * 桥接事件：外卖配送异常告警（P0）。
     */
    public UnifiedMessageEnvelope publishTakeoutDispatchAlert(String alertType, Integer shopId, Integer orderId,
                                                              String orderNo, String message, Long zsqOpenOrderId) {
        int normalizedShopId = shopId != null && shopId > 0 ? shopId : 1;
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("type", "takeout_dispatch_alert");
        payload.put("alertType", alertType);
        payload.put("shopId", normalizedShopId);
        payload.put("orderId", orderId);
        payload.put("orderNo", orderNo);
        payload.put("message", message);
        payload.put("zsqOpenOrderId", zsqOpenOrderId);

        UnifiedMessageEnvelope envelope = UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id("ntf_takeout_alert_" + (orderNo != null ? orderNo : System.nanoTime()) + "_" + (alertType != null ? alertType : "ERR"))
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope("SHOP")
                        .shop_id(normalizedShopId)
                        .client_type(UnifiedSessionRegistry.CLIENT_TYPE_CASHIER)
                        .build())
                .business_type("TAKEOUT")
                .event_type("TAKEOUT_DISPATCH_ALERT")
                .priority("P0")
                .require_ack(true)
                .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                        .ui_type("PERSISTENT_ALERT_BANNER")
                        .sound("VOICE_TIMEOUT_ALERT")
                        .tts_text(StringUtils.hasText(message) ? message : "外卖配送异常，请及时处理")
                        .duration_ms(0L)
                        .repeat_interval_ms(60000L)
                        .action_text("查看配送")
                        .action_route("/cashier/takeout?orderNo=" + (orderNo != null ? orderNo : ""))
                        .build())
                .payload(payload)
                .build();
        return publish(envelope);
    }

    /**
     * 桥接事件：外卖配送状态变更（P2）。
     */
    public UnifiedMessageEnvelope publishTakeoutDispatchChanged(Integer shopId, Integer orderId, String orderNo,
                                                                String dispatchStatus, String zsqDispatchStatus, String zsqPhase) {
        int normalizedShopId = shopId != null && shopId > 0 ? shopId : 1;
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("type", "takeout_dispatch_changed");
        payload.put("shopId", normalizedShopId);
        payload.put("orderId", orderId);
        payload.put("orderNo", orderNo);
        payload.put("dispatchStatus", dispatchStatus);
        payload.put("zsqDispatchStatus", zsqDispatchStatus);
        payload.put("zsqPhase", zsqPhase);

        UnifiedMessageEnvelope envelope = UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id("ntf_takeout_chg_" + (orderNo != null ? orderNo : "") + "_" + System.nanoTime())
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope("SHOP")
                        .shop_id(normalizedShopId)
                        .client_type(UnifiedSessionRegistry.CLIENT_TYPE_ALL)
                        .build())
                .business_type("TAKEOUT")
                .event_type("TAKEOUT_DISPATCH_CHANGED")
                .priority("P2")
                .require_ack(false)
                .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                        .ui_type("SILENT_INVALIDATE")
                        .sound("NONE")
                        .duration_ms(0L)
                        .build())
                .payload(payload)
                .build();
        return publish(envelope);
    }

    /**
     * 桥接事件：出餐完成取餐提醒（P1）。
     */
    public UnifiedMessageEnvelope publishMealPickupReady(Integer shopId, Integer orderId, String orderNo,
                                                         String tableNumber, String dineInOrTakeOut, String pickupCode) {
        int normalizedShopId = shopId != null && shopId > 0 ? shopId : 1;
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("type", "meal_pickup_ready");
        payload.put("shopId", normalizedShopId);
        payload.put("orderId", orderId);
        payload.put("orderNo", orderNo);
        payload.put("tableNumber", tableNumber);
        payload.put("dineInOrTakeOut", dineInOrTakeOut);
        payload.put("pickupCode", pickupCode);
        payload.put("status", "ready_for_pickup");
        payload.put("message", "您的餐品已制作完成，请取餐");

        UnifiedMessageEnvelope envelope = UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id("ntf_pickup_" + (orderNo != null ? orderNo : System.nanoTime()))
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope("SHOP")
                        .shop_id(normalizedShopId)
                        .client_type(UnifiedSessionRegistry.CLIENT_TYPE_ALL)
                        .build())
                .business_type("ORDER")
                .event_type("MEAL_PICKUP_READY")
                .priority("P1")
                .require_ack(true)
                .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                        .ui_type("TOP_BANNER_AND_VOICE")
                        .sound("VOICE_NEW_ORDER")
                        .tts_text("您的餐品已制作完成，请取餐")
                        .duration_ms(8000L)
                        .action_text("查看详情")
                        .action_route("/pages/order-details/details?order_no=" + (orderNo != null ? orderNo : ""))
                        .build())
                .payload(payload)
                .build();
        return publish(envelope);
    }

    /**
     * 业务事件 5：C端顾客专属取餐强提醒（P0，按订单 openid 精准触达顾客小程序，展示取餐号 + 震动提醒）。
     */
    public UnifiedMessageEnvelope publishCustomerOrderPickupReady(Order order, String pickupCode) {
        if (order == null || !StringUtils.hasText(order.getOpenid())) {
            return null;
        }
        String openid = order.getOpenid().trim();
        int normalizedShopId = order.getShop_id() != null && order.getShop_id() > 0 ? order.getShop_id() : 1;
        String orderNo = order.getOrder_no() != null ? order.getOrder_no() : String.valueOf(order.getId());
        String resolvedPickupCode = StringUtils.hasText(pickupCode)
                ? pickupCode.trim()
                : (order.getId() != null ? String.valueOf(order.getId()) : tail4(orderNo));

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("type", "order_ready_for_pickup");
        payload.put("shop_id", normalizedShopId);
        payload.put("order_id", order.getId());
        payload.put("order_no", orderNo);
        payload.put("table_number", order.getTable_number() != null ? order.getTable_number() : "");
        payload.put("dine_in_or_take_out", order.getDineInOrTakeOut() != null ? order.getDineInOrTakeOut() : "堂食");
        payload.put("pickup_code", resolvedPickupCode);
        payload.put("status", "ready_for_pickup");
        payload.put("message", "您的餐品已全部制作完成，请凭取餐号 " + resolvedPickupCode + " 取餐");

        UnifiedMessageEnvelope envelope = UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id("ntf_user_pickup_" + orderNo)
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope("USER")
                        .shop_id(normalizedShopId)
                        .openid(openid)
                        .client_type(UnifiedSessionRegistry.CLIENT_TYPE_MINI_PROGRAM)
                        .build())
                .business_type("ORDER")
                .event_type("ORDER_READY_FOR_PICKUP")
                .priority("P0")
                .require_ack(true)
                .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                        .ui_type("TOP_BANNER_AND_VIBRATE")
                        .sound("VOICE_PICKUP_READY")
                        .tts_text("请 " + resolvedPickupCode + " 号顾客取餐")
                        .duration_ms(10000L)
                        .repeat_interval_ms(0L)
                        .action_text("查看取餐码")
                        .action_route("/packageOther/order-details/details?order_no=" + orderNo)
                        .build())
                .payload(payload)
                .build();
        return publish(envelope);
    }

    /**
     * 业务事件 6：B端收银台退单/退款申请强提醒（P0，模态或常驻告警条 + 语音提示）。
     */
    public UnifiedMessageEnvelope publishRefundRequested(Order order, Double refundAmount, String reason) {
        if (order == null) {
            return null;
        }
        int normalizedShopId = order.getShop_id() != null && order.getShop_id() > 0 ? order.getShop_id() : 1;
        String orderNo = order.getOrder_no() != null ? order.getOrder_no() : String.valueOf(order.getId());

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("shop_id", normalizedShopId);
        payload.put("order_id", order.getId());
        payload.put("order_no", orderNo);
        payload.put("table_number", order.getTable_number() != null ? order.getTable_number() : "");
        payload.put("refund_amount", refundAmount);
        payload.put("reason", reason != null ? reason : "顾客申请退款");

        UnifiedMessageEnvelope envelope = UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id("ntf_refund_req_" + orderNo)
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope("SHOP")
                        .shop_id(normalizedShopId)
                        .client_type(UnifiedSessionRegistry.CLIENT_TYPE_CASHIER)
                        .build())
                .business_type("ORDER")
                .event_type("REFUND_REQUESTED")
                .priority("P0")
                .require_ack(true)
                .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                        .ui_type("PERSISTENT_ALERT_BANNER")
                        .sound("VOICE_REFUND_ALERT")
                        .tts_text("收到新的退款申请，请及时处理")
                        .duration_ms(0L)
                        .repeat_interval_ms(60000L)
                        .action_text("去处理")
                        .action_route("/cashier/orders?orderNo=" + orderNo)
                        .build())
                .payload(payload)
                .build();
        return publish(envelope);
    }

    /**
     * 业务事件 7：营销活动弹窗发布/变更实时推送（P2，纳入统一模态队列调度 + 失效本地 3 分钟缓存）。
     */
    public UnifiedMessageEnvelope publishActivityPopupChanged(String action, ActivityPopup popup) {
        if (popup == null) {
            return null;
        }
        String normalizedAction = StringUtils.hasText(action) ? action.trim().toUpperCase() : "UPDATED";
        Long popupId = popup.getId() != null ? popup.getId() : 0L;

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("action", normalizedAction);
        payload.put("popup_id", popupId);
        payload.put("name", popup.getName() != null ? popup.getName() : "");
        payload.put("popup_image", popup.getPopup_image() != null ? popup.getPopup_image() : "");
        payload.put("image_url", popup.getImage_url() != null ? popup.getImage_url() : "");
        payload.put("target_user", popup.getTarget_user() != null ? popup.getTarget_user() : "all");
        payload.put("type", popup.getType() != null ? popup.getType() : "page_activity");
        payload.put("is_enabled", popup.getIs_enabled() != null ? popup.getIs_enabled() : 1);
        payload.put("max_show_count", popup.getMax_show_count() != null ? popup.getMax_show_count() : 0);
        payload.put("apply_shop_ids", popup.getApply_shop_ids() != null ? popup.getApply_shop_ids() : "");

        UnifiedMessageEnvelope envelope = UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id("ntf_act_popup_" + popupId + "_" + System.currentTimeMillis())
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope("BROADCAST")
                        .shop_id(0)
                        .client_type(UnifiedSessionRegistry.CLIENT_TYPE_MINI_PROGRAM)
                        .build())
                .business_type("MARKETING")
                .event_type("ACTIVITY_POPUP_CHANGED")
                .priority("P2")
                .require_ack(false)
                .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                        .ui_type("MODAL_POPUP_OR_INVALIDATE")
                        .sound("NONE")
                        .duration_ms(0L)
                        .action_text("查看活动")
                        .action_route(StringUtils.hasText(popup.getImage_url()) ? popup.getImage_url() : "/pages/order/order")
                        .build())
                .payload(payload)
                .build();
        return publish(envelope);
    }

    /**
     * 业务事件 8：门店公告发布/变更实时广播（P2，顶部滚动通告栏或弹窗更新）。
     */
    public UnifiedMessageEnvelope publishShopAnnouncementChanged(String action, Announcement announcement) {
        if (announcement == null) {
            return null;
        }
        String normalizedAction = StringUtils.hasText(action) ? action.trim().toUpperCase() : "UPDATED";
        Long annId = announcement.getId() != null ? announcement.getId() : 0L;
        Integer shopId = announcement.getShop_id();
        boolean isGlobal = (shopId == null || shopId <= 0);

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("action", normalizedAction);
        payload.put("announcement_id", annId);
        payload.put("shop_id", isGlobal ? 0 : shopId);
        payload.put("title", announcement.getTitle() != null ? announcement.getTitle() : "");
        payload.put("content", announcement.getContent() != null ? announcement.getContent() : "");
        payload.put("status", announcement.getStatus() != null ? announcement.getStatus() : 1);

        UnifiedMessageEnvelope envelope = UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id("ntf_ann_" + annId + "_" + System.currentTimeMillis())
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope(isGlobal ? "BROADCAST" : "SHOP")
                        .shop_id(isGlobal ? 0 : shopId)
                        .client_type(UnifiedSessionRegistry.CLIENT_TYPE_MINI_PROGRAM)
                        .build())
                .business_type("SHOP")
                .event_type("SHOP_ANNOUNCEMENT_CHANGED")
                .priority("P2")
                .require_ack(false)
                .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                        .ui_type("TOP_NOTICE_BAR")
                        .sound("NONE")
                        .duration_ms(8000L)
                        .build())
                .payload(payload)
                .build();
        return publish(envelope);
    }

    /**
     * 业务事件 9：C端排队叫号到号强提醒（P0，按取号顾客 openid 精准触达，顶部强提醒卡片 + 震动 + 语音）。
     */
    public UnifiedMessageEnvelope publishQueueTicketCalled(QueueTicket ticket, Integer aheadCount, String shopName) {
        if (ticket == null || !StringUtils.hasText(ticket.getOpenid())) {
            return null;
        }
        String openid = ticket.getOpenid().trim();
        int normalizedShopId = ticket.getShop_id() != null && ticket.getShop_id() > 0 ? ticket.getShop_id() : 1;
        String ticketNo = ticket.getTicket_no() != null ? ticket.getTicket_no() : String.valueOf(ticket.getId());
        int ahead = aheadCount != null && aheadCount >= 0 ? aheadCount : 0;

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("ticket_id", ticket.getId());
        payload.put("ticket_no", ticketNo);
        payload.put("shop_id", normalizedShopId);
        payload.put("shop_name", StringUtils.hasText(shopName) ? shopName : "门店");
        payload.put("party_size", ticket.getParty_size() != null ? ticket.getParty_size() : 2);
        payload.put("dine_type", ticket.getDine_type() != null ? ticket.getDine_type() : "堂食");
        payload.put("status", ticket.getStatus() != null ? ticket.getStatus() : "calling");
        payload.put("ahead_count", ahead);
        payload.put("message", ahead == 0
                ? ("请 " + ticketNo + " 号顾客立即前往迎宾台就餐")
                : ("您的排号 " + ticketNo + " 即将到号，前方仅剩 " + ahead + " 桌"));

        UnifiedMessageEnvelope envelope = UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id("ntf_queue_call_" + ticketNo + "_" + (ticket.getId() != null ? ticket.getId() : System.currentTimeMillis()))
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope("USER")
                        .shop_id(normalizedShopId)
                        .openid(openid)
                        .client_type(UnifiedSessionRegistry.CLIENT_TYPE_MINI_PROGRAM)
                        .build())
                .business_type("QUEUE")
                .event_type("QUEUE_TICKET_CALLED")
                .priority("P0")
                .require_ack(true)
                .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                        .ui_type("TOP_BANNER_AND_VIBRATE")
                        .sound("VOICE_QUEUE_CALLED")
                        .tts_text("请 " + ticketNo + " 号顾客前往就餐")
                        .duration_ms(12000L)
                        .action_text("查看排号")
                        .action_route("/packageOther/queue/index?ticketNo=" + ticketNo)
                        .build())
                .payload(payload)
                .build();
        return publish(envelope);
    }

    /**
     * 业务事件 10：C端顾客退款审批/到账结果通知（P1，按订单 openid 精准触达，顶部横幅提醒）。
     */
    public UnifiedMessageEnvelope publishCustomerOrderRefundResult(Order order, String refundStatus, Double refundAmount, String remark) {
        if (order == null || !StringUtils.hasText(order.getOpenid())) {
            return null;
        }
        String openid = order.getOpenid().trim();
        int normalizedShopId = order.getShop_id() != null && order.getShop_id() > 0 ? order.getShop_id() : 1;
        String orderNo = order.getOrder_no() != null ? order.getOrder_no() : String.valueOf(order.getId());
        String status = StringUtils.hasText(refundStatus) ? refundStatus.trim().toUpperCase() : "APPROVED";

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("shop_id", normalizedShopId);
        payload.put("order_id", order.getId());
        payload.put("order_no", orderNo);
        payload.put("refund_status", status);
        payload.put("refund_amount", refundAmount != null ? refundAmount : 0.0);
        payload.put("remark", StringUtils.hasText(remark) ? remark : "退款状态已更新");

        UnifiedMessageEnvelope envelope = UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id("ntf_refund_res_" + orderNo + "_" + status)
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope("USER")
                        .shop_id(normalizedShopId)
                        .openid(openid)
                        .client_type(UnifiedSessionRegistry.CLIENT_TYPE_MINI_PROGRAM)
                        .build())
                .business_type("ORDER")
                .event_type("ORDER_REFUND_PROCESSED")
                .priority("P1")
                .require_ack(true)
                .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                        .ui_type("TOP_BANNER")
                        .sound("CHIME_COUPON")
                        .duration_ms(6000L)
                        .action_text("查看订单")
                        .action_route("/packageOther/order-details/details?order_no=" + orderNo)
                        .build())
                .payload(payload)
                .build();
        return publish(envelope);
    }

    /**
     * 断线重连后按游标增量拉取未读、未过期消息。
     */
    public Map<String, Object> syncNotifications(Integer shopId, String clientType, String openid,
                                                 Long lastSeqId, Integer limit) {
        long cursor = lastSeqId != null && lastSeqId > 0 ? lastSeqId : 0L;
        int pageSize = (limit == null || limit <= 0) ? 50 : Math.min(limit, 200);
        String normClient = UnifiedSessionRegistry.normalizeClientType(clientType);
        Date now = new Date();

        List<UnifiedMessageEnvelope> items = new ArrayList<>();
        boolean hasMore = false;

        if (notificationMapper != null) {
            QueryWrapper<RealtimeNotification> qw = new QueryWrapper<RealtimeNotification>()
                    .gt("seq_id", cursor)
                    .eq("read_status", 0)
                    .gt("expire_at", now);

            if (UnifiedSessionRegistry.CLIENT_TYPE_CASHIER.equals(normClient)) {
                int targetShop = (shopId != null && shopId > 0) ? shopId : 1;
                qw.and(w -> w.eq("shop_id", targetShop).or().eq("shop_id", 0))
                  .in("client_type", UnifiedSessionRegistry.CLIENT_TYPE_CASHIER, UnifiedSessionRegistry.CLIENT_TYPE_ALL);
            } else if (StringUtils.hasText(openid)) {
                String trimmedOpenid = openid.trim();
                if (shopId != null && shopId > 0) {
                    int targetShop = shopId;
                    qw.and(w -> w.eq("user_openid", trimmedOpenid)
                            .or(sw -> sw.eq("target_scope", "SHOP").eq("shop_id", targetShop)
                                    .in("client_type", UnifiedSessionRegistry.CLIENT_TYPE_MINI_PROGRAM, UnifiedSessionRegistry.CLIENT_TYPE_ALL)));
                } else {
                    qw.eq("user_openid", trimmedOpenid);
                }
            } else if (shopId != null && shopId > 0) {
                qw.eq("shop_id", shopId);
            }

            qw.orderByAsc("seq_id").last("LIMIT " + (pageSize + 1));
            List<RealtimeNotification> records = notificationMapper.selectList(qw);
            if (records != null) {
                if (records.size() > pageSize) {
                    hasMore = true;
                    records = records.subList(0, pageSize);
                }
                for (RealtimeNotification record : records) {
                    items.add(fromEntity(record));
                }
            }
        }

        long serverHead = currentServerHeadSeqId(shopId);
        if (!items.isEmpty()) {
            long lastItemSeq = items.get(items.size() - 1).getSeq_id();
            if (lastItemSeq > serverHead) {
                serverHead = lastItemSeq;
            }
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("server_head_seq_id", serverHead);
        result.put("serverHeadSeqId", serverHead);
        result.put("last_seq_id", cursor);
        result.put("has_more", hasMore);
        result.put("hasMore", hasMore);
        result.put("items", items);
        return result;
    }

    /**
     * 批量确认消息已读，并在收银端多机场景下向同门店所有终端广播 ALERT_DISMISSED 以消除告警。
     */
    public Map<String, Object> acknowledgeNotifications(Integer shopId, String openid,
                                                        List<String> messageIds, String ackedBy) {
        if (messageIds == null || messageIds.isEmpty()) {
            Map<String, Object> empty = new LinkedHashMap<>();
            empty.put("acked_count", 0);
            empty.put("dismissed_message_ids", Collections.emptyList());
            return empty;
        }
        List<String> cleanIds = new ArrayList<>();
        for (String id : messageIds) {
            if (StringUtils.hasText(id)) {
                cleanIds.add(id.trim());
            }
        }
        int updated = 0;
        if (!cleanIds.isEmpty() && notificationMapper != null) {
            UpdateWrapper<RealtimeNotification> uw = new UpdateWrapper<RealtimeNotification>()
                    .set("read_status", 1)
                    .set("acked_by", StringUtils.hasText(ackedBy) ? ackedBy.trim() : "CLIENT_ACK")
                    .set("acked_at", new Date())
                    .in("message_id", cleanIds)
                    .eq("read_status", 0);
            if (shopId != null && shopId > 0 && !StringUtils.hasText(openid)) {
                uw.and(w -> w.eq("shop_id", shopId).or().eq("shop_id", 0));
            } else if (StringUtils.hasText(openid)) {
                uw.eq("user_openid", openid.trim());
            }
            try {
                updated = notificationMapper.update(null, uw);
            } catch (Exception e) {
                log.warn("[notify] acknowledge update failed: {}", e.getMessage());
            }
        }

        // 若属于门店收银端确认，向同店所有收银终端广播 ALERT_DISMISSED 实现 1s 内跨终端同步消除告警
        if (shopId != null && shopId > 0 && !cleanIds.isEmpty()) {
            Map<String, Object> dismissPayload = new LinkedHashMap<>();
            dismissPayload.put("shop_id", shopId);
            dismissPayload.put("dismissed_message_ids", cleanIds);
            dismissPayload.put("acked_by", StringUtils.hasText(ackedBy) ? ackedBy.trim() : "CASHIER");

            UnifiedMessageEnvelope dismissEnvelope = UnifiedMessageEnvelope.builder()
                    .frame_type("EVENT")
                    .message_id("ntf_dismiss_" + shopId + "_" + System.nanoTime())
                    .seq_id(0L)
                    .timestamp(System.currentTimeMillis())
                    .expire_at(System.currentTimeMillis() + DEFAULT_TTL_P2_MS)
                    .target(UnifiedMessageEnvelope.Target.builder()
                            .scope("SHOP")
                            .shop_id(shopId)
                            .client_type(UnifiedSessionRegistry.CLIENT_TYPE_CASHIER)
                            .build())
                    .business_type("SYSTEM")
                    .event_type("ALERT_DISMISSED")
                    .priority("P2")
                    .require_ack(false)
                    .display_strategy(UnifiedMessageEnvelope.DisplayStrategy.builder()
                            .ui_type("SILENT_INVALIDATE")
                            .sound("NONE")
                            .duration_ms(0L)
                            .build())
                    .payload(dismissPayload)
                    .build();
            sessionRegistry.sendToShop(shopId, UnifiedSessionRegistry.CLIENT_TYPE_CASHIER, dismissEnvelope);
        }

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("acked_count", updated);
        res.put("dismissed_message_ids", cleanIds);
        return res;
    }

    /**
     * 清理已过期通知及超过保留天数的已确认历史消息。
     */
    public int cleanupExpiredNotifications(int retentionDaysForRead) {
        if (notificationMapper == null) {
            return 0;
        }
        int days = retentionDaysForRead > 0 ? retentionDaysForRead : 7;
        Date now = new Date();
        long archiveThresholdMs = System.currentTimeMillis() - (days * 24L * 3600L * 1000L);
        Date readArchiveThreshold = new Date(archiveThresholdMs);

        try {
            QueryWrapper<RealtimeNotification> qw = new QueryWrapper<RealtimeNotification>()
                    .le("expire_at", now)
                    .or(w -> w.eq("read_status", 1).le("acked_at", readArchiveThreshold));
            return notificationMapper.delete(qw);
        } catch (Exception e) {
            log.warn("[notify-cleanup] cleanup expired/archived notifications failed: {}", e.getMessage());
            return 0;
        }
    }

    /**
     * 查询门店实时消息通道连接与待处理告警统计。
     */
    public Map<String, Object> getChannelStats(Integer shopId) {
        int targetShop = shopId != null && shopId > 0 ? shopId : 1;
        Map<String, Object> sessionStats = sessionRegistry != null
                ? sessionRegistry.getShopSessionStats(targetShop)
                : Collections.emptyMap();

        long pendingP0Count = 0L;
        long pendingP1Count = 0L;
        if (notificationMapper != null) {
            try {
                Date now = new Date();
                Integer p0 = notificationMapper.selectCount(new QueryWrapper<RealtimeNotification>()
                        .eq("shop_id", targetShop)
                        .eq("priority", "P0")
                        .eq("read_status", 0)
                        .gt("expire_at", now));
                if (p0 != null) {
                    pendingP0Count = p0;
                }
                Integer p1 = notificationMapper.selectCount(new QueryWrapper<RealtimeNotification>()
                        .eq("shop_id", targetShop)
                        .eq("priority", "P1")
                        .eq("read_status", 0)
                        .gt("expire_at", now));
                if (p1 != null) {
                    pendingP1Count = p1;
                }
            } catch (Exception ignored) {
            }
        }

        Map<String, Object> result = new LinkedHashMap<>(sessionStats);
        result.put("pending_p0_count", pendingP0Count);
        result.put("pending_p1_count", pendingP1Count);
        result.put("server_head_seq_id", currentServerHeadSeqId(targetShop));
        return result;
    }

    /**
     * 发送联调测试实时通知（支持 ORDER_PREP_TIMEOUT / NEW_ORDER_PAID / REFUND_REQUESTED）。
     */
    public UnifiedMessageEnvelope publishTestNotification(Integer shopId, String eventType, String operatorName) {
        int targetShop = shopId != null && shopId > 0 ? shopId : 1;
        String cleanType = StringUtils.hasText(eventType) ? eventType.trim().toUpperCase() : "ORDER_PREP_TIMEOUT";
        String operator = StringUtils.hasText(operatorName) ? operatorName.trim() : "ADMIN";

        if ("NEW_ORDER_PAID".equals(cleanType)) {
            Order testOrder = new Order();
            testOrder.setId(99999);
            testOrder.setOrder_no("TEST_PAID_" + (System.currentTimeMillis() % 10000));
            testOrder.setShop_id(targetShop);
            testOrder.setSett_amount(88.0);
            testOrder.setTable_number("T08");
            testOrder.setNumber_of_diners("3");
            return publishNewOrderPaid(testOrder, 88.0);
        } else if ("REFUND_REQUESTED".equals(cleanType)) {
            Order testOrder = new Order();
            testOrder.setId(99998);
            testOrder.setOrder_no("TEST_REF_" + (System.currentTimeMillis() % 10000));
            testOrder.setShop_id(targetShop);
            testOrder.setSett_amount(66.0);
            testOrder.setTable_number("T02");
            return publishRefundRequested(testOrder, 66.0, "顾客联调测试申请整单退款");
        } else {
            // Default: ORDER_PREP_TIMEOUT
            Order testOrder = new Order();
            testOrder.setId(99997);
            testOrder.setOrder_no("TEST_OVR_" + (System.currentTimeMillis() % 10000));
            testOrder.setShop_id(targetShop);
            testOrder.setSett_amount(120.0);
            testOrder.setTable_number("A01");
            return publishOrderPrepTimeout(testOrder, 15, 18, 30);
        }
    }

    private void dispatchEnvelope(UnifiedMessageEnvelope envelope, Runnable onZeroRecipient) {
        UnifiedMessageEnvelope.Target target = envelope.getTarget();
        if (target == null) {
            sessionRegistry.broadcastAll(envelope);
            return;
        }
        String scope = target.getScope() != null ? target.getScope().toUpperCase() : "SHOP";
        int sent;
        if ("USER".equals(scope)) {
            sent = sessionRegistry.sendToUser(target.getOpenid(), target.getUser_id(), envelope);
        } else if ("BROADCAST".equals(scope)) {
            sent = sessionRegistry.broadcastAll(envelope);
        } else {
            sent = sessionRegistry.sendToShop(target.getShop_id(), target.getClient_type(), envelope);
        }
        if (sent <= 0 && onZeroRecipient != null) {
            onZeroRecipient.run();
        }
    }

    private void runAfterCommitOrNow(Runnable task) {
        if (TransactionSynchronizationManager.isActualTransactionActive()
                && TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    try {
                        task.run();
                    } catch (Exception e) {
                        log.warn("[notify] afterCommit dispatch failed: {}", e.getMessage());
                    }
                }
            });
        } else {
            try {
                task.run();
            } catch (Exception e) {
                log.warn("[notify] immediate dispatch failed: {}", e.getMessage());
            }
        }
    }

    private RealtimeNotification toEntity(UnifiedMessageEnvelope envelope, long nowMs) {
        RealtimeNotification entity = new RealtimeNotification();
        entity.setMessage_id(envelope.getMessage_id());
        UnifiedMessageEnvelope.Target target = envelope.getTarget();
        entity.setTarget_scope(target != null && target.getScope() != null ? target.getScope() : "SHOP");
        entity.setShop_id(target != null && target.getShop_id() != null ? target.getShop_id() : 0);
        entity.setUser_id(target != null ? target.getUser_id() : null);
        entity.setUser_openid(target != null ? target.getOpenid() : null);
        entity.setClient_type(target != null && target.getClient_type() != null
                ? target.getClient_type()
                : UnifiedSessionRegistry.CLIENT_TYPE_CASHIER);
        entity.setBusiness_type(envelope.getBusiness_type() != null ? envelope.getBusiness_type() : "SYSTEM");
        entity.setEvent_type(envelope.getEvent_type() != null ? envelope.getEvent_type() : "UNKNOWN");
        entity.setPriority(envelope.getPriority() != null ? envelope.getPriority() : "P2");
        entity.setRequire_ack(Boolean.TRUE.equals(envelope.getRequire_ack()) ? 1 : 0);
        try {
            entity.setDisplay_strategy_json(envelope.getDisplay_strategy() != null
                    ? objectMapper.writeValueAsString(envelope.getDisplay_strategy())
                    : "{}");
            entity.setPayload_json(envelope.getPayload() != null
                    ? objectMapper.writeValueAsString(envelope.getPayload())
                    : "{}");
        } catch (Exception e) {
            entity.setDisplay_strategy_json("{}");
            entity.setPayload_json("{}");
        }
        entity.setRead_status(0);
        entity.setExpire_at(new Date(envelope.getExpire_at() != null ? envelope.getExpire_at() : (nowMs + DEFAULT_TTL_P1_MS)));
        entity.setCreated_at(new Date(nowMs));
        entity.setUpdated_at(new Date(nowMs));
        return entity;
    }

    private UnifiedMessageEnvelope fromEntity(RealtimeNotification entity) {
        UnifiedMessageEnvelope.DisplayStrategy displayStrategy = null;
        Map<String, Object> payload = Collections.emptyMap();
        try {
            if (StringUtils.hasText(entity.getDisplay_strategy_json())) {
                displayStrategy = objectMapper.readValue(
                        entity.getDisplay_strategy_json(), UnifiedMessageEnvelope.DisplayStrategy.class);
            }
            if (StringUtils.hasText(entity.getPayload_json())) {
                payload = objectMapper.readValue(
                        entity.getPayload_json(), new TypeReference<Map<String, Object>>() {});
            }
        } catch (Exception ignored) {
        }
        return UnifiedMessageEnvelope.builder()
                .frame_type("EVENT")
                .message_id(entity.getMessage_id())
                .seq_id(entity.getSeq_id())
                .timestamp(entity.getCreated_at() != null ? entity.getCreated_at().getTime() : System.currentTimeMillis())
                .expire_at(entity.getExpire_at() != null ? entity.getExpire_at().getTime() : null)
                .target(UnifiedMessageEnvelope.Target.builder()
                        .scope(entity.getTarget_scope())
                        .shop_id(entity.getShop_id())
                        .user_id(entity.getUser_id())
                        .openid(entity.getUser_openid())
                        .client_type(entity.getClient_type())
                        .build())
                .business_type(entity.getBusiness_type())
                .event_type(entity.getEvent_type())
                .priority(entity.getPriority())
                .require_ack(entity.getRequire_ack() != null && entity.getRequire_ack() == 1)
                .display_strategy(displayStrategy)
                .payload(payload)
                .build();
    }

    private static String tail4(String orderNo) {
        if (!StringUtils.hasText(orderNo)) {
            return "";
        }
        String s = orderNo.trim();
        return s.length() <= 4 ? s : s.substring(s.length() - 4);
    }

    private static String formatCouponDiscountDesc(String couponType, Double discountValue, Double minAmount) {
        if (discountValue == null) {
            return "立享专属优惠";
        }
        String type = couponType != null ? couponType.trim().toLowerCase() : "";
        if ("discount".equals(type)) {
            return discountValue + "折优惠券";
        }
        if (minAmount != null && minAmount > 0) {
            return String.format("满%.0f减%.0f元", minAmount, discountValue);
        }
        return String.format("立减%.0f元", discountValue);
    }
}

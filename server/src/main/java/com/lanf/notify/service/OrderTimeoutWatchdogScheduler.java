package com.lanf.notify.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.ShopNotificationConfig;
import com.lanf.mapper.OrderMapper;
import com.lanf.realtime.UnifiedMessageEnvelope;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 订单出餐超时动态阈值巡检调度器。
 * 按门店在后台设置的动态阈值（t_shop_notification_config.prep_timeout_minutes，默认15分钟）
 * 扫描已支付且未完成（off_time IS NULL）的订单，触发 P0 级 ORDER_PREP_TIMEOUT 实时告警。
 */
@Component
public class OrderTimeoutWatchdogScheduler {

    private static final Logger log = LoggerFactory.getLogger(OrderTimeoutWatchdogScheduler.class);
    private static final long SCAN_LOOKBACK_WINDOW_MS = 24 * 60 * 60 * 1000L; // 仅扫描最近24小时内支付的未结单

    private final OrderMapper orderMapper;
    private final ShopNotificationConfigService configService;
    private final UnifiedNotificationService notificationService;

    /** 进程内一级幂等去重缓存，配合数据库 uk_message_id 双重防重 */
    private final Set<String> triggeredTimeoutKeys = ConcurrentHashMap.newKeySet();

    @Autowired
    public OrderTimeoutWatchdogScheduler(@Autowired(required = false) OrderMapper orderMapper,
                                         ShopNotificationConfigService configService,
                                         UnifiedNotificationService notificationService) {
        this.orderMapper = orderMapper;
        this.configService = configService;
        this.notificationService = notificationService;
    }

    @Scheduled(
            fixedDelayString = "${notify.prep-timeout.scan-interval-ms:30000}",
            initialDelayString = "${notify.prep-timeout.initial-delay-ms:30000}"
    )
    public void scheduledScan() {
        try {
            scanAndNotifyTimedOutOrders(System.currentTimeMillis());
        } catch (Exception e) {
            log.warn("[timeout-watchdog] scheduled scan error: {}", e.getMessage());
        }
    }

    /**
     * 执行一次超时订单扫描并返回本次新触发的告警信封列表（便于单元测试精确断言）。
     */
    public List<UnifiedMessageEnvelope> scanAndNotifyTimedOutOrders(long nowEpochMs) {
        if (orderMapper == null) {
            return new ArrayList<>();
        }
        Date lookbackStart = new Date(nowEpochMs - SCAN_LOOKBACK_WINDOW_MS);
        QueryWrapper<Order> qw = new QueryWrapper<Order>()
                .eq("transac_status", "success")
                .isNull("off_time")
                .isNotNull("pay_time")
                .ge("pay_time", lookbackStart)
                .and(w -> w.isNull("order_receiving")
                        .or().ne("order_receiving", "completed")
                        .ne("order_receiving", "cancelled"))
                .orderByAsc("pay_time")
                .last("LIMIT 200");

        List<Order> candidates = orderMapper.selectList(qw);
        if (candidates == null || candidates.isEmpty()) {
            return new ArrayList<>();
        }

        List<UnifiedMessageEnvelope> published = new ArrayList<>();
        for (Order order : candidates) {
            if (order == null || !StringUtils.hasText(order.getOrder_no()) || order.getPay_time() == null) {
                continue;
            }
            // 已全额退款的订单不触发出餐超时告警
            if (order.getRefund_amount() != null && order.getSett_amount() != null
                    && order.getSett_amount() > 0 && order.getRefund_amount() >= order.getSett_amount()) {
                continue;
            }
            int shopId = (order.getShop_id() != null && order.getShop_id() > 0) ? order.getShop_id() : 1;
            ShopNotificationConfig shopConfig = configService.getOrDefaultConfig(shopId);
            if (shopConfig.getPrep_timeout_enabled() == null || shopConfig.getPrep_timeout_enabled() == 0) {
                continue;
            }

            int thresholdMinutes = shopConfig.getPrep_timeout_minutes() != null
                    ? shopConfig.getPrep_timeout_minutes()
                    : ShopNotificationConfigService.DEFAULT_PREP_TIMEOUT_MINUTES;
            int repeatSeconds = shopConfig.getTimeout_repeat_interval_seconds() != null
                    ? shopConfig.getTimeout_repeat_interval_seconds()
                    : ShopNotificationConfigService.DEFAULT_REPEAT_INTERVAL_SECONDS;

            long elapsedMs = nowEpochMs - order.getPay_time().getTime();
            long thresholdMs = thresholdMinutes * 60_000L;
            if (elapsedMs < thresholdMs) {
                continue;
            }

            String orderNo = order.getOrder_no().trim();
            String messageId = "ntf_timeout_" + orderNo + "_stage1";
            if (triggeredTimeoutKeys.contains(messageId) || notificationService.existsByMessageId(messageId)) {
                triggeredTimeoutKeys.add(messageId);
                continue;
            }

            int elapsedMinutes = (int) Math.max(thresholdMinutes, elapsedMs / 60_000L);
            UnifiedMessageEnvelope env = notificationService.publishOrderPrepTimeout(
                    order, thresholdMinutes, elapsedMinutes, repeatSeconds);
            if (env != null) {
                triggeredTimeoutKeys.add(messageId);
                published.add(env);
            }
        }
        return published;
    }

    public void clearTriggeredCacheForTest() {
        triggeredTimeoutKeys.clear();
    }
}

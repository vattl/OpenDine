package com.lanf.kds.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsScreenTag;
import com.lanf.realtime.KdsWebSocketHub;
import com.lanf.kds.event.KdsCrossInstanceEventBus;
import com.lanf.kds.event.KdsCrossInstanceEventMessage;
import javax.annotation.PostConstruct;
import java.util.concurrent.ConcurrentHashMap;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
public class KdsPushService {

    private static final Logger log = LoggerFactory.getLogger(KdsPushService.class);

    @Autowired
    private KdsWebSocketHub hub;
    @Autowired
    private ObjectMapper objectMapper;
    @Autowired(required = false)
    private KdsCrossInstanceEventBus eventBus;

    private final Map<String, Long> processedEvents = new ConcurrentHashMap<>();
    private static final int MAX_PROCESSED_EVENTS = 4096;

    @PostConstruct
    public void init() {
        if (eventBus != null) {
            eventBus.registerListener(this::handleRemoteEvent);
        }
    }

    public void handleRemoteEvent(KdsCrossInstanceEventMessage msg) {
        if (msg == null) return;
        String dedupKey = buildDedupKey(msg.getShopId(), msg.getEventSeq(), msg.getEventId());
        if (dedupKey != null && processedEvents.putIfAbsent(dedupKey, System.currentTimeMillis()) != null) {
            return;
        }
        pruneDedupCacheIfNeeded();
        try {
            for (String tag : KdsScreenTag.allBroadcastTags()) {
                hub.broadcastV2(msg.getShopId(), tag, msg.getEnvelopeJson());
            }
            log.debug("[kds/bus] Dispatched remote event seq={} shop={} from instance={}",
                    msg.getEventSeq(), msg.getShopId(), msg.getOriginInstanceId());
        } catch (Exception e) {
            log.warn("[kds/bus] Failed to dispatch remote event to local hub: {}", e.getMessage());
        }
    }

    public void newOrder(int shopId, String screenTag, Map<String, Object> payload) {
        send("new_order", shopId, screenTag, payload);
        fanOutToBossOverview(shopId, screenTag, "new_order", payload);
        fanOutToWorkflowBoard(shopId, screenTag, "new_order", payload);
    }

    public void updateOrder(int shopId, String screenTag, Map<String, Object> payload) {
        send("update_order", shopId, screenTag, payload);
        fanOutDoneToOtherScreens(shopId, screenTag, payload);
        fanOutToBossOverview(shopId, screenTag, "update_order", payload);
        fanOutToWorkflowBoard(shopId, screenTag, "update_order", payload);
    }

    /**
     * 烤制岗划为完成(2)时，除本屏外同步推给出餐屏、收银总览（及已连接的其它订阅桶）。
     */
    private void fanOutDoneToOtherScreens(int shopId, String sourceScreen, Map<String, Object> payload) {
        if (payload == null || sourceScreen == null) {
            return;
        }
        Object st = payload.get("item_status");
        int status = st instanceof Number ? ((Number) st).intValue() : -1;
        if (status != KdsItemStatus.DONE) {
            return;
        }
        if (!KdsScreenTag.PRODUCTION_GRILL_TAGS.contains(sourceScreen)) {
            return;
        }
        Map<String, Object> fan = new LinkedHashMap<>(payload);
        fan.put("source_screen_tag", sourceScreen);
        List<String> targets = new ArrayList<>();
        if (!KdsScreenTag.EXPEDITION.equals(sourceScreen)) {
            targets.add(KdsScreenTag.EXPEDITION);
        }
        if (!KdsScreenTag.BOSS_OVERVIEW.equals(sourceScreen)) {
            targets.add(KdsScreenTag.BOSS_OVERVIEW);
        }
        for (String tag : targets) {
            int n = send("update_order", shopId, tag, fan);
            if (n == 0) {
                log.debug("[kds] ws update_order item_status=2 shop={} target={} (no subscriber)",
                        shopId, tag);
            }
        }
    }

    public void cancelItem(int shopId, String screenTag, Map<String, Object> payload) {
        send("cancel_item", shopId, screenTag, payload);
        fanOutToBossOverview(shopId, screenTag, "cancel_item", payload);
        fanOutToWorkflowBoard(shopId, screenTag, "cancel_item", payload);
    }

    public void cancelOrder(int shopId, Map<String, Object> payload) {
        for (String tag : new String[]{
                KdsScreenTag.MEAT_GRILL, KdsScreenTag.VEG_GRILL, KdsScreenTag.SEAFOOD_SPECIAL,
                KdsScreenTag.SKEWER_AGGREGATE, KdsScreenTag.EXPEDITION, KdsScreenTag.BOSS_OVERVIEW,
                KdsScreenTag.WORKFLOW_BOARD
        }) {
            send("cancel_order", shopId, tag, payload);
        }
    }

    /** 烤制岗/抓串/出餐工单变更时同步推送给收银总览屏订阅端。 */
    private void fanOutToBossOverview(int shopId, String screenTag, String type, Map<String, Object> payload) {
        if (screenTag == null || KdsScreenTag.BOSS_OVERVIEW.equals(screenTag)) {
            return;
        }
        boolean production = KdsScreenTag.PRODUCTION_GRILL_TAGS.contains(screenTag);
        boolean skewer = KdsScreenTag.SKEWER_AGGREGATE.equals(screenTag);
        boolean expedition = KdsScreenTag.EXPEDITION.equals(screenTag);
        if (!production && !skewer && !expedition) {
            return;
        }
        send(type, shopId, KdsScreenTag.BOSS_OVERVIEW, payload);
    }

    /** 统一工作流看板订阅 workflow_board，需要收到抓串/烤制/出餐所有状态变化后刷新队列。 */
    private void fanOutToWorkflowBoard(int shopId, String screenTag, String type, Map<String, Object> payload) {
        if (screenTag == null || KdsScreenTag.WORKFLOW_BOARD.equals(screenTag)) {
            return;
        }
        if ("new_order".equals(type)) {
            send(type, shopId, KdsScreenTag.WORKFLOW_BOARD, payload);
            return;
        }
        boolean production = KdsScreenTag.PRODUCTION_GRILL_TAGS.contains(screenTag);
        boolean skewer = KdsScreenTag.SKEWER_AGGREGATE.equals(screenTag);
        boolean expedition = KdsScreenTag.EXPEDITION.equals(screenTag);
        boolean overview = KdsScreenTag.BOSS_OVERVIEW.equals(screenTag);
        if (!production && !skewer && !expedition && !overview) {
            return;
        }
        send(type, shopId, KdsScreenTag.WORKFLOW_BOARD, payload);
    }

    public void orderStatusChanged(int shopId, String screenTag, int kdsOrderStatus, Map<String, Object> payload) {
        Map<String, Object> body = payload != null ? new LinkedHashMap<>(payload) : new LinkedHashMap<>();
        body.put("kds_order_status", kdsOrderStatus);
        if (screenTag != null) {
            send("order_status_changed", shopId, screenTag, body);
            return;
        }
        // screenTag=null：整单状态对全岗位可见，扇出到所有订阅桶
        for (String tag : KdsScreenTag.allBroadcastTags()) {
            send("order_status_changed", shopId, tag, body);
        }
    }

    /** 门店规则配置变更，广播 {@code config_changed} 至各屏订阅桶，厨显端据此刷新本机设置。 */
    public void configChanged(int shopId, Map<String, Object> payload) {
        for (String tag : KdsScreenTag.allBroadcastTags()) {
            send("config_changed", shopId, tag, payload);
        }
    }

    /** 催 / 超 / 加 标记变更，广播至各屏订阅桶。 */
    public void dishFlagsChanged(int shopId, Map<String, Object> payload) {
        for (String tag : KdsScreenTag.allBroadcastTags()) {
            send("dish_flags_changed", shopId, tag, payload);
        }
    }

    /**
     * V2 规范广播：向门店所有岗位/工作流屏幕推送对齐 V2 Envelope 格式的事件。
     * 由 KdsWorkflowV2Service.publishEnvelope 统一治理事务提交边界（在 afterCommit 中触发），
     * 此处直接执行广播，避免在 afterCommit 期间重复注册事务同步导致推送被静默丢弃。
     */
    public void broadcastV2Envelope(int shopId, Map<String, Object> envelope) {
        if (envelope == null) return;
        doBroadcastV2Envelope(shopId, envelope);
    }

    private void doBroadcastV2Envelope(int shopId, Map<String, Object> envelope) {
        try {
            String json = objectMapper.writeValueAsString(envelope);
            String dedupKey = buildDedupKey(shopId, extractEventSeq(envelope), (String) envelope.get("event_id"));
            if (dedupKey != null) {
                processedEvents.put(dedupKey, System.currentTimeMillis());
                pruneDedupCacheIfNeeded();
            }
            for (String tag : KdsScreenTag.allBroadcastTags()) {
                hub.broadcastV2(shopId, tag, json);
            }
            if (eventBus != null) {
                eventBus.publish(shopId, envelope);
            }
        } catch (Exception e) {
            log.warn("[kds] broadcastV2Envelope failed shop={}: {}", shopId, e.getMessage());
        }
    }

    private String buildDedupKey(int shopId, Long eventSeq, String eventId) {
        if (eventSeq != null && eventSeq > 0) {
            return shopId + ":seq:" + eventSeq;
        }
        if (eventId != null && !eventId.trim().isEmpty()) {
            return shopId + ":id:" + eventId.trim();
        }
        return null;
    }

    private Long extractEventSeq(Map<String, Object> envelope) {
        Object val = envelope.get("event_seq");
        if (val instanceof Number) {
            return ((Number) val).longValue();
        }
        return null;
    }

    private void pruneDedupCacheIfNeeded() {
        if (processedEvents.size() > MAX_PROCESSED_EVENTS) {
            long cutoff = System.currentTimeMillis() - 300000L;
            processedEvents.entrySet().removeIf(entry -> entry.getValue() < cutoff);
            if (processedEvents.size() > MAX_PROCESSED_EVENTS) {
                int toRemove = processedEvents.size() / 2;
                for (String k : processedEvents.keySet()) {
                    if (toRemove-- <= 0) break;
                    processedEvents.remove(k);
                }
            }
        }
    }

    /** @return 实际推送到的 WebSocket 连接数（事务内注册 afterCommit 时返回 0） */
    private int send(String type, int shopId, String screenTag, Map<String, Object> payload) {
        if (TransactionSynchronizationManager.isActualTransactionActive()
                && TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    doSend(type, shopId, screenTag, payload);
                }
            });
            return 0;
        }
        return doSend(type, shopId, screenTag, payload);
    }

    private int doSend(String type, int shopId, String screenTag, Map<String, Object> payload) {
        try {
            Map<String, Object> envelope = new LinkedHashMap<>();
            envelope.put("type", type);
            envelope.put("shop_id", shopId);
            envelope.put("screen_tag", screenTag);
            envelope.put("payload", payload != null ? payload : Collections.emptyMap());
            String json = objectMapper.writeValueAsString(envelope);
            int sent = hub.broadcastV1(shopId, screenTag, json);
            if (KdsScreenTag.EXPEDITION.equals(screenTag) || KdsScreenTag.SKEWER_AGGREGATE.equals(screenTag)) {
                logPush(type, shopId, screenTag, sent);
                return sent;
            }
            if ("update_order".equals(type) || "new_order".equals(type)) {
                if (!KdsScreenTag.SKEWER_AGGREGATE.equals(screenTag)) {
                    sent += hub.broadcastV1(shopId, KdsScreenTag.SKEWER_AGGREGATE, json);
                }
            }
            logPush(type, shopId, screenTag, sent);
            return sent;
        } catch (Exception e) {
            log.warn("[kds] ws push failed type={}: {}", type, e.getMessage());
            return 0;
        }
    }

    private void logPush(String type, int shopId, String screenTag, int sent) {
        if (!"new_order".equals(type) && !"update_order".equals(type)) {
            return;
        }
        if (sent > 0) {
            log.info("[kds] ws {} shop={} screen={} subscribers={}", type, shopId, screenTag, sent);
        } else if (KdsScreenTag.WORKFLOW_BOARD.equals(screenTag) || KdsScreenTag.SKEWER_AGGREGATE.equals(screenTag)) {
            log.info("[kds] ws {} shop={} screen={} (no subscriber)", type, shopId, screenTag);
        }
    }
}

package com.lanf.kds.event;

import org.springframework.context.ApplicationEvent;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * KDS 单品/工单状态或工作流队列已变化。
 * 由划菜域（advance / status / revoke / refund 等）发布，
 * 监听器在事务提交后广播 WS {@code update_order} / {@code cancel_item}。
 */
public class KdsItemStatusChangedEvent extends ApplicationEvent {

    private final int shopId;
    private final int detailId;
    private final Integer orderId;
    private final String screenTag;
    private final Integer fromStatus;
    private final int toStatus;
    private final String workflowQueue;
    private final Map<String, Object> payload;

    public KdsItemStatusChangedEvent(Object source, int shopId, int detailId, Integer orderId,
                                     String screenTag, Integer fromStatus, int toStatus,
                                     String workflowQueue, Map<String, Object> payload) {
        super(source);
        this.shopId = shopId;
        this.detailId = detailId;
        this.orderId = orderId;
        this.screenTag = screenTag;
        this.fromStatus = fromStatus;
        this.toStatus = toStatus;
        this.workflowQueue = workflowQueue;
        this.payload = payload != null
                ? Collections.unmodifiableMap(new LinkedHashMap<>(payload))
                : Collections.emptyMap();
    }

    public int getShopId() {
        return shopId;
    }

    public int getDetailId() {
        return detailId;
    }

    public Integer getOrderId() {
        return orderId;
    }

    public String getScreenTag() {
        return screenTag;
    }

    public Integer getFromStatus() {
        return fromStatus;
    }

    public int getToStatus() {
        return toStatus;
    }

    public String getWorkflowQueue() {
        return workflowQueue;
    }

    public Map<String, Object> getPayload() {
        return payload;
    }
}

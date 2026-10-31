package com.lanf.kds.event;

import org.springframework.context.ApplicationEvent;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * KDS 门店规则配置已变化（settings / config/save）。
 * 监听器在事务提交后广播 WS {@code config_changed}，通知厨显端刷新本机设置。
 */
public class KdsConfigChangedEvent extends ApplicationEvent {

    private final int shopId;
    private final Map<String, Object> changedFields;

    public KdsConfigChangedEvent(Object source, int shopId, Map<String, Object> changedFields) {
        super(source);
        this.shopId = shopId;
        this.changedFields = changedFields != null
                ? Collections.unmodifiableMap(new LinkedHashMap<>(changedFields))
                : Collections.emptyMap();
    }

    public int getShopId() {
        return shopId;
    }

    public Map<String, Object> getChangedFields() {
        return changedFields;
    }
}

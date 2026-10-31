package com.lanf.payment.support;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import org.springframework.stereotype.Component;

import java.util.concurrent.TimeUnit;

@Component
public class PaymentNotifyState {

    private final Cache<String, Boolean> processedNotifications = Caffeine.newBuilder()
            .expireAfterWrite(5, TimeUnit.MINUTES)
            .maximumSize(10000)
            .build();

    private final Cache<String, Object> paymentOrderLocks = Caffeine.newBuilder()
            .expireAfterWrite(10, TimeUnit.MINUTES)
            .maximumSize(5000)
            .build();

    public Boolean getProcessed(String notifyId) {
        return processedNotifications.getIfPresent(notifyId);
    }

    public void markProcessed(String notifyId) {
        if (notifyId != null) {
            processedNotifications.put(notifyId, true);
        }
    }

    public Object lockFor(String key) {
        return paymentOrderLocks.get(key, k -> new Object());
    }
}

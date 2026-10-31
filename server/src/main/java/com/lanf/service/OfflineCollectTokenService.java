package com.lanf.service;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.lanf.dto.OfflineCollectTokenPayload;
import org.springframework.stereotype.Service;

import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

/**
 * 线下收款中转链接短时 token（默认 3 分钟）。
 */
@Service
public class OfflineCollectTokenService {

    public static final int TTL_MINUTES = 3;

    private final Cache<String, OfflineCollectTokenPayload> cache = Caffeine.newBuilder()
            .expireAfterWrite(TTL_MINUTES, TimeUnit.MINUTES)
            .maximumSize(50_000)
            .build();

    public String newToken(int shopId, String channel) {
        return newToken(shopId, channel, null);
    }

    public String newToken(int shopId, String channel, String merchantId) {
        String token = UUID.randomUUID().toString().replace("-", "");
        cache.put(token, new OfflineCollectTokenPayload(
                shopId, channel.trim().toLowerCase(), merchantId));
        return token;
    }

    public Optional<OfflineCollectTokenPayload> resolve(String token) {
        if (token == null || token.length() < 16) {
            return Optional.empty();
        }
        OfflineCollectTokenPayload p = cache.getIfPresent(token.trim());
        return Optional.ofNullable(p);
    }
}

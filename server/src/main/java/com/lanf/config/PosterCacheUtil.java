package com.lanf.config;

import org.springframework.stereotype.Component;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;

@Component
public class PosterCacheUtil {
    // 本地缓存容器（线程安全）
    private final Map<String, CacheValue> localCache = new ConcurrentHashMap<>();
    // 缓存过期时间（1小时，可调整）
    private static final long CACHE_EXPIRE_SECONDS = 3600;

    // 缓存值封装（含字节数组 + 过期时间）
    private static class CacheValue {
        byte[] data;
        long expireTime; // 过期时间戳（毫秒）

        CacheValue(byte[] data, long expireTime) {
            this.data = data;
            this.expireTime = expireTime;
        }
    }

    // 从缓存获取海报字节数组（本地缓存）
    public byte[] getPosterCache(String code) {
        if (code == null) return null;
        CacheValue cacheValue = localCache.get(code);
        // 检查缓存是否存在且未过期
        if (cacheValue == null || System.currentTimeMillis() > cacheValue.expireTime) {
            localCache.remove(code); // 清理过期缓存
            return null;
        }
        return cacheValue.data;
    }

    // 存入缓存（本地缓存，设置过期时间）
    public void setPosterCache(String code, byte[] posterBytes) {
        if (code == null || posterBytes == null) return;
        long expireTime = System.currentTimeMillis() + TimeUnit.SECONDS.toMillis(CACHE_EXPIRE_SECONDS);
        localCache.put(code, new CacheValue(posterBytes, expireTime));
    }
}
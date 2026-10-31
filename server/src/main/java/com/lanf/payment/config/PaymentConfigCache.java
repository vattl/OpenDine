package com.lanf.payment.config;

import com.lanf.payment.entity.PaymentCapabilityEntity;
import com.lanf.payment.entity.PaymentMerchantConfigEntity;
import com.lanf.payment.entity.PaymentNinefoldEntity;
import org.springframework.stereotype.Component;

import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Component
public class PaymentConfigCache {

    public static final int GLOBAL_SHOP_ID = 0;

    private final ConcurrentHashMap<Integer, PaymentCapabilityEntity> capabilityByShop = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<Integer, PaymentNinefoldEntity> ninefoldByShop = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, List<PaymentMerchantConfigEntity>> merchantsByShopChannel = new ConcurrentHashMap<>();

    public void putCapability(int shopId, PaymentCapabilityEntity row) {
        if (row != null) {
            capabilityByShop.put(normalizeShopId(shopId), row);
        }
    }

    public PaymentCapabilityEntity getCapabilityRow(int shopId) {
        return capabilityByShop.get(normalizeShopId(shopId));
    }

    public void putNinefold(int shopId, PaymentNinefoldEntity row) {
        if (row != null) {
            ninefoldByShop.put(normalizeShopId(shopId), row);
        }
    }

    public PaymentNinefoldEntity getNinefoldRow(int shopId) {
        return ninefoldByShop.get(normalizeShopId(shopId));
    }

    public void invalidateNinefold(int shopId) {
        ninefoldByShop.remove(normalizeShopId(shopId));
    }

    public void putMerchants(int shopId, String channel, List<PaymentMerchantConfigEntity> rows) {
        merchantsByShopChannel.put(cacheKey(shopId, channel),
                rows == null ? Collections.emptyList() : Collections.unmodifiableList(new java.util.ArrayList<>(rows)));
    }

    public List<PaymentMerchantConfigEntity> getMerchants(int shopId, String channel) {
        List<PaymentMerchantConfigEntity> list = merchantsByShopChannel.get(cacheKey(shopId, channel));
        return list == null ? Collections.emptyList() : list;
    }

    public void invalidateShop(int shopId) {
        int sid = normalizeShopId(shopId);
        capabilityByShop.remove(sid);
        ninefoldByShop.remove(sid);
        merchantsByShopChannel.entrySet().removeIf(e -> e.getKey().startsWith(sid + ":"));
    }

    public void clearAll() {
        capabilityByShop.clear();
        ninefoldByShop.clear();
        merchantsByShopChannel.clear();
    }

    public static int normalizeShopId(Integer shopId) {
        if (shopId == null || shopId < 0) {
            return GLOBAL_SHOP_ID;
        }
        return shopId;
    }

    private static String cacheKey(int shopId, String channel) {
        return normalizeShopId(shopId) + ":" + (channel == null ? "" : channel.trim().toLowerCase());
    }
}

package com.lanf.payment.service;

import com.lanf.payment.entity.PaymentMerchantPolicyEntity;
import com.lanf.payment.mapper.PaymentMerchantPolicyMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.Date;
import java.util.LinkedHashMap;
import java.util.Map;

@Service
public class PaymentMerchantPolicyService {
    @Autowired private PaymentMerchantPolicyMapper mapper;

    public boolean allowsGlobalFallback(int shopId) {
        if (shopId <= 0) return true;
        PaymentMerchantPolicyEntity row = mapper.selectById(shopId);
        return row != null && row.getAllow_global_fallback() != null && row.getAllow_global_fallback() != 0;
    }

    public Map<String, Object> get(int shopId) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("shopId", shopId);
        out.put("allowGlobalFallback", allowsGlobalFallback(shopId));
        return out;
    }

    public Map<String, Object> save(int shopId, boolean allow) {
        if (shopId <= 0) throw new IllegalArgumentException("商户策略只能配置到具体门店");
        PaymentMerchantPolicyEntity row = mapper.selectById(shopId);
        Date now = new Date();
        if (row == null) {
            row = new PaymentMerchantPolicyEntity();
            row.setShop_id(shopId);
            row.setCreated_at(now);
            row.setUpdated_at(now);
            row.setAllow_global_fallback(allow ? 1 : 0);
            mapper.insert(row);
        } else {
            row.setAllow_global_fallback(allow ? 1 : 0);
            row.setUpdated_at(now);
            mapper.updateById(row);
        }
        return get(shopId);
    }
}

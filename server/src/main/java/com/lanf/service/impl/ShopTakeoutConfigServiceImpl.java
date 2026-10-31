package com.lanf.service.impl;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.ShopTakeoutConfig;
import com.lanf.mapper.ShopTakeoutConfigMapper;
import com.lanf.service.IShopTakeoutConfigService;
import com.lanf.util.ShopTakeoutConfigFormHelper;
import org.springframework.stereotype.Service;

import java.util.Map;

@Service
public class ShopTakeoutConfigServiceImpl extends ServiceImpl<ShopTakeoutConfigMapper, ShopTakeoutConfig> implements IShopTakeoutConfigService {

    @Override
    public ShopTakeoutConfig resolveForShop(int shopId) {
        ShopTakeoutConfig c = getById(shopId);
        if (c != null) {
            return c;
        }
        return ShopTakeoutConfigFormHelper.newDefault(shopId);
    }

    @Override
    public void upsertForShop(ShopTakeoutConfig row) {
        if (row == null || row.getShop_id() == null) {
            return;
        }
        ShopTakeoutConfig target = getById(row.getShop_id());
        if (target == null) {
            target = ShopTakeoutConfigFormHelper.newDefault(row.getShop_id());
        }
        mergeEntity(target, row);
        saveOrUpdate(target);
    }

    @Override
    public ShopTakeoutConfig upsertForShopFromMap(int shopId, Map<String, Object> body) {
        ShopTakeoutConfig target = getById(shopId);
        if (target == null) {
            target = ShopTakeoutConfigFormHelper.newDefault(shopId);
        }
        ShopTakeoutConfigFormHelper.applyMap(target, body);
        saveOrUpdate(target);
        return target;
    }

    private static void mergeEntity(ShopTakeoutConfig target, ShopTakeoutConfig patch) {
        if (patch.getEnabled() != null) {
            target.setEnabled(patch.getEnabled());
        }
        if (patch.getDelivery_fee() != null) {
            target.setDelivery_fee(patch.getDelivery_fee());
        }
        if (patch.getMin_order_amount() != null) {
            target.setMin_order_amount(patch.getMin_order_amount());
        }
        if (patch.getFree_delivery_threshold() != null) {
            target.setFree_delivery_threshold(patch.getFree_delivery_threshold());
        }
        if (patch.getMax_delivery_distance_km() != null) {
            target.setMax_delivery_distance_km(patch.getMax_delivery_distance_km());
        }
        if (patch.getFree_delivery_max_distance_km() != null) {
            target.setFree_delivery_max_distance_km(patch.getFree_delivery_max_distance_km());
        }
        if (patch.getDelivery_fee_tiers_json() != null) {
            target.setDelivery_fee_tiers_json(patch.getDelivery_fee_tiers_json());
        }
        if (patch.getLead_time_minutes() != null) {
            target.setLead_time_minutes(patch.getLead_time_minutes());
        }
        if (patch.getRemark() != null) {
            target.setRemark(patch.getRemark());
        }
        if (patch.getZsq_enabled() != null) {
            target.setZsq_enabled(patch.getZsq_enabled());
        }
        if (patch.getZsq_auto_dispatch() != null) {
            target.setZsq_auto_dispatch(patch.getZsq_auto_dispatch());
        }
        if (patch.getZsq_from_address_id() != null) {
            target.setZsq_from_address_id(patch.getZsq_from_address_id());
        }
        if (patch.getZsq_city_name() != null) {
            target.setZsq_city_name(patch.getZsq_city_name());
        }
        target.setUpdated_at(new java.util.Date());
    }
}

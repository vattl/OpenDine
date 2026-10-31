package com.lanf.payment.config;

import com.lanf.payment.PaymentChannels;
import com.lanf.payment.channel.wechat.WechatPlatformPublicKeyLoader;
import com.lanf.payment.entity.PaymentCapabilityEntity;
import com.lanf.payment.entity.PaymentMerchantConfigEntity;
import com.lanf.payment.entity.PaymentNinefoldEntity;
import com.lanf.payment.mapper.PaymentCapabilityMapper;
import com.lanf.payment.mapper.PaymentMerchantConfigMapper;
import com.lanf.payment.mapper.PaymentNinefoldMapper;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import javax.annotation.PostConstruct;
import java.util.List;

/**
 * 启动时加载支付配置到内存缓存；后台更新后调用 {@link #reloadAll()} 或按店刷新。
 */
@Component
public class PaymentConfigSync {

    private static final Logger log = LoggerFactory.getLogger(PaymentConfigSync.class);

    @Autowired
    private PaymentCapabilityMapper capabilityMapper;
    @Autowired
    private PaymentMerchantConfigMapper merchantMapper;
    @Autowired
    private PaymentNinefoldMapper ninefoldMapper;
    @Autowired
    private PaymentConfigCache configCache;
    @Autowired
    private WechatPlatformPublicKeyLoader platformPublicKeyLoader;

    @PostConstruct
    public void loadFromDb() {
        try {
            reloadAll();
        } catch (Exception e) {
            log.warn("加载支付配置失败（表可能未迁移）: {}", e.getMessage());
        }
    }

    public void reloadAll() {
        configCache.clearAll();
        List<PaymentCapabilityEntity> caps = capabilityMapper.selectList(new QueryWrapper<>());
        if (caps != null) {
            for (PaymentCapabilityEntity c : caps) {
                if (c != null && c.getShop_id() != null) {
                    configCache.putCapability(c.getShop_id(), c);
                }
            }
        }
        List<PaymentMerchantConfigEntity> merchants = merchantMapper.selectList(
                new QueryWrapper<PaymentMerchantConfigEntity>().eq("channel", PaymentChannels.WECHAT));
        if (merchants != null) {
            merchants.stream()
                    .collect(java.util.stream.Collectors.groupingBy(PaymentMerchantConfigEntity::getShop_id))
                    .forEach((shopId, rows) -> configCache.putMerchants(shopId, PaymentChannels.WECHAT, rows));
        }
        List<PaymentNinefoldEntity> ninefolds = ninefoldMapper.selectList(new QueryWrapper<>());
        if (ninefolds != null) {
            for (PaymentNinefoldEntity n : ninefolds) {
                if (n != null && n.getShop_id() != null) {
                    configCache.putNinefold(n.getShop_id(), n);
                }
            }
        }
        log.info("支付配置已加载: capabilityRows={}, wechatMerchantRows={}, ninefoldRows={}",
                caps == null ? 0 : caps.size(), merchants == null ? 0 : merchants.size(),
                ninefolds == null ? 0 : ninefolds.size());
        platformPublicKeyLoader.invalidateAll();
    }

    public void reloadShop(int shopId) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        PaymentCapabilityEntity cap = capabilityMapper.selectOne(new QueryWrapper<PaymentCapabilityEntity>()
                .eq("shop_id", sid).last("LIMIT 1"));
        if (cap != null) {
            configCache.putCapability(sid, cap);
        } else {
            configCache.invalidateShop(sid);
        }
        List<PaymentMerchantConfigEntity> wx = merchantMapper.selectList(
                new QueryWrapper<PaymentMerchantConfigEntity>()
                        .eq("shop_id", sid)
                        .eq("channel", PaymentChannels.WECHAT));
        configCache.putMerchants(sid, PaymentChannels.WECHAT, wx);
        PaymentNinefoldEntity ninefold = ninefoldMapper.selectOne(new QueryWrapper<PaymentNinefoldEntity>()
                .eq("shop_id", sid).last("LIMIT 1"));
        if (ninefold != null) {
            configCache.putNinefold(sid, ninefold);
        } else {
            configCache.invalidateNinefold(sid);
        }
        platformPublicKeyLoader.invalidateAll();
    }
}

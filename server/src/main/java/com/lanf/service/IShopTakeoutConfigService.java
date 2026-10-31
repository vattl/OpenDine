package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.ShopTakeoutConfig;

import java.util.Map;

public interface IShopTakeoutConfigService extends IService<ShopTakeoutConfig> {

    /**
     * 无配置行时返回关闭外卖的默认对象（不落库）。
     */
    ShopTakeoutConfig resolveForShop(int shopId);

    void upsertForShop(ShopTakeoutConfig row);

    /** 按请求 Map 合并保存（支持 boolean 开关与 camelCase 字段名） */
    ShopTakeoutConfig upsertForShopFromMap(int shopId, Map<String, Object> body);
}

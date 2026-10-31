package com.lanf.service;

import com.lanf.entity.StockPrepConfig;

/**
 * 门店备货规则（t_stock_prep_config）
 */
public interface IStockPrepConfigService {

    /** 有则返回，无则返回 null（不自动插入） */
    StockPrepConfig getByShopId(Integer shopId);

    /**
     * 读取或创建默认配置（用于生成备货计划时保证有安全库存系数等）。
     */
    StockPrepConfig getOrCreateForShop(Integer shopId);

    void saveConfig(StockPrepConfig config);
}

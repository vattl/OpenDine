package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.StockPrepConfig;
import com.lanf.mapper.StockPrepConfigMapper;
import com.lanf.service.IStockPrepConfigService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;

@Service
public class StockPrepConfigServiceImpl implements IStockPrepConfigService {

    @Autowired
    private StockPrepConfigMapper stockPrepConfigMapper;

    @Override
    public StockPrepConfig getByShopId(Integer shopId) {
        if (shopId == null) {
            return null;
        }
        return stockPrepConfigMapper.selectOne(new QueryWrapper<StockPrepConfig>().eq("shop_id", shopId).last("LIMIT 1"));
    }

    @Override
    public StockPrepConfig getOrCreateForShop(Integer shopId) {
        if (shopId == null) {
            return null;
        }
        StockPrepConfig c = getByShopId(shopId);
        if (c != null) {
            return c;
        }
        StockPrepConfig n = new StockPrepConfig();
        n.setShop_id(shopId);
        n.setSafe_stock_rate(new BigDecimal("0.10"));
        n.setDefault_loss_rate(new BigDecimal("0.05"));
        n.setForecast_days(3);
        n.setHistory_days(30);
        n.setWeather_factor(BigDecimal.ONE);
        n.setHoliday_factor(new BigDecimal("1.20"));
        n.setMember_factor(BigDecimal.ONE);
        n.setIs_enabled(1);
        stockPrepConfigMapper.insert(n);
        return n;
    }

    @Override
    public void saveConfig(StockPrepConfig config) {
        if (config == null || config.getShop_id() == null) {
            throw new RuntimeException("shop_id 不能为空");
        }
        StockPrepConfig existing = getByShopId(config.getShop_id());
        if (existing != null) {
            config.setId(existing.getId());
            stockPrepConfigMapper.updateById(config);
        } else {
            if (config.getSafe_stock_rate() == null) {
                config.setSafe_stock_rate(new BigDecimal("0.10"));
            }
            if (config.getDefault_loss_rate() == null) {
                config.setDefault_loss_rate(new BigDecimal("0.05"));
            }
            if (config.getForecast_days() == null) {
                config.setForecast_days(3);
            }
            if (config.getHistory_days() == null) {
                config.setHistory_days(30);
            }
            if (config.getWeather_factor() == null) {
                config.setWeather_factor(BigDecimal.ONE);
            }
            if (config.getHoliday_factor() == null) {
                config.setHoliday_factor(new BigDecimal("1.20"));
            }
            if (config.getMember_factor() == null) {
                config.setMember_factor(BigDecimal.ONE);
            }
            if (config.getIs_enabled() == null) {
                config.setIs_enabled(1);
            }
            stockPrepConfigMapper.insert(config);
        }
    }
}

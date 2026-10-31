package com.lanf.schedule;

import com.lanf.entity.Shop;
import com.lanf.service.IShopService;
import com.lanf.service.StockPrepForecastService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * 每日自动预测并落库（可选）。与落地方案「每日凌晨预测」一致；默认关闭。
 */
@Slf4j
@Component
@ConditionalOnProperty(prefix = "stock-prep-forecast", name = "scheduled-enabled", havingValue = "true")
public class StockPrepForecastScheduler {

    @Autowired
    private IShopService shopService;
    @Autowired
    private StockPrepForecastService stockPrepForecastService;

    @Scheduled(cron = "${stock-prep-forecast.scheduled-cron:0 0 3 * * ?}")
    public void nightlyPersistForecast() {
        List<Shop> shops = shopService.list();
        if (shops == null) {
            return;
        }
        for (Shop s : shops) {
            if (s == null || s.getId() == null) {
                continue;
            }
            try {
                stockPrepForecastService.buildForecast(s.getId(), null, null, true);
                log.info("备货预测定时任务已落库 shopId={}", s.getId());
            } catch (Exception e) {
                log.warn("备货预测定时任务失败 shopId={}: {}", s.getId(), e.toString());
            }
        }
    }
}

package com.lanf.kds.schedule;

import com.lanf.entity.Shop;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.service.KdsConfigService;
import com.lanf.kds.service.KdsTicketFlagService;
import com.lanf.service.IShopService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * 定时扫描待做工单 SLA，持久化 overdue_flag 并 WS 多屏同步。
 */
@Slf4j
@Component
public class KdsTicketSlaScheduler {

    @Autowired
    private IShopService shopService;
    @Autowired
    private KdsConfigService configService;
    @Autowired
    private KdsTicketFlagService ticketFlagService;

    @Scheduled(cron = "${kds.sla-scan-cron:0 * * * * ?}")
    public void scanOverdueFlags() {
        List<Shop> shops = shopService.list();
        if (shops == null) {
            return;
        }
        for (Shop shop : shops) {
            if (shop == null || shop.getId() == null) {
                continue;
            }
            try {
                KdsShopConfig cfg = configService.getOrDefault(shop.getId());
                int slaMinutes = cfg.getSla_minutes() != null ? cfg.getSla_minutes() : 10;
                int n = ticketFlagService.refreshOverdueForShop(shop.getId(), slaMinutes * 60);
                if (n > 0) {
                    log.debug("[kds] overdue flags updated shopId={} count={}", shop.getId(), n);
                }
            } catch (Exception e) {
                log.warn("[kds] overdue scan failed shopId={}: {}", shop.getId(), e.getMessage());
            }
        }
    }
}

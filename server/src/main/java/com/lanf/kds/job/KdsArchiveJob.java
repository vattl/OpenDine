package com.lanf.kds.job;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.service.KdsConfigService;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsShopConfigMapper;
import com.lanf.kds.mapper.KdsTicketMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.Calendar;
import java.util.Date;
import java.util.List;

/**
 * 已完成工单超时归档（默认 2 小时，按门店 archive_hours 配置）。
 */
@Component
public class KdsArchiveJob {

    private static final Logger log = LoggerFactory.getLogger(KdsArchiveJob.class);

    @Autowired
    private KdsTicketMapper ticketMapper;
    @Autowired
    private KdsShopConfigMapper shopConfigMapper;
    @Autowired
    private com.lanf.kds.service.KdsV2RetentionService retentionService;
    @Autowired(required = false)
    private com.lanf.kds.service.KdsWorkflowV2Service workflowV2Service;

    @Scheduled(cron = "0 */15 * * * ?")
    public void archiveDoneTickets() {
        List<KdsShopConfig> configs = shopConfigMapper.selectList(null);
        if (configs == null || configs.isEmpty()) {
            return;
        }
        int total = 0;
        for (KdsShopConfig cfg : configs) {
            if (cfg == null || cfg.getShop_id() == null) {
                continue;
            }
            if (KdsConfigService.MODE_PRINT_ONLY.equals(cfg.getKds_mode())) {
                continue;
            }
            int hours = cfg.getArchive_hours() != null && cfg.getArchive_hours() > 0 ? cfg.getArchive_hours() : 2;
            Calendar cal = Calendar.getInstance();
            cal.add(Calendar.HOUR_OF_DAY, -hours);
            Date before = cal.getTime();
            int n = ticketMapper.update(null, new UpdateWrapper<KdsTicket>()
                    .eq("shop_id", cfg.getShop_id())
                    .eq("item_status", KdsItemStatus.DONE)
                    .eq("archived", 0)
                    .lt("done_at", before)
                    .set("archived", 1));
            total += n;

            // 异步维护：归档上一营业日遗留未划工单与批量缺票自愈，移出 bootstrap 读取热路径
            if (workflowV2Service != null) {
                try {
                    Date bizDayStart = workflowV2Service.businessDayStart(cfg.getShop_id());
                    workflowV2Service.archiveStalePastDayTickets(cfg.getShop_id(), bizDayStart);
                    int compensated = workflowV2Service.compensateMissingTicketsForActiveOrdersBatch(cfg.getShop_id(), bizDayStart);
                    if (compensated > 0) {
                        log.info("[kds] batch compensated {} missing tickets for shop {}", compensated, cfg.getShop_id());
                    }
                } catch (Exception ex) {
                    log.warn("[kds] background integrity maintenance failed for shop {}: {}", cfg.getShop_id(), ex.getMessage());
                }
            }
        }
        if (total > 0) {
            log.info("[kds] archived {} done tickets", total);
        }

        try {
            if (retentionService != null) {
                int archivedCommands = retentionService.archiveTerminalCommandsAllShops(7, 500);
                if (archivedCommands > 0) {
                    log.info("[kds] archived {} terminal V2 commands into cold archive", archivedCommands);
                }
            }
        } catch (Exception ex) {
            log.error("[kds] failed to run V2 command retention archive: {}", ex.getMessage());
        }
    }
}

package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.entity.KdsSyncDedup;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsSyncDedupMapper;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.service.IOrderDetailService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.*;

@Service
public class KdsSyncService {

    private static final Logger log = LoggerFactory.getLogger(KdsSyncService.class);

    @Autowired
    private KdsSyncDedupMapper dedupMapper;
    @Autowired
    private KdsTicketService ticketService;
    @Autowired
    private KdsTicketMapper ticketMapper;
    @Autowired
    private IOrderDetailService orderDetailService;

    /**
     * 离线批量回写（功能需求 F-SYNC-03/04）。
     * 不加外层事务：每条 updateItemStatus 自带事务独立提交/回滚，
     * 单条失败（工单不存在/非法转换）不污染其它条目，保证离线补偿的最大可达性。
     */
    public Map<String, Object> syncAll(int shopId, String screenTag, Long stationId, List<Map<String, Object>> items) {
        int applied = 0;
        int skipped = 0;
        if (items == null) {
            items = Collections.emptyList();
        }
        for (Map<String, Object> item : items) {
            String clientId = str(item.get("client_id"));
            if (clientId == null) {
                continue;
            }
            if (dedupMapper.selectById(clientId) != null) {
                skipped++;
                continue;
            }
            Integer detailId = intVal(item.get("detail_id"));
            Integer status = intVal(item.get("status"));
            if (detailId == null || status == null) {
                continue;
            }
            try {
                ticketService.updateItemStatus(shopId, detailId, status, screenTag, stationId);
                KdsSyncDedup d = new KdsSyncDedup();
                d.setClient_id(clientId);
                d.setShop_id(shopId);
                d.setCreated_at(new Date());
                dedupMapper.insert(d);
                applied++;
            } catch (Exception e) {
                log.warn("[kds] sync failed for clientId={}, detailId={}, status={}: {}", 
                        clientId, detailId, status, e.getMessage());
                skipped++;
            }
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("applied", applied);
        result.put("skipped", skipped);
        return result;
    }

    public List<Map<String, Object>> changesSince(int shopId, String screenTag, long sinceMs) {
        Date since = new Date(sinceMs);
        QueryWrapper<KdsTicket> q = new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .gt("updated_at", since)
                .orderByAsc("updated_at");
        // workflow_board 工单实际落在 meat_grill/skewer_aggregate 等屏，不能按 screen_tag=workflow_board 过滤
        if (screenTag != null && !screenTag.isEmpty()
                && !KdsScreenTag.WORKFLOW_BOARD.equals(screenTag)) {
            q.eq("screen_tag", screenTag);
        }
        List<KdsTicket> tickets = ticketMapper.selectList(q);
        List<Map<String, Object>> out = new ArrayList<>();
        if (tickets == null) {
            return out;
        }
        Set<Integer> detailIds = new HashSet<>();
        for (KdsTicket t : tickets) {
            if (t.getDetail_id() != null) {
                detailIds.add(t.getDetail_id());
            }
        }
        Map<Integer, Integer> dishIdByDetailId = new HashMap<>();
        if (!detailIds.isEmpty()) {
            for (OrderDetail d : orderDetailService.listByIds(detailIds)) {
                if (d != null && d.getId() != null) {
                    dishIdByDetailId.put(d.getId(), d.getDish_id());
                }
            }
        }
        for (KdsTicket t : tickets) {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("ticket_id", t.getId());
            row.put("detail_id", t.getDetail_id());
            row.put("dish_id", t.getDetail_id() != null ? dishIdByDetailId.get(t.getDetail_id()) : null);
            row.put("order_id", t.getOrder_id());
            row.put("item_status", t.getItem_status());
            row.put("screen_tag", t.getScreen_tag());
            row.put("updated_at", t.getUpdated_at());
            row.put("rush_flag", t.getRush_flag() != null ? t.getRush_flag() : 0);
            row.put("add_dish_flag", t.getAdd_dish_flag() != null ? t.getAdd_dish_flag() : 0);
            row.put("overdue_flag", t.getOverdue_flag() != null ? t.getOverdue_flag() : 0);
            if (t.getRush_at() != null) {
                row.put("rush_at", t.getRush_at());
            }
            if (t.getOverdue_at() != null) {
                row.put("overdue_at", t.getOverdue_at());
            }
            out.add(row);
        }
        return out;
    }

    private static String str(Object o) {
        if (o == null) {
            return null;
        }
        String s = o.toString().trim();
        return s.isEmpty() ? null : s;
    }

    private static Integer intVal(Object o) {
        if (o instanceof Number) {
            return ((Number) o).intValue();
        }
        if (o != null) {
            try {
                return Integer.parseInt(o.toString().trim());
            } catch (NumberFormatException ignore) {
                return null;
            }
        }
        return null;
    }
}

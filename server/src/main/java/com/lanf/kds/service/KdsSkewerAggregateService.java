package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.support.KdsPushPayloadBuilder;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.*;

@Service
public class KdsSkewerAggregateService {

    @Autowired
    private KdsTicketMapper ticketMapper;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private KdsPushService pushService;
    @Autowired
    private KdsConfigService configService;

    /**
     * 待抓串汇总：仅 skewer_picked=0 且待制作的烤制工单。
     */
    public List<Map<String, Object>> summary(int shopId) {
        if (!configService.isSkewerGateEnabled(shopId)) {
            return Collections.emptyList();
        }
        List<KdsTicket> tickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .eq("item_status", KdsItemStatus.PENDING)
                .eq("skewer_picked", 0)
                .eq("archived", 0)
                .in("screen_tag", KdsScreenTag.MEAT_GRILL, KdsScreenTag.VEG_GRILL, KdsScreenTag.SEAFOOD_SPECIAL));
        if (tickets == null || tickets.isEmpty()) {
            return Collections.emptyList();
        }
        Map<String, AggregateRow> map = new LinkedHashMap<>();
        for (KdsTicket t : tickets) {
            OrderDetail d = orderDetailService.getById(t.getDetail_id());
            if (d == null || !StringUtils.hasText(d.getName())) {
                continue;
            }
            String name = d.getName().trim();
            int qty = parseQty(d.getQuantity());
            AggregateRow row = map.computeIfAbsent(name, k -> new AggregateRow(name, d.getUnit()));
            row.quantity += qty;
            row.ticketIds.add(t.getId());
            row.detailIds.add(t.getDetail_id());
            row.targetScreens.add(t.getScreen_tag());
        }
        List<Map<String, Object>> out = new ArrayList<>();
        for (AggregateRow row : map.values()) {
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("dish_name", row.name);
            item.put("quantity", row.quantity);
            item.put("unit", row.unit);
            item.put("detail_ids", row.detailIds);
            item.put("target_screens", new ArrayList<>(row.targetScreens));
            out.add(item);
        }
        out.sort(Comparator.comparing(m -> String.valueOf(m.get("dish_name"))));
        return out;
    }

    /**
     * 抓串完成：标记 skewer_picked=1，保持 item_status=待制作，并 WS 分流至对应烤制屏。
     */
    @Transactional
    public int picked(int shopId, String dishName, List<Integer> detailIds) {
        if (!configService.isSkewerGateEnabled(shopId)) {
            throw new IllegalStateException("门店未启用抓串闸门");
        }
        if (!StringUtils.hasText(dishName) && (detailIds == null || detailIds.isEmpty())) {
            throw new IllegalArgumentException("dish_name 或 detail_ids 必填");
        }
        Set<Integer> targets = resolveTargetDetailIds(shopId, dishName, detailIds);
        if (targets.isEmpty()) {
            return 0;
        }
        Date now = new Date();
        int updated = 0;
        Map<Integer, Set<String>> orderScreens = new LinkedHashMap<>();
        Map<Integer, Map<String, List<OrderDetail>>> orderScreenDetails = new LinkedHashMap<>();
        for (Integer detailId : targets) {
            if (detailId == null) {
                continue;
            }
            List<KdsTicket> tickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                    .eq("shop_id", shopId)
                    .eq("detail_id", detailId)
                    .eq("skewer_picked", 0)
                    .eq("item_status", KdsItemStatus.PENDING));
            OrderDetail detailRow = orderDetailService.getById(detailId);
            for (KdsTicket t : tickets) {
                ticketMapper.update(null, new UpdateWrapper<KdsTicket>()
                        .eq("id", t.getId())
                        .set("skewer_picked", 1)
                        .set("skewer_picked_at", now)
                        .set("updated_at", now));
                if (t.getOrder_id() != null && t.getScreen_tag() != null) {
                    orderScreens.computeIfAbsent(t.getOrder_id(), k -> new LinkedHashSet<>())
                            .add(t.getScreen_tag());
                    if (detailRow != null) {
                        orderScreenDetails
                                .computeIfAbsent(t.getOrder_id(), k -> new LinkedHashMap<>())
                                .computeIfAbsent(t.getScreen_tag(), k -> new ArrayList<>())
                                .add(detailRow);
                    }
                }
                updated++;
            }
        }
        for (Map.Entry<Integer, Set<String>> e : orderScreens.entrySet()) {
            Order order = orderService.getById(e.getKey());
            if (order == null) {
                continue;
            }
            Map<String, List<OrderDetail>> byScreen = orderScreenDetails.getOrDefault(e.getKey(), Collections.emptyMap());
            for (String screen : e.getValue()) {
                Map<String, Object> payload = KdsPushPayloadBuilder.newOrder(
                        order, null, byScreen.getOrDefault(screen, Collections.emptyList()));
                payload.put("skewer_released", true);
                pushService.newOrder(shopId, screen, payload);
            }
        }
        Map<String, Object> skewerPayload = new LinkedHashMap<>();
        skewerPayload.put("dish_name", dishName);
        skewerPayload.put("picked_count", updated);
        pushService.updateOrder(shopId, KdsScreenTag.SKEWER_AGGREGATE, skewerPayload);
        return updated;
    }

    private Set<Integer> resolveTargetDetailIds(int shopId, String dishName, List<Integer> detailIds) {
        Set<Integer> targets = new HashSet<>();
        if (detailIds != null) {
            targets.addAll(detailIds);
        }
        if (StringUtils.hasText(dishName)) {
            for (Map<String, Object> row : summary(shopId)) {
                if (dishName.trim().equals(String.valueOf(row.get("dish_name")))) {
                    @SuppressWarnings("unchecked")
                    List<Integer> ids = (List<Integer>) row.get("detail_ids");
                    if (ids != null) {
                        targets.addAll(ids);
                    }
                }
            }
        }
        return targets;
    }

    private static int parseQty(String q) {
        if (q == null || q.trim().isEmpty()) {
            return 1;
        }
        try {
            return Math.max(1, Integer.parseInt(q.trim()));
        } catch (NumberFormatException e) {
            return 1;
        }
    }

    private static final class AggregateRow {
        final String name;
        final String unit;
        int quantity;
        final List<Long> ticketIds = new ArrayList<>();
        final List<Integer> detailIds = new ArrayList<>();
        final Set<String> targetScreens = new HashSet<>();

        AggregateRow(String name, String unit) {
            this.name = name;
            this.unit = unit;
        }
    }
}

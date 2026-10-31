package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.stream.Collectors;

@Service
public class KdsOrderListService {

    @Autowired
    private KdsTicketMapper ticketMapper;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private KdsConfigService configService;
    @Autowired
    private KdsDishServingDurationService servingDurationService;

    public List<Map<String, Object>> listOrderCards(int shopId, String screenTag, Integer itemStatus,
                                                    boolean includeArchived, int page, int pageSize) {
        if (KdsScreenTag.EXPEDITION.equals(screenTag)) {
            itemStatus = itemStatus != null ? itemStatus : KdsItemStatus.DONE;
        }
        QueryWrapper<KdsTicket> q = new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId);
        if (KdsScreenTag.EXPEDITION.equals(screenTag)) {
            // 总出餐屏：汇总各烤制岗已完成的工单（不展示待做/制作中）
            q.eq("item_status", KdsItemStatus.DONE)
                    .in("screen_tag", KdsScreenTag.MEAT_GRILL, KdsScreenTag.VEG_GRILL, KdsScreenTag.SEAFOOD_SPECIAL);
        } else if (!KdsScreenTag.SKEWER_AGGREGATE.equals(screenTag)) {
            q.eq("screen_tag", screenTag);
            if (configService.isSkewerGateEnabled(shopId)) {
                q.eq("skewer_picked", 1);
            }
            if (itemStatus != null) {
                q.eq("item_status", itemStatus);
            } else {
                q.in("item_status", KdsItemStatus.PENDING, KdsItemStatus.COOKING, KdsItemStatus.DONE);
            }
        } else {
            return Collections.emptyList();
        }
        if (!includeArchived) {
            q.eq("archived", 0);
        }
        q.orderByDesc("rush_flag").orderByAsc("created_at");
        int offset = Math.max(0, (page - 1) * pageSize);
        q.last("LIMIT " + offset + "," + pageSize);
        List<KdsTicket> tickets = ticketMapper.selectList(q);
        if (tickets == null || tickets.isEmpty()) {
            return Collections.emptyList();
        }
        KdsShopConfig cfg = configService.getOrDefault(shopId);
        int slaSeconds = (cfg.getSla_minutes() != null ? cfg.getSla_minutes() : 10) * 60;
        long now = System.currentTimeMillis();

        // 批量查询订单和明细，避免N+1问题
        Set<Integer> orderIds = tickets.stream()
                .map(KdsTicket::getOrder_id)
                .filter(Objects::nonNull)
                .collect(Collectors.toSet());
        Set<Integer> detailIds = tickets.stream()
                .map(KdsTicket::getDetail_id)
                .filter(Objects::nonNull)
                .collect(Collectors.toSet());
        
        Map<Integer, Order> orderMap = new HashMap<>();
        Map<Integer, OrderDetail> detailMap = new HashMap<>();
        
        if (!orderIds.isEmpty()) {
            List<Order> orders = orderService.listByIds(orderIds);
            orderMap = orders.stream()
                    .collect(Collectors.toMap(Order::getId, o -> o));
        }
        if (!detailIds.isEmpty()) {
            List<OrderDetail> details = orderDetailService.listByIds(detailIds);
            detailMap = details.stream()
                    .collect(Collectors.toMap(OrderDetail::getId, d -> d));
        }
        Map<Integer, Integer> secondsByDetail = servingDurationService.resolveSecondsByDetails(
                detailMap.values(), slaSeconds, shopId);

        Map<Integer, List<KdsTicket>> byOrder = tickets.stream()
                .collect(Collectors.groupingBy(KdsTicket::getOrder_id, LinkedHashMap::new, Collectors.toList()));

        List<Map<String, Object>> cards = new ArrayList<>();
        for (Map.Entry<Integer, List<KdsTicket>> e : byOrder.entrySet()) {
            Order order = orderMap.get(e.getKey());
            if (order == null) {
                continue;
            }
            Map<String, Object> card = new LinkedHashMap<>();
            card.put("order_id", order.getId());
            card.put("order_no", order.getOrder_no());
            card.put("table_number", order.getTable_number());
            card.put("dineInOrTakeOut", order.getDineInOrTakeOut());
            card.put("order_time", order.getOrder_time());
            card.put("remark", order.getRemark());
            card.put("orderNumber", order.getOrderNumber());
            card.put("rush_flag", e.getValue().stream().anyMatch(t -> t.getRush_flag() != null && t.getRush_flag() == 1) ? 1 : 0);
            card.put("add_dish_flag", e.getValue().stream().anyMatch(t -> t.getAdd_dish_flag() != null && t.getAdd_dish_flag() == 1) ? 1 : 0);
            List<Map<String, Object>> items = new ArrayList<>();
            boolean cardOverdue = false;
            for (KdsTicket t : e.getValue()) {
                OrderDetail detail = detailMap.get(t.getDetail_id());
                Map<String, Object> item = new LinkedHashMap<>();
                item.put("ticket_id", t.getId());
                item.put("detail_id", t.getDetail_id());
                item.put("item_status", t.getItem_status());
                item.put("screen_tag", t.getScreen_tag());
                if (detail != null) {
                    item.put("name", detail.getName());
                    item.put("quantity", detail.getQuantity());
                    item.put("unit", detail.getUnit());
                    item.put("remark", detail.getRemark());
                    item.put("selectedSpicy", detail.getSelectedSpicy());
                }
                long waitMs = t.getCreated_at() != null ? now - t.getCreated_at().getTime() : 0;
                int waitSeconds = (int) (waitMs / 1000);
                item.put("wait_seconds", waitSeconds);
                int itemSlaSeconds = KdsDishServingDurationService.secondsForDetail(
                        t.getDetail_id(), secondsByDetail, slaSeconds);
                item.put("serving_duration_minutes", itemSlaSeconds / 60);
                KdsTicketFlagService.appendFlagsToItemMap(item, t, order, detail, itemSlaSeconds, now);
                if (Boolean.TRUE.equals(item.get("overdue_flag"))) {
                    cardOverdue = true;
                }
                items.add(item);
            }
            card.put("overdue_flag", cardOverdue ? 1 : 0);
            card.put("items", items);
            cards.add(card);
        }
        return cards;
    }
}

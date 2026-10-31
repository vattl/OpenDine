package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.entity.KdsDishScreen;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsDishScreenMapper;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.mapper.DishShopMapper;
import com.lanf.service.IDishService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.*;
import java.util.stream.Collectors;

/**
 * 烤制屏三栏看板：左桌号队列 / 中菜品固定位汇总 / 右制作中。
 */
@Service
public class KdsGrillBoardService {

    @Autowired
    private KdsTicketMapper ticketMapper;
    @Autowired
    private KdsDishScreenMapper dishScreenMapper;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private IDishService dishService;
    @Autowired
    private DishShopMapper dishShopMapper;
    @Autowired
    private KdsConfigService configService;
    @Autowired
    private KdsTicketService ticketService;
    @Autowired
    private KdsDishServingDurationService servingDurationService;

    public Map<String, Object> buildBoard(int shopId, String screenTag) {
        return buildBoardFromContext(shopId, screenTag, loadBoardContext(shopId, screenTag));
    }

    /**
     * 按菜品名将本屏全部待做工单合并划为制作中（中间固定位点击）。
     */
    @Transactional
    public Map<String, Object> startCookingByDishName(int shopId, String screenTag, String dishName, Long stationId) {
        if (!isGrillScreen(screenTag)) {
            throw new IllegalArgumentException("仅烤制屏支持按菜品开始制作");
        }
        if (!StringUtils.hasText(dishName)) {
            throw new IllegalArgumentException("dish_name 不能为空");
        }
        String targetName = dishName.trim();
        BoardContext ctx = loadBoardContext(shopId, screenTag);
        List<Integer> detailIds = new ArrayList<>();
        int pendingQty = 0;
        for (KdsTicket t : ctx.tickets) {
            if (t.getItem_status() == null || t.getItem_status() != KdsItemStatus.PENDING) {
                continue;
            }
            OrderDetail d = ctx.detailMap.get(t.getDetail_id());
            if (d == null || !StringUtils.hasText(d.getName())) {
                continue;
            }
            if (!targetName.equals(d.getName().trim())) {
                continue;
            }
            detailIds.add(t.getDetail_id());
            pendingQty += parseQty(d.getQuantity());
        }
        if (detailIds.isEmpty()) {
            throw new IllegalArgumentException("该菜品暂无待制作工单");
        }
        for (Integer detailId : detailIds) {
            ticketService.updateItemStatus(shopId, detailId, KdsItemStatus.COOKING, screenTag, stationId);
        }
        BoardContext refreshed = loadBoardContext(shopId, screenTag);
        Map<String, Object> result = buildBoardFromContext(shopId, screenTag, refreshed);
        result.put("dish_name", targetName);
        result.put("updated", detailIds.size());
        result.put("started_quantity", pendingQty);
        return result;
    }

    private Map<String, Object> buildBoardFromContext(int shopId, String screenTag, BoardContext ctx) {
        if (!isGrillScreen(screenTag)) {
            throw new IllegalArgumentException("仅烤制屏支持三栏看板");
        }
        long now = System.currentTimeMillis();
        int slaSeconds = resolveSlaSeconds(shopId);
        Map<Integer, Integer> secondsByDetail = servingDurationService.resolveSecondsByDetails(
                ctx.detailMap.values(), slaSeconds, shopId);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("screen_tag", screenTag);
        result.put("sla_minutes", slaSeconds / 60);
        result.put("table_queue", buildTableQueue(ctx.tickets, ctx.orderMap, ctx.detailMap, now, slaSeconds, secondsByDetail));
        result.put("product_slots", buildProductSlots(shopId, screenTag, ctx.tickets, ctx.detailMap, now, slaSeconds, secondsByDetail));
        result.put("cooking", buildCookingList(ctx.tickets, ctx.orderMap, ctx.detailMap, now, slaSeconds, secondsByDetail));
        result.put("cooking_groups", buildCookingGroups(ctx.tickets, ctx.orderMap, ctx.detailMap, now));
        return result;
    }

    private int resolveSlaSeconds(int shopId) {
        KdsShopConfig cfg = configService.getOrDefault(shopId);
        int minutes = cfg.getSla_minutes() != null ? cfg.getSla_minutes() : 10;
        return Math.max(1, minutes) * 60;
    }

    private BoardContext loadBoardContext(int shopId, String screenTag) {
        QueryWrapper<KdsTicket> q = new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .eq("screen_tag", screenTag)
                .in("item_status", KdsItemStatus.PENDING, KdsItemStatus.COOKING)
                .eq("archived", 0);
        if (configService.isSkewerGateEnabled(shopId)) {
            q.eq("skewer_picked", 1);
        }
        q.orderByDesc("rush_flag").orderByAsc("created_at");
        List<KdsTicket> tickets = ticketMapper.selectList(q);
        if (tickets == null) {
            tickets = Collections.emptyList();
        }
        Set<Integer> orderIds = tickets.stream().map(KdsTicket::getOrder_id).filter(Objects::nonNull).collect(Collectors.toSet());
        Set<Integer> detailIds = tickets.stream().map(KdsTicket::getDetail_id).filter(Objects::nonNull).collect(Collectors.toSet());
        Map<Integer, Order> orderMap = orderIds.isEmpty() ? Collections.emptyMap()
                : orderService.listByIds(orderIds).stream().collect(Collectors.toMap(Order::getId, o -> o, (a, b) -> a));
        Map<Integer, OrderDetail> detailMap = detailIds.isEmpty() ? Collections.emptyMap()
                : orderDetailService.listByIds(detailIds).stream().collect(Collectors.toMap(OrderDetail::getId, d -> d, (a, b) -> a));
        return new BoardContext(tickets, orderMap, detailMap);
    }

    private List<Map<String, Object>> buildTableQueue(List<KdsTicket> tickets,
                                                      Map<Integer, Order> orderMap,
                                                      Map<Integer, OrderDetail> detailMap,
                                                      long now,
                                                      int slaSeconds,
                                                      Map<Integer, Integer> secondsByDetail) {
        Map<Integer, List<KdsTicket>> byOrder = tickets.stream()
                .filter(t -> t.getItem_status() != null && t.getItem_status() == KdsItemStatus.PENDING)
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
            card.put("order_time", order.getOrder_time());
            card.put("orderNumber", order.getOrderNumber());
            card.put("dineInOrTakeOut", order.getDineInOrTakeOut());
            card.put("remark", order.getRemark());
            card.put("rush_flag", e.getValue().stream().anyMatch(t -> t.getRush_flag() != null && t.getRush_flag() == 1) ? 1 : 0);
            List<Map<String, Object>> items = new ArrayList<>();
            boolean cardOverdue = false;
            for (KdsTicket t : e.getValue()) {
                int itemSlaSeconds = KdsDishServingDurationService.secondsForDetail(
                        t.getDetail_id(), secondsByDetail, slaSeconds);
                Map<String, Object> item = toItemRow(t, detailMap.get(t.getDetail_id()), now, itemSlaSeconds);
                if (Boolean.TRUE.equals(item.get("overdue_flag"))) {
                    cardOverdue = true;
                }
                items.add(item);
            }
            card.put("items", items);
            card.put("overdue_flag", cardOverdue);
            cards.add(card);
        }
        cards.sort(tableQueueComparator());
        return cards;
    }

    private List<Map<String, Object>> buildProductSlots(int shopId, String screenTag,
                                                         List<KdsTicket> tickets,
                                                         Map<Integer, OrderDetail> detailMap,
                                                         long now,
                                                         int slaSeconds,
                                                         Map<Integer, Integer> secondsByDetail) {
        Map<String, Integer> pendingByName = new LinkedHashMap<>();
        Map<String, Boolean> overdueByName = new LinkedHashMap<>();
        for (KdsTicket t : tickets) {
            if (t.getItem_status() == null || t.getItem_status() != KdsItemStatus.PENDING) {
                continue;
            }
            OrderDetail d = detailMap.get(t.getDetail_id());
            if (d == null || !StringUtils.hasText(d.getName())) {
                continue;
            }
            String name = d.getName().trim();
            int qty = parseQty(d.getQuantity());
            pendingByName.merge(name, qty, Integer::sum);
            int itemSlaSeconds = KdsDishServingDurationService.secondsForDetail(
                    t.getDetail_id(), secondsByDetail, slaSeconds);
            if (isOverduePending(t, now, itemSlaSeconds)) {
                overdueByName.put(name, true);
            }
        }

        List<KdsDishScreen> bindings = dishScreenMapper.selectList(new QueryWrapper<KdsDishScreen>()
                .eq("shop_id", shopId)
                .eq("screen_tag", screenTag)
                .orderByAsc("id"));
        List<SlotDef> defs = new ArrayList<>();
        if (bindings != null) {
            for (KdsDishScreen b : bindings) {
                if (b.getDish_id() == null) {
                    continue;
                }
                Dish dish = dishService.getById(b.getDish_id());
                if (dish == null || !StringUtils.hasText(dish.getName())) {
                    continue;
                }
                DishShop link = dishShopMapper.selectOne(new QueryWrapper<DishShop>()
                        .eq("shop_id", shopId)
                        .eq("dish_id", b.getDish_id())
                        .last("LIMIT 1"));
                if (link == null || !isOnsaleAtShop(dish, link)) {
                    continue;
                }
                // 门店覆盖：名称/单位/排序与 C 端菜单一致（覆盖列 NULL 回退总部）
                String slotName = StringUtils.hasText(link.getName_override())
                        ? link.getName_override() : dish.getName();
                String slotUnit = StringUtils.hasText(link.getUnit_override())
                        ? link.getUnit_override() : dish.getUnit();
                int sort = link.getSorting_override() != null ? link.getSorting_override()
                        : (dish.getSorting() != null ? dish.getSorting() : 9999);
                defs.add(new SlotDef(slotName.trim(), slotUnit, sort, b.getDish_id()));
            }
        }
        defs.sort(Comparator.<SlotDef>comparingInt(s -> s.sortKey).thenComparingInt(s -> s.dishId));

        List<Map<String, Object>> slots = new ArrayList<>();
        int slotIndex = 0;
        for (SlotDef def : defs) {
            int qty = pendingByName.getOrDefault(def.name, 0);
            boolean slotOverdue = Boolean.TRUE.equals(overdueByName.get(def.name));
            slots.add(slotRow(++slotIndex, def.dishId, def.name, def.unit, qty, slotOverdue));
        }
        return slots;
    }

    /** 门店维度是否上架：有 onsale_override 用 override，否则用总部 t_dish.onsale。 */
    private static boolean isOnsaleAtShop(Dish dish, DishShop link) {
        if (dish == null) {
            return false;
        }
        if (link != null && link.getOnsale_override() != null) {
            return link.getOnsale_override() == 1;
        }
        return dish.isOnsale();
    }

    private List<Map<String, Object>> buildCookingList(List<KdsTicket> tickets,
                                                        Map<Integer, Order> orderMap,
                                                        Map<Integer, OrderDetail> detailMap,
                                                        long now,
                                                        int slaSeconds,
                                                        Map<Integer, Integer> secondsByDetail) {
        List<Map<String, Object>> rows = new ArrayList<>();
        for (KdsTicket t : tickets) {
            if (t.getItem_status() == null || t.getItem_status() != KdsItemStatus.COOKING) {
                continue;
            }
            Order order = orderMap.get(t.getOrder_id());
            int itemSlaSeconds = KdsDishServingDurationService.secondsForDetail(
                    t.getDetail_id(), secondsByDetail, slaSeconds);
            Map<String, Object> row = toItemRow(t, detailMap.get(t.getDetail_id()), now, itemSlaSeconds);
            row.put("table_number", order != null ? order.getTable_number() : null);
            row.put("order_no", order != null ? order.getOrder_no() : t.getOrder_no());
            row.put("rush_flag", t.getRush_flag());
            rows.add(row);
        }
        rows.sort(Comparator
                .comparing((Map<String, Object> m) -> -(Integer) m.getOrDefault("rush_flag", 0))
                .thenComparing(m -> String.valueOf(m.get("table_number"))));
        return rows;
    }

    /** 右栏按菜品合并的制作中汇总（多桌同菜合并为一行）。 */
    private List<Map<String, Object>> buildCookingGroups(List<KdsTicket> tickets,
                                                         Map<Integer, Order> orderMap,
                                                         Map<Integer, OrderDetail> detailMap,
                                                         long now) {
        Map<String, CookingGroup> groups = new LinkedHashMap<>();
        for (KdsTicket t : tickets) {
            if (t.getItem_status() == null || t.getItem_status() != KdsItemStatus.COOKING) {
                continue;
            }
            OrderDetail d = detailMap.get(t.getDetail_id());
            if (d == null || !StringUtils.hasText(d.getName())) {
                continue;
            }
            String name = d.getName().trim();
            CookingGroup g = groups.computeIfAbsent(name, k -> new CookingGroup(name, d.getUnit()));
            g.quantity += parseQty(d.getQuantity());
            g.detailIds.add(t.getDetail_id());
            Order order = orderMap.get(t.getOrder_id());
            if (order != null && StringUtils.hasText(order.getTable_number())) {
                g.tables.add(order.getTable_number().trim());
            }
            int wait = (int) ((t.getCreated_at() != null ? now - t.getCreated_at().getTime() : 0) / 1000);
            if (wait > g.waitSeconds) {
                g.waitSeconds = wait;
            }
        }
        List<Map<String, Object>> rows = new ArrayList<>();
        for (CookingGroup g : groups.values()) {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("dish_name", g.dishName);
            row.put("unit", g.unit != null ? g.unit : "串");
            row.put("quantity", g.quantity);
            row.put("detail_ids", g.detailIds);
            row.put("table_numbers", String.join(",", g.tables));
            row.put("wait_seconds", g.waitSeconds);
            rows.add(row);
        }
        return rows;
    }

    private static Map<String, Object> slotRow(int slotIndex, int dishId, String name, String unit, int quantity,
                                               boolean overdue) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("slot_index", slotIndex);
        row.put("dish_id", dishId);
        row.put("dish_name", name);
        row.put("unit", unit != null ? unit : "串");
        row.put("quantity", quantity);
        int pending = quantity > 0 ? 1 : 0;
        row.put("has_pending", pending);
        row.put("clickable", pending);
        row.put("overdue_flag", overdue && pending == 1);
        return row;
    }

    private static boolean isOverduePending(KdsTicket t, long now, int slaSeconds) {
        if (t.getItem_status() == null || t.getItem_status() != KdsItemStatus.PENDING) {
            return false;
        }
        if (t.getOverdue_flag() != null && t.getOverdue_flag() == 1) {
            return true;
        }
        long waitMs = t.getCreated_at() != null ? now - t.getCreated_at().getTime() : 0;
        return (int) (waitMs / 1000) > slaSeconds;
    }

    private static Map<String, Object> toItemRow(KdsTicket t, OrderDetail detail, long now, int slaSeconds) {
        Map<String, Object> item = new LinkedHashMap<>();
        item.put("ticket_id", t.getId());
        item.put("detail_id", t.getDetail_id());
        item.put("item_status", t.getItem_status());
        if (detail != null) {
            item.put("name", detail.getName());
            item.put("quantity", detail.getQuantity());
            item.put("unit", detail.getUnit());
            item.put("selectedSpicy", detail.getSelectedSpicy());
            item.put("remark", detail.getRemark());
        }
        long waitMs = t.getCreated_at() != null ? now - t.getCreated_at().getTime() : 0;
        int waitSeconds = (int) (waitMs / 1000);
        item.put("wait_seconds", waitSeconds);
        item.put("serving_duration_minutes", slaSeconds / 60);
        item.put("rush_flag", t.getRush_flag() != null ? t.getRush_flag() : 0);
        item.put("add_dish_flag", t.getAdd_dish_flag() != null ? t.getAdd_dish_flag() : 0);
        item.put("overdue_flag", isOverduePending(t, now, slaSeconds));
        return item;
    }

    private static Comparator<Map<String, Object>> tableQueueComparator() {
        return Comparator
                .comparing((Map<String, Object> c) -> -(Integer) c.getOrDefault("rush_flag", 0))
                .thenComparing(c -> -(((Boolean) c.getOrDefault("overdue_flag", false)) ? 1 : 0))
                .thenComparing(c -> tableSortKey(String.valueOf(c.get("table_number"))))
                .thenComparing(c -> String.valueOf(c.get("order_no")));
    }

    private static String tableSortKey(String table) {
        if (table == null) {
            return "zzz";
        }
        String digits = table.replaceAll("\\D+", "");
        if (!digits.isEmpty()) {
            try {
                return String.format("%010d", Integer.parseInt(digits));
            } catch (NumberFormatException ignore) {
                // fall through
            }
        }
        return table;
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

    public static boolean isGrillScreen(String screenTag) {
        return KdsScreenTag.MEAT_GRILL.equals(screenTag)
                || KdsScreenTag.VEG_GRILL.equals(screenTag)
                || KdsScreenTag.SEAFOOD_SPECIAL.equals(screenTag);
    }

    private static final class BoardContext {
        final List<KdsTicket> tickets;
        final Map<Integer, Order> orderMap;
        final Map<Integer, OrderDetail> detailMap;

        BoardContext(List<KdsTicket> tickets, Map<Integer, Order> orderMap, Map<Integer, OrderDetail> detailMap) {
            this.tickets = tickets;
            this.orderMap = orderMap;
            this.detailMap = detailMap;
        }
    }

    private static final class CookingGroup {
        final String dishName;
        final String unit;
        int quantity;
        int waitSeconds;
        final List<Integer> detailIds = new ArrayList<>();
        final Set<String> tables = new LinkedHashSet<>();

        CookingGroup(String dishName, String unit) {
            this.dishName = dishName;
            this.unit = unit;
        }
    }

    private static final class SlotDef {
        final String name;
        final String unit;
        final int sortKey;
        final int dishId;

        SlotDef(String name, String unit, int sortKey, int dishId) {
            this.name = name;
            this.unit = unit;
            this.sortKey = sortKey;
            this.dishId = dishId;
        }
    }
}

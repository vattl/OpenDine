package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Dish;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.Shop;
import com.lanf.kds.KdsBoardMergeRules;
import com.lanf.kds.KdsFlowBatchStatus;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.KdsWorkflowQueue;
import com.lanf.kds.support.KdsSpecNormalizer;
import com.lanf.kds.support.KdsTicketQuantityUtil;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.service.IDishService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.util.ShopBusinessWindowResolver;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.util.*;
import java.util.stream.Collectors;

/**
 * 收银总览屏：跨荤/素/海鲜烤制岗汇总，支持队列/就餐方式/视图与特殊筛选。
 */
@Service
public class KdsOverviewBoardService {

    public static final String QUEUE_PENDING = "pending";
    /** 统一工作流：待配菜（skewer_picked=0） */
    public static final String QUEUE_PENDING_PREP = "pending_prep";
    /** 统一工作流：待制作，仅包含已配菜/已抓串的待制作工单 */
    public static final String QUEUE_PENDING_COOK = "pending_cook";
    /** 仅制作中 item_status=1 */
    public static final String QUEUE_COOKING = "cooking";
    public static final String QUEUE_READY_SERVE = "ready_serve";
    public static final String QUEUE_DONE = "done";

    public static final String VIEW_DISH = "dish";
    public static final String VIEW_ORDER = "order";
    public static final String VIEW_TABLE = "table";

    @Autowired
    private KdsTicketMapper ticketMapper;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private KdsConfigService configService;
    @Autowired
    private IDishService dishService;
    @Autowired
    private KdsFlowBatchService flowBatchService;
    @Autowired
    private KdsDishServingDurationService servingDurationService;
    @Autowired(required = false)
    private IShopService shopService;

    /**
     * 计算当前门店当前活动营业班次的起始时间（[当前班次起始日 settle_time]）。
     * 若未配置 settle_time 或异常，兜底为 24 小时前。
     */
    public Date businessDayStart(int shopId) {
        if (shopId <= 0 || shopService == null) {
            return new Date(System.currentTimeMillis() - 24L * 3600 * 1000);
        }
        try {
            Shop shop = shopService.getById(shopId);
            if (shop != null && StringUtils.hasText(shop.getSettle_time())) {
                return ShopBusinessWindowResolver.operationalWindow(shop)[0];
            }
        } catch (Exception ignore) {
        }
        return new Date(System.currentTimeMillis() - 24L * 3600 * 1000);
    }

    public Map<String, Object> buildBoard(int shopId, String queue, String dining, String view, String extraRaw) {
        return buildBoard(shopId, queue, dining, view, extraRaw, null, KdsBoardMergeRules.none(), null);
    }

    public Map<String, Object> buildBoard(int shopId, String queue, String dining, String view, String extraRaw,
                                          String keyword) {
        return buildBoard(shopId, queue, dining, view, extraRaw, keyword, KdsBoardMergeRules.none(), null);
    }

    public Map<String, Object> buildBoard(int shopId, String queue, String dining, String view, String extraRaw,
                                          String keyword, KdsBoardMergeRules mergeRules) {
        return buildBoard(shopId, queue, dining, view, extraRaw, keyword, mergeRules, null);
    }

    /**
     * 统一看板构建（D026）：screenTags 为设备可见烤制岗，null/空 = 默认三岗全选。
     * 旧屏（expedition/overview）等无设备上下文的调用方传 null 保持全量。
     */
    public Map<String, Object> buildBoard(int shopId, String queue, String dining, String view, String extraRaw,
                                          String keyword, KdsBoardMergeRules mergeRules, Set<String> screenTags) {
        String q = normalizeQueue(queue);
        String d = normalizeDining(dining);
        String v = normalizeView(view);
        Set<String> extras = parseExtras(extraRaw);
        String kw = keyword != null ? keyword.trim() : "";
        KdsBoardMergeRules rules = mergeRules != null ? mergeRules : KdsBoardMergeRules.none();

        List<EnrichedItem> items = collectItems(shopId, q, d, extras, kw, screenTags);
        if (items.isEmpty()) {
            return emptyBoard(q, d, v, extras);
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("screen_tag", KdsScreenTag.BOSS_OVERVIEW);
        result.put("queue", q);
        result.put("dining", d);
        result.put("view", v);
        result.put("extra", new ArrayList<>(extras));
        result.put("summary", buildSummary(items, q));
        result.put("dining_counts", buildDiningCounts(items, q));
        result.put("extra_counts", buildExtraCounts(items));
        result.put("merge_rules", rules.toList());
        result.put("split_pack_takeout", rules.isSplitPackTakeout() ? 1 : 0);
        if (VIEW_DISH.equals(v)) {
            result.put("dish_groups", buildDishGroups(items, q, rules));
            result.put("order_cards", buildRemarkOrderCards(items));
        } else {
            List<EnrichedItem> orderViewItems = collectOrderViewItems(shopId, q, d, extras, kw, screenTags);
            result.put("dish_groups", Collections.emptyList());
            result.put("order_cards", buildOrderCards(orderViewItems, VIEW_TABLE.equals(v), q));
            items = orderViewItems;
        }
        return result;
    }

    /**
     * 工作流 Tab 角标：与 {@link #collectItems} 相同筛选（dining/extra/keyword），按队列汇总可见份数。
     */
    public Map<String, Integer> countWorkflowQueues(int shopId, String dining, String extraRaw, String keyword) {
        return countWorkflowQueues(shopId, dining, extraRaw, keyword, null);
    }

    /** D026：screenTags 为设备可见烤制岗，null/空 = 默认三岗全选（Tab 角标与列表口径一致）。 */
    public Map<String, Integer> countWorkflowQueues(int shopId, String dining, String extraRaw, String keyword,
                                                    Set<String> screenTags) {
        String d = normalizeDining(dining);
        Set<String> extras = parseExtras(extraRaw);
        String kw = keyword != null ? keyword.trim() : "";
        Map<String, Integer> counts = new LinkedHashMap<>();
        for (String wfQueue : new String[]{
                KdsWorkflowQueue.PENDING_PREP,
                KdsWorkflowQueue.PENDING_COOK,
                KdsWorkflowQueue.READY_SERVE,
                KdsWorkflowQueue.DONE
        }) {
            String overviewQueue = KdsWorkflowQueue.toOverviewLegacyQueue(wfQueue);
            List<EnrichedItem> items = collectItems(shopId, overviewQueue, d, extras, kw, screenTags);
            int sum = items.stream().mapToInt(ei -> ei.qty).sum();
            counts.put(wfQueue, sum);
        }
        return counts;
    }

    /** view=dish 时附带整单备注，避免前端为 remark 再请求 view=order。 */
    List<Map<String, Object>> buildRemarkOrderCards(List<EnrichedItem> items) {
        Map<Integer, Map<String, Object>> byOrder = new LinkedHashMap<>();
        for (EnrichedItem ei : items) {
            if (ei.order == null || ei.order.getId() == null) {
                continue;
            }
            byOrder.computeIfAbsent(ei.order.getId(), id -> {
                Map<String, Object> card = new LinkedHashMap<>();
                card.put("order_id", ei.order.getId());
                card.put("order_no", ei.order.getOrder_no());
                card.put("table_number", ei.order.getTable_number());
                card.put("dineInOrTakeOut", ei.order.getDineInOrTakeOut());
                card.put("orderNumber", ei.order.getOrderNumber());
                card.put("remark", ei.order.getRemark());
                card.put("order_time", ei.order.getOrder_time());
                return card;
            });
        }
        return new ArrayList<>(byOrder.values());
    }

    private List<EnrichedItem> collectItems(int shopId, String q, String d, Set<String> extras, String kw,
                                            Set<String> screenTags) {
        return collectEnrichedItems(shopId, q, d, extras, kw, true, screenTags);
    }

    /**
     * 订单维度：先确定仍有本队列待操作的订单，再返回该单全部明细（含 done_line=1 的已划行）。
     */
    private List<EnrichedItem> collectOrderViewItems(int shopId, String q, String d, Set<String> extras, String kw,
                                                    Set<String> screenTags) {
        List<EnrichedItem> activeLines = collectItems(shopId, q, d, extras, kw, screenTags);
        if (activeLines.isEmpty()) {
            return Collections.emptyList();
        }
        Set<Integer> visibleOrderIds = activeLines.stream()
                .map(ei -> ei.order != null ? ei.order.getId() : null)
                .filter(Objects::nonNull)
                .collect(Collectors.toCollection(LinkedHashSet::new));

        KdsShopConfig cfg = configService.getOrDefault(shopId);
        int slaSeconds = (cfg.getSla_minutes() != null ? cfg.getSla_minutes() : 10) * 60;
        long now = System.currentTimeMillis();

        QueryWrapper<KdsTicket> qw = new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .in("order_id", visibleOrderIds)
                .in("screen_tag", effectiveScreenTags(screenTags))
                .ne("item_status", KdsItemStatus.VOID);
        qw.orderByDesc("rush_flag").orderByAsc("created_at");
        List<KdsTicket> tickets = ticketMapper.selectList(qw);
        if (tickets == null || tickets.isEmpty()) {
            return activeLines;
        }

        Set<Integer> detailIds = tickets.stream().map(KdsTicket::getDetail_id).filter(Objects::nonNull).collect(Collectors.toSet());
        Map<Integer, Order> orderMap = orderService.listByIds(visibleOrderIds).stream()
                .collect(Collectors.toMap(Order::getId, o -> o));
        Map<Integer, OrderDetail> detailMap = detailIds.isEmpty() ? Collections.emptyMap()
                : orderDetailService.listByIds(detailIds).stream().collect(Collectors.toMap(OrderDetail::getId, x -> x));
        Map<String, String> dishSpecByName = loadDishSpecifications(detailMap.values());
        Map<Integer, Integer> secondsByDetail = servingDurationService.resolveSecondsByDetails(
                detailMap.values(), slaSeconds, shopId);

        Map<Integer, KdsTicket> primaryByDetail = new LinkedHashMap<>();
        for (KdsTicket t : tickets) {
            if (t.getDetail_id() == null) {
                continue;
            }
            primaryByDetail.merge(t.getDetail_id(), t, this::pickPrimaryTicket);
        }

        List<EnrichedItem> out = new ArrayList<>();
        for (KdsTicket t : primaryByDetail.values()) {
            Order order = orderMap.get(t.getOrder_id());
            if (order == null || !matchesDining(d, order)) {
                continue;
            }
            if ("cancelled".equalsIgnoreCase(order.getTransac_status())) {
                continue;
            }
            if (!QUEUE_DONE.equals(q) && "off_order".equalsIgnoreCase(order.getOrder_receiving())) {
                continue;
            }
            OrderDetail detail = detailMap.get(t.getDetail_id());
            String dishSpec = detail != null && StringUtils.hasText(detail.getName())
                    ? dishSpecByName.get(detail.getName().trim()) : null;
            int itemSlaSeconds = KdsDishServingDurationService.secondsForDetail(
                    t.getDetail_id(), secondsByDetail, slaSeconds);
            out.add(enrich(t, order, detail, dishSpec, now, itemSlaSeconds, q));
        }
        out.sort(Comparator
                .comparingInt((EnrichedItem e) -> e.order != null && e.order.getId() != null ? e.order.getId() : 0)
                .thenComparingLong(e -> e.fifoSeq)
                .thenComparingInt(e -> e.ticket.getDetail_id() != null ? e.ticket.getDetail_id() : 0));
        return out;
    }

    private KdsTicket pickPrimaryTicket(KdsTicket a, KdsTicket b) {
        int scoreA = ticketProgressScore(a);
        int scoreB = ticketProgressScore(b);
        if (scoreA != scoreB) {
            return scoreA >= scoreB ? a : b;
        }
        Date ca = a.getCreated_at();
        Date cb = b.getCreated_at();
        if (ca != null && cb != null && !ca.equals(cb)) {
            return ca.before(cb) ? a : b;
        }
        long idA = a.getId() != null ? a.getId() : 0L;
        long idB = b.getId() != null ? b.getId() : 0L;
        return idA <= idB ? a : b;
    }

    private static int ticketProgressScore(KdsTicket t) {
        if (t == null) {
            return 0;
        }
        return KdsTicketQuantityUtil.prepQuantity(t)
                + (t.getCooked_quantity() != null ? t.getCooked_quantity() : 0)
                + KdsTicketQuantityUtil.servedQuantity(t);
    }

    private List<EnrichedItem> collectEnrichedItems(int shopId, String q, String d, Set<String> extras, String kw,
                                                    boolean requirePositiveQty, Set<String> screenTags) {
        KdsShopConfig cfg = configService.getOrDefault(shopId);
        int slaSeconds = (cfg.getSla_minutes() != null ? cfg.getSla_minutes() : 10) * 60;
        long now = System.currentTimeMillis();
        Date bizDayStart = businessDayStart(shopId);

        QueryWrapper<KdsTicket> qw = new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .in("screen_tag", effectiveScreenTags(screenTags))
                .ne("item_status", KdsItemStatus.VOID);
        applyQueueFilter(qw, q);
        if (QUEUE_DONE.equals(q)) {
            qw.ge("updated_at", bizDayStart);
        } else {
            qw.ge("created_at", bizDayStart);
        }
        qw.orderByDesc("rush_flag").orderByAsc("created_at");
        List<KdsTicket> tickets = ticketMapper.selectList(qw);
        if (tickets == null || tickets.isEmpty()) {
            return Collections.emptyList();
        }

        Set<Integer> orderIds = tickets.stream().map(KdsTicket::getOrder_id).filter(Objects::nonNull).collect(Collectors.toSet());
        Set<Integer> detailIds = tickets.stream().map(KdsTicket::getDetail_id).filter(Objects::nonNull).collect(Collectors.toSet());
        Map<Integer, Order> orderMap = orderIds.isEmpty() ? Collections.emptyMap()
                : orderService.listByIds(orderIds).stream().collect(Collectors.toMap(Order::getId, o -> o));
        Map<Integer, OrderDetail> detailMap = detailIds.isEmpty() ? Collections.emptyMap()
                : orderDetailService.listByIds(detailIds).stream().collect(Collectors.toMap(OrderDetail::getId, x -> x));
        Map<String, String> dishSpecByName = loadDishSpecifications(detailMap.values());
        Map<Integer, Integer> secondsByDetail = servingDurationService.resolveSecondsByDetails(
                detailMap.values(), slaSeconds, shopId);

        List<EnrichedItem> items = new ArrayList<>();
        for (KdsTicket t : tickets) {
            Order order = orderMap.get(t.getOrder_id());
            if (order == null) {
                continue;
            }
            if ("cancelled".equalsIgnoreCase(order.getTransac_status())) {
                continue;
            }
            if (!QUEUE_DONE.equals(q) && "off_order".equalsIgnoreCase(order.getOrder_receiving())) {
                continue;
            }
            if (!matchesDining(d, order)) {
                continue;
            }
            OrderDetail detail = detailMap.get(t.getDetail_id());
            String dishSpec = detail != null && StringUtils.hasText(detail.getName())
                    ? dishSpecByName.get(detail.getName().trim()) : null;
            int itemSlaSeconds = KdsDishServingDurationService.secondsForDetail(
                    t.getDetail_id(), secondsByDetail, slaSeconds);
            EnrichedItem ei = enrich(t, order, detail, dishSpec, now, itemSlaSeconds, q);
            if (requirePositiveQty && ei.qty <= 0) {
                continue;
            }
            if (!matchesExtras(extras, ei)) {
                continue;
            }
            if (StringUtils.hasText(kw) && !matchesKeyword(ei, kw)) {
                continue;
            }
            items.add(ei);
        }
        return items;
    }

    private static Map<String, Integer> buildDiningCounts(List<EnrichedItem> items, String queue) {
        Map<String, Integer> counts = new LinkedHashMap<>();
        counts.put("dine_in", 0);
        counts.put("pack", 0);
        counts.put("takeout", 0);
        for (EnrichedItem ei : items) {
            Map<String, Integer> one = fallbackDiningBreakdown(ei, displayQuantity(ei, queue));
            for (Map.Entry<String, Integer> e : one.entrySet()) {
                counts.put(e.getKey(), counts.getOrDefault(e.getKey(), 0) + e.getValue());
            }
        }
        return counts;
    }

    private static Map<String, Integer> buildExtraCounts(List<EnrichedItem> items) {
        Map<String, Integer> counts = new LinkedHashMap<>();
        counts.put("rush", 0);
        counts.put("overdue", 0);
        counts.put("add_dish", 0);
        counts.put("hold", 0);
        for (EnrichedItem ei : items) {
            if (ei.rush) {
                counts.merge("rush", 1, Integer::sum);
            }
            if (ei.overdue) {
                counts.merge("overdue", 1, Integer::sum);
            }
            if (ei.addDish) {
                counts.merge("add_dish", 1, Integer::sum);
            }
            if (ei.hold) {
                counts.merge("hold", 1, Integer::sum);
            }
        }
        return counts;
    }

    private Map<String, Object> emptyBoard(String q, String d, String v, Set<String> extras) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("screen_tag", KdsScreenTag.BOSS_OVERVIEW);
        result.put("queue", q);
        result.put("dining", d);
        result.put("view", v);
        result.put("extra", new ArrayList<>(extras));
        result.put("summary", summaryMap(0, 0, 0, 0));
        result.put("dining_counts", buildDiningCounts(Collections.emptyList(), q));
        result.put("extra_counts", buildExtraCounts(Collections.emptyList()));
        result.put("dish_groups", Collections.emptyList());
        result.put("order_cards", Collections.emptyList());
        return result;
    }

    /** D026：设备可见岗缺省为烤制三岗全选。 */
    private static Collection<String> effectiveScreenTags(Set<String> screenTags) {
        return screenTags != null && !screenTags.isEmpty()
                ? screenTags
                : KdsScreenTag.PRODUCTION_GRILL_TAGS;
    }

    private void applyQueueFilter(QueryWrapper<KdsTicket> qw, String queue) {
        if (QUEUE_PENDING_PREP.equals(queue) || QUEUE_PENDING.equals(queue) || QUEUE_PENDING_COOK.equals(queue)
                || QUEUE_COOKING.equals(queue)) {
            qw.in("item_status", KdsItemStatus.PENDING, KdsItemStatus.COOKING, KdsItemStatus.DONE)
                    .eq("archived", 0);
        } else if (QUEUE_READY_SERVE.equals(queue)) {
            qw.eq("archived", 0);
        } else if (QUEUE_DONE.equals(queue)) {
            qw.eq("archived", 1);
        } else {
            qw.in("item_status", KdsItemStatus.PENDING, KdsItemStatus.COOKING, KdsItemStatus.DONE);
        }
    }

    private static String normalizeQueue(String queue) {
        if (queue == null || queue.trim().isEmpty()) {
            return QUEUE_PENDING;
        }
        String raw = queue.trim();
        String q = raw.toLowerCase(Locale.ROOT);
        if ("pending_prep".equals(q) || "prep".equals(q) || "待配菜".equals(raw)) {
            return QUEUE_PENDING_PREP;
        }
        if ("pending_cook".equals(q) || "cook".equals(q) || "待制作".equals(raw)) {
            return QUEUE_PENDING_COOK;
        }
        if ("cooking".equals(q) || "in_progress".equals(q) || "制作中".equals(raw)) {
            return QUEUE_COOKING;
        }
        if ("ready".equals(q) || "ready_serve".equals(q) || "serve".equals(q)) {
            return QUEUE_READY_SERVE;
        }
        if ("done".equals(q) || "completed".equals(q) || "archived".equals(q)) {
            return QUEUE_DONE;
        }
        return QUEUE_PENDING;
    }

    private static String normalizeDining(String dining) {
        if (dining == null || dining.trim().isEmpty()) {
            return "all";
        }
        String d = dining.trim().toLowerCase(Locale.ROOT);
        if ("dine_in".equals(d) || "dinein".equals(d) || "堂食".equals(dining.trim())) {
            return "dine_in";
        }
        if ("takeout".equals(d) || "waimai".equals(d) || "外卖".equals(dining.trim())) {
            return "takeout";
        }
        if ("pack".equals(d) || "打包".equals(dining.trim())) {
            return "pack";
        }
        return "all";
    }

    private static String normalizeView(String view) {
        if (view == null || view.trim().isEmpty()) {
            return VIEW_DISH;
        }
        String v = view.trim().toLowerCase(Locale.ROOT);
        if ("order".equals(v) || "orders".equals(v)) {
            return VIEW_ORDER;
        }
        if ("table".equals(v) || "tables".equals(v)) {
            return VIEW_TABLE;
        }
        return VIEW_DISH;
    }

    private static Set<String> parseExtras(String extraRaw) {
        if (!StringUtils.hasText(extraRaw)) {
            return Collections.emptySet();
        }
        Set<String> set = new LinkedHashSet<>();
        for (String part : extraRaw.split("[,;\\s]+")) {
            if (!StringUtils.hasText(part)) {
                continue;
            }
            String p = part.trim().toLowerCase(Locale.ROOT);
            if ("overdue".equals(p) || "timeout".equals(p) || "超时".equals(part.trim())) {
                set.add("overdue");
            } else if ("rush".equals(p) || "催菜".equals(part.trim())) {
                set.add("rush");
            } else if ("add_dish".equals(p) || "add".equals(p) || "加菜".equals(part.trim())) {
                set.add("add_dish");
            } else if ("hold".equals(p) || "wait_call".equals(p) || "等叫".equals(part.trim())) {
                set.add("hold");
            }
        }
        return set;
    }

    private static boolean matchesKeyword(EnrichedItem ei, String kw) {
        if (ei.dishName != null && ei.dishName.contains(kw)) {
            return true;
        }
        if (ei.order != null) {
            if (ei.order.getTable_number() != null && ei.order.getTable_number().contains(kw)) {
                return true;
            }
            if (ei.order.getOrder_no() != null && ei.order.getOrder_no().contains(kw)) {
                return true;
            }
        }
        if (ei.ticket.getOrder_no() != null && ei.ticket.getOrder_no().contains(kw)) {
            return true;
        }
        return false;
    }

    private static boolean matchesDining(String dining, Order order) {
        if ("all".equals(dining)) {
            return true;
        }
        String t = order.getDineInOrTakeOut();
        if (t == null) {
            return false;
        }
        t = t.trim();
        if ("dine_in".equals(dining)) {
            return "堂食".equals(t);
        }
        if ("takeout".equals(dining)) {
            return "外卖".equals(t);
        }
        if ("pack".equals(dining)) {
            return "打包".equals(t);
        }
        return true;
    }

    private static boolean matchesExtras(Set<String> extras, EnrichedItem ei) {
        if (extras.isEmpty()) {
            return true;
        }
        for (String e : extras) {
            switch (e) {
                case "overdue":
                    if (!ei.overdue) {
                        return false;
                    }
                    break;
                case "rush":
                    if (!ei.rush) {
                        return false;
                    }
                    break;
                case "add_dish":
                    if (!ei.addDish) {
                        return false;
                    }
                    break;
                case "hold":
                    if (!ei.hold) {
                        return false;
                    }
                    break;
                default:
                    break;
            }
        }
        return true;
    }

    private Map<String, String> loadDishSpecifications(Collection<OrderDetail> details) {
        if (details == null || details.isEmpty()) {
            return Collections.emptyMap();
        }
        Set<String> names = details.stream()
                .map(OrderDetail::getName)
                .filter(StringUtils::hasText)
                .map(String::trim)
                .collect(Collectors.toSet());
        if (names.isEmpty()) {
            return Collections.emptyMap();
        }
        List<Dish> dishes = dishService.list(new QueryWrapper<Dish>().in("name", names));
        if (dishes == null || dishes.isEmpty()) {
            return Collections.emptyMap();
        }
        Map<String, String> out = new HashMap<>();
        for (Dish dish : dishes) {
            if (dish == null || !StringUtils.hasText(dish.getName())) {
                continue;
            }
            out.putIfAbsent(dish.getName().trim(), dish.getSpecification());
        }
        return out;
    }

    private EnrichedItem enrich(KdsTicket t, Order order, OrderDetail detail, String dishSpecification,
                                long now, int servingDurationSeconds, String queue) {
        EnrichedItem ei = new EnrichedItem();
        ei.ticket = t;
        ei.order = order;
        ei.detail = detail;
        ei.workflowQueue = workflowQueueForResponse(queue);
        int status = t.getItem_status() != null ? t.getItem_status() : KdsItemStatus.PENDING;
        long waitMs = t.getCreated_at() != null ? now - t.getCreated_at().getTime() : 0;
        ei.waitSeconds = (int) (waitMs / 1000);
        ei.servingDurationMinutes = servingDurationSeconds / 60;
        boolean pendingLike = status == KdsItemStatus.PENDING
                || QUEUE_READY_SERVE.equals(queue);
        ei.overdue = t.getOverdue_flag() != null && t.getOverdue_flag() == 1 && pendingLike;
        if (!ei.overdue) {
            ei.overdue = status == KdsItemStatus.PENDING && ei.waitSeconds > servingDurationSeconds;
        }
        ei.rush = t.getRush_flag() != null && t.getRush_flag() == 1;
        ei.addDish = KdsTicketFlagService.resolveAddDishFlag(t, order, detail);
        ei.hold = isHold(detail);
        ei.lineQty = KdsTicketQuantityUtil.lineQuantity(detail != null ? detail.getQuantity() : null);
        ei.qty = resolveQueueQuantity(t, order, ei.lineQty, queue);
        refreshQuantityFields(ei, t, ei.lineQty);
        ei.dishName = detail != null && StringUtils.hasText(detail.getName()) ? detail.getName().trim() : "?";
        String selected = detail != null ? detail.getSelectedSpicy() : null;
        KdsSpecNormalizer.SpecTastePair specTaste = KdsSpecNormalizer.splitSpecAndTaste(selected, dishSpecification);
        ei.specNorm = specTaste.getSpecNorm();
        ei.tasteNorm = specTaste.getTasteNorm();
        ei.unit = detail != null ? detail.getUnit() : null;
        ei.doneAt = t.getDone_at();
        ei.fifoSeq = queueEnterEpoch(t, queue);
        ei.orderRound = orderRound(ei);
        return ei;
    }

    private int resolveQueueQuantity(KdsTicket ticket, Order order, int lineQty, String queue) {
        if (ticket != null && ticket.getId() != null) {
            flowBatchService.ensureInitialized(ticket, lineQty);
            int batchQty = flowBatchService.queueBatchQuantity(ticket.getId(), queueToBatchStatus(queue));
            if (batchQty >= 0) {
                KdsTicket refreshed = ticketMapper.selectById(ticket.getId());
                if (refreshed != null) {
                    ticket.setPrep_quantity(refreshed.getPrep_quantity());
                    ticket.setCooked_quantity(refreshed.getCooked_quantity());
                    ticket.setServed_quantity(refreshed.getServed_quantity());
                    ticket.setSkewer_picked(refreshed.getSkewer_picked());
                    ticket.setSkewer_picked_at(refreshed.getSkewer_picked_at());
                    ticket.setArchived(refreshed.getArchived());
                    ticket.setItem_status(refreshed.getItem_status());
                }
                return batchQty;
            }
        }
        return KdsTicketQuantityUtil.displayQuantity(ticket, lineQty, queue);
    }

    private static void refreshQuantityFields(EnrichedItem ei, KdsTicket t, int lineQty) {
        ei.prepQty = KdsTicketQuantityUtil.prepQuantity(t);
        ei.cookedQty = KdsTicketQuantityUtil.cookedQuantity(t, lineQty);
        ei.servedQty = KdsTicketQuantityUtil.servedQuantity(t);
        ei.prepRemaining = KdsTicketQuantityUtil.prepRemaining(t, lineQty);
        ei.cookRemaining = KdsTicketQuantityUtil.cookRemaining(t, lineQty);
        ei.remainingQty = KdsTicketQuantityUtil.serveRemaining(t, lineQty);
    }

    private static int displayQuantity(EnrichedItem ei, String queue) {
        return ei.qty;
    }

    private static boolean isHold(OrderDetail detail) {
        if (detail == null) {
            return false;
        }
        String r = detail.getOrder_rece();
        if (r == null || r.trim().isEmpty()) {
            return true;
        }
        return "mis_order".equals(r.trim());
    }

    private static int parseQty(String quantity) {
        if (!StringUtils.hasText(quantity)) {
            return 1;
        }
        try {
            double d = Double.parseDouble(quantity.trim());
            return Math.max(1, (int) Math.round(d));
        } catch (NumberFormatException e) {
            return 1;
        }
    }

    private Map<String, Object> buildSummary(List<EnrichedItem> items, String queue) {
        Set<Integer> orderIds = new HashSet<>();
        int dishQty = 0;
        int rush = 0;
        int overdue = 0;
        for (EnrichedItem ei : items) {
            if (ei.order != null && ei.order.getId() != null) {
                orderIds.add(ei.order.getId());
            }
            dishQty += displayQuantity(ei, queue);
            if (ei.rush) {
                rush++;
            }
            if (ei.overdue) {
                overdue++;
            }
        }
        return summaryMap(items.size(), orderIds.size(), dishQty, rush, overdue);
    }

    private static Map<String, Object> summaryMap(int ticketCount, int orderCount, int dishQty, int rushCount) {
        return summaryMap(ticketCount, orderCount, dishQty, rushCount, 0);
    }

    private static Map<String, Object> summaryMap(int ticketCount, int orderCount, int dishQty,
                                                 int rushCount, int overdueCount) {
        Map<String, Object> s = new LinkedHashMap<>();
        s.put("ticket_count", ticketCount);
        s.put("order_count", orderCount);
        s.put("dish_quantity", dishQty);
        s.put("rush_count", rushCount);
        s.put("overdue_count", overdueCount);
        return s;
    }

    private List<Map<String, Object>> buildDishGroups(List<EnrichedItem> items, String queue, KdsBoardMergeRules rules) {
        Map<String, List<EnrichedItem>> byKey = new LinkedHashMap<>();
        for (EnrichedItem ei : items) {
            if (ei.qty <= 0) {
                continue;
            }
            String key = buildDisplayGroupKey(ei, queue, rules);
            byKey.computeIfAbsent(key, k -> new ArrayList<>()).add(ei);
        }
        List<Map<String, Object>> groups = new ArrayList<>();
        for (Map.Entry<String, List<EnrichedItem>> entry : byKey.entrySet()) {
            List<EnrichedItem> group = entry.getValue();
            sortItemsFifo(group);
            EnrichedItem first = group.get(0);
            int totalQty = group.stream().mapToInt(e -> displayQuantity(e, queue)).sum();
            int pendingQty = group.stream().filter(e -> e.ticket.getItem_status() != null
                    && e.ticket.getItem_status() == KdsItemStatus.PENDING).mapToInt(e -> e.qty).sum();
            int cookingQty = group.stream().filter(e -> e.ticket.getItem_status() != null
                    && e.ticket.getItem_status() == KdsItemStatus.COOKING).mapToInt(e -> e.qty).sum();
            boolean rush = group.stream().anyMatch(e -> e.rush);
            boolean overdue = group.stream().anyMatch(e -> e.overdue);
            Map<String, Object> g = new LinkedHashMap<>();
            g.put("merge_group_key", entry.getKey());
            g.put("fifo_seq", group.stream().mapToLong(e -> e.fifoSeq).min().orElse(0L));
            g.put("dish_name", first.dishName);
            g.put("spec_norm", first.specNorm);
            g.put("taste_norm", first.tasteNorm);
            g.put("workflow_queue", first.workflowQueue);
            g.put("screen_tag", first.ticket.getScreen_tag());
            g.put("quantity", totalQty);
            g.put("total_quantity", totalQty);
            g.put("line_quantity", group.stream().mapToInt(e -> e.lineQty).sum());
            g.put("prep_quantity", group.stream().mapToInt(e -> e.prepQty).sum());
            g.put("cooked_quantity", group.stream().mapToInt(e -> e.cookedQty).sum());
            g.put("served_quantity", group.stream().mapToInt(e -> e.servedQty).sum());
            g.put("prep_remaining", group.stream().mapToInt(e -> e.prepRemaining).sum());
            g.put("cook_remaining", group.stream().mapToInt(e -> e.cookRemaining).sum());
            g.put("remaining_quantity", group.stream().mapToInt(e -> e.remainingQty).sum());
            g.put("pending_quantity", pendingQty);
            g.put("cooking_quantity", cookingQty);
            g.put("clickable", totalQty > 0 ? 1 : 0);
            if (QUEUE_READY_SERVE.equals(queue)) {
                g.put("serve_clickable", totalQty > 0 ? 1 : 0);
            }
            g.put("unit", first.unit);
            g.put("order_count", (int) group.stream().map(e -> e.order != null ? e.order.getId() : null)
                    .filter(Objects::nonNull).distinct().count());
            g.put("rush_flag", rush ? 1 : 0);
            g.put("overdue_flag", overdue);
            g.put("add_dish_flag", group.stream().anyMatch(e -> e.addDish) ? 1 : 0);
            g.put("hold_flag", group.stream().anyMatch(e -> e.hold) ? 1 : 0);
            g.put("pack_flag", group.stream().anyMatch(e -> packFlag(e.order) == 1) ? 1 : 0);
            g.put("takeout_flag", group.stream().anyMatch(e -> takeoutFlag(e.order) == 1) ? 1 : 0);
            g.put("combo_flag", group.stream().anyMatch(e -> comboFlag(e.detail) == 1) ? 1 : 0);
            Map<String, Integer> diningBd = aggregateDiningBreakdown(group, queue, totalQty);
            g.put("dining_breakdown", diningBd);
            g.put("dining_breakdown_text", diningBreakdownText(diningBd));
            g.put("first_order_time", earliestOrderTime(group));
            g.put("max_wait_seconds", group.stream().mapToInt(e -> e.waitSeconds).max().orElse(0));
            g.put("ticket_count", group.size());
            g.put("detail_ids", group.stream().map(e -> e.ticket.getDetail_id())
                    .filter(Objects::nonNull).collect(Collectors.toList()));
            g.put("target_screens", group.stream().map(e -> e.ticket.getScreen_tag())
                    .filter(StringUtils::hasText).distinct().collect(Collectors.toList()));
            g.put("lines", group.stream().map(ei -> toLineMap(ei, queue, entry.getKey())).collect(Collectors.toList()));
            groups.add(g);
        }
        groups.sort(Comparator
                .comparingLong((Map<String, Object> g) -> g.get("fifo_seq") instanceof Number
                        ? ((Number) g.get("fifo_seq")).longValue() : 0L)
                .thenComparing(g -> String.valueOf(g.get("dish_name")))
                .thenComparing(g -> String.valueOf(g.get("merge_group_key"))));
        return groups;
    }

    /**
     * 展示分组键。美团模式：同屏 + 菜名 + 规格 + 口味（+ 渠道拆行 / 套餐拆行）跨订单合并；
     * 关闭合并时按明细一行（一桌一行）。
     */
    private static String buildDisplayGroupKey(EnrichedItem ei, String queue, KdsBoardMergeRules rules) {
        if (rules.hasDish() && rules.isCrossOrder()) {
            return buildMeituanCrossOrderKey(ei, rules);
        }
        StringBuilder k = new StringBuilder();
        int orderId = ei.order != null && ei.order.getId() != null ? ei.order.getId() : 0;
        appendLegacyFifoBatchPrefix(k, ei, queue, rules, orderId);
        if (rules.hasDish()) {
            k.append(":D:").append(ei.dishName).append(':').append(ei.specNorm).append(':').append(ei.tasteNorm);
            if (rules.isTagSplitOnMerge()) {
                appendTagSplitSuffix(k, ei);
            }
            appendLegacyDiningSplitSuffix(k, ei, rules);
        } else {
            k.append(":L:").append(ei.ticket.getDetail_id() != null ? ei.ticket.getDetail_id() : 0);
            if (rules.hasTags()) {
                appendTagSplitSuffix(k, ei);
            }
            if (rules.hasDining()) {
                k.append(":DN:").append(diningNorm(ei.order));
            }
        }
        return k.toString();
    }

    /** 美团：跨订单/跨桌，同烤制屏内四要素合并。 */
    private static String buildMeituanCrossOrderKey(EnrichedItem ei, KdsBoardMergeRules rules) {
        StringBuilder k = new StringBuilder();
        String screen = ei.ticket.getScreen_tag() != null ? ei.ticket.getScreen_tag() : "";
        k.append(":S:").append(screen);
        k.append(":D:").append(ei.dishName).append(':').append(ei.specNorm).append(':').append(ei.tasteNorm);
        if (rules.isSplitPackTakeout() || rules.hasDining()) {
            k.append(":DN:").append(diningNorm(ei.order));
        }
        if (!rules.isComboMerge()) {
            k.append(":C:").append(comboFlag(ei.detail));
        }
        return k.toString();
    }

    /**
     * 旧版按单合并：订单+轮次+入队时刻 FIFO 前缀。
     */
    private static void appendLegacyFifoBatchPrefix(StringBuilder k, EnrichedItem ei, String queue,
                                                    KdsBoardMergeRules rules, int orderId) {
        if (rules.hasDish() && rules.isSplitPackTakeout() && isDineIn(ei.order)) {
            k.append(orderId).append(":DI");
            return;
        }
        k.append(orderId).append(':').append(ei.orderRound).append(':').append(queueEnterEpoch(ei.ticket, queue));
    }

    private static void appendLegacyDiningSplitSuffix(StringBuilder k, EnrichedItem ei, KdsBoardMergeRules rules) {
        if (rules.isSplitPackTakeout()) {
            String dn = diningNorm(ei.order);
            if ("pack".equals(dn) || "takeout".equals(dn)) {
                k.append(":DN:").append(dn);
            }
            return;
        }
        if (rules.hasDining()) {
            k.append(":DN:").append(diningNorm(ei.order));
        }
    }

    private static boolean isDineIn(Order order) {
        if (order == null || order.getDineInOrTakeOut() == null) {
            return true;
        }
        return "堂食".equals(order.getDineInOrTakeOut().trim());
    }

    /** 特殊标签（催/超/等/加）按明细维度拆分展示组，避免同菜合并后标签污染其它份数。 */
    private static void appendTagSplitSuffix(StringBuilder k, EnrichedItem ei) {
        k.append(":T:r").append(ei.rush ? '1' : '0')
                .append('o').append(ei.overdue ? '1' : '0')
                .append('h').append(ei.hold ? '1' : '0')
                .append('a').append(ei.addDish ? '1' : '0');
    }

    private static void sortItemsFifo(List<EnrichedItem> items) {
        items.sort(Comparator
                .comparingLong((EnrichedItem e) -> e.fifoSeq)
                .thenComparing(e -> e.ticket.getDetail_id() != null ? e.ticket.getDetail_id() : 0));
    }

    private static long queueEnterEpoch(com.lanf.kds.entity.KdsTicket t, String queue) {
        if (t == null) {
            return 0L;
        }
        if (QUEUE_READY_SERVE.equals(queue) && t.getDone_at() != null) {
            return t.getDone_at().getTime();
        }
        if (QUEUE_PENDING_COOK.equals(queue) && t.getSkewer_picked_at() != null) {
            return t.getSkewer_picked_at().getTime();
        }
        return t.getCreated_at() != null ? t.getCreated_at().getTime() : 0L;
    }

    private static String diningNorm(Order order) {
        if (order == null || order.getDineInOrTakeOut() == null) {
            return "unknown";
        }
        String t = order.getDineInOrTakeOut().trim();
        if ("堂食".equals(t)) {
            return "dine_in";
        }
        if ("打包".equals(t)) {
            return "pack";
        }
        if ("外卖".equals(t)) {
            return "takeout";
        }
        return t.toLowerCase(Locale.ROOT);
    }

    private List<Map<String, Object>> buildOrderCards(List<EnrichedItem> items, boolean sortByTable, String queue) {
        Map<Integer, List<EnrichedItem>> byOrder = new LinkedHashMap<>();
        for (EnrichedItem ei : items) {
            if (ei.order == null || ei.order.getId() == null) {
                continue;
            }
            byOrder.computeIfAbsent(ei.order.getId(), k -> new ArrayList<>()).add(ei);
        }
        List<Map<String, Object>> cards = new ArrayList<>();
        for (List<EnrichedItem> group : byOrder.values()) {
            Order order = group.get(0).order;
            Map<Integer, EnrichedItem> byDetail = new LinkedHashMap<>();
            for (EnrichedItem ei : group) {
                if (ei.ticket.getDetail_id() == null) {
                    continue;
                }
                byDetail.putIfAbsent(ei.ticket.getDetail_id(), ei);
            }
            List<EnrichedItem> lines = new ArrayList<>(byDetail.values());
            sortItemsFifo(lines);
            List<Map<String, Object>> lineMaps = lines.stream()
                    .map(ei -> toLineMap(ei, queue, null))
                    .collect(Collectors.toList());

            Map<String, Object> card = new LinkedHashMap<>();
            card.put("order_id", order.getId());
            card.put("order_no", order.getOrder_no());
            card.put("table_number", order.getTable_number());
            card.put("dineInOrTakeOut", order.getDineInOrTakeOut());
            card.put("orderNumber", order.getOrderNumber());
            card.put("remark", order.getRemark());
            card.put("order_time", order.getOrder_time());
            card.put("pack_flag", packFlag(order));
            card.put("takeout_flag", takeoutFlag(order));
            card.put("total_quantity", lines.stream().mapToInt(e -> e.lineQty).sum());
            card.put("remaining_quantity", lines.stream().mapToInt(e -> queueRemainingInTab(e, queue)).sum());
            card.put("served_quantity", lines.stream().mapToInt(e -> e.servedQty).sum());
            card.put("workflow_queues", Collections.singletonList(workflowQueueForResponse(queue)));
            card.put("fifo_seq", lines.stream().mapToLong(e -> e.fifoSeq).min().orElse(0L));
            card.put("items", lineMaps);
            card.put("rounds", buildOrderRounds(lines, queue));
            cards.add(card);
        }
        if (sortByTable) {
            cards.sort(Comparator
                    .comparing((Map<String, Object> c) -> c.get("table_number") == null ? "" : c.get("table_number").toString())
                    .thenComparing(c -> c.get("order_no") == null ? "" : c.get("order_no").toString()));
        } else {
            cards.sort(Comparator
                    .comparingLong((Map<String, Object> c) -> c.get("fifo_seq") instanceof Number
                            ? ((Number) c.get("fifo_seq")).longValue() : 0L)
                    .thenComparing(c -> c.get("order_time") == null ? "" : c.get("order_time").toString()));
        }
        return cards;
    }

    private List<Map<String, Object>> buildOrderRounds(List<EnrichedItem> lines, String queue) {
        Map<Integer, List<EnrichedItem>> byRound = new TreeMap<>();
        for (EnrichedItem ei : lines) {
            byRound.computeIfAbsent(ei.orderRound, r -> new ArrayList<>()).add(ei);
        }
        List<Map<String, Object>> rounds = new ArrayList<>();
        for (Map.Entry<Integer, List<EnrichedItem>> entry : byRound.entrySet()) {
            List<EnrichedItem> roundLines = entry.getValue();
            sortItemsFifo(roundLines);
            Map<String, Object> round = new LinkedHashMap<>();
            round.put("order_round", entry.getKey());
            round.put("label", "#" + entry.getKey());
            round.put("items", roundLines.stream().map(ei -> toLineMap(ei, queue, null)).collect(Collectors.toList()));
            rounds.add(round);
        }
        return rounds;
    }

    static int queueRemainingInTab(EnrichedItem ei, String queue) {
        if (QUEUE_PENDING_PREP.equals(queue)) {
            return ei.prepRemaining;
        }
        if (QUEUE_PENDING_COOK.equals(queue) || QUEUE_COOKING.equals(queue)) {
            return ei.cookRemaining;
        }
        if (QUEUE_READY_SERVE.equals(queue)) {
            return ei.remainingQty;
        }
        return ei.qty;
    }

    static int queueCompletedInTab(EnrichedItem ei, String queue) {
        if (QUEUE_PENDING_PREP.equals(queue)) {
            return ei.prepQty;
        }
        if (QUEUE_PENDING_COOK.equals(queue) || QUEUE_COOKING.equals(queue)) {
            return ei.cookedQty;
        }
        if (QUEUE_READY_SERVE.equals(queue)) {
            return ei.servedQty;
        }
        return ei.servedQty;
    }

    static boolean computeDoneLine(EnrichedItem ei, String queue) {
        if (ei == null || ei.lineQty <= 0) {
            return false;
        }
        return isDoneLineInTab(ei.lineQty, queueRemainingInTab(ei, queue), queueCompletedInTab(ei, queue));
    }

    /** 本 Tab 下行是否已全部划完：remaining=0 且 completed≥line_quantity。 */
    static boolean isDoneLineInTab(int lineQty, int tabRemaining, int tabCompleted) {
        return tabRemaining == 0 && tabCompleted >= lineQty;
    }

    private static String actionLabelForQueue(String queue) {
        if (QUEUE_PENDING_PREP.equals(queue)) {
            return "配菜完成";
        }
        if (QUEUE_PENDING_COOK.equals(queue) || QUEUE_COOKING.equals(queue)) {
            return "制作完成";
        }
        if (QUEUE_READY_SERVE.equals(queue)) {
            return "传菜";
        }
        return "完成";
    }

    private static String nextQueueAfterTab(String queue) {
        if (QUEUE_PENDING_PREP.equals(queue)) {
            return KdsWorkflowQueue.PENDING_COOK;
        }
        if (QUEUE_PENDING_COOK.equals(queue) || QUEUE_COOKING.equals(queue)) {
            return KdsWorkflowQueue.READY_SERVE;
        }
        if (QUEUE_READY_SERVE.equals(queue)) {
            return KdsWorkflowQueue.DONE;
        }
        return null;
    }

    private Map<String, Object> toLineMap(EnrichedItem ei, String queue) {
        return toLineMap(ei, queue, null);
    }

    private Map<String, Object> toLineMap(EnrichedItem ei, String queue, String mergeGroupKey) {
        Map<String, Object> line = new LinkedHashMap<>();
        line.put("ticket_id", ei.ticket.getId());
        line.put("detail_id", ei.ticket.getDetail_id());
        line.put("dish_id", ei.detail != null ? ei.detail.getDish_id() : null);
        line.put("order_id", ei.ticket.getOrder_id());
        line.put("order_no", ei.order != null ? ei.order.getOrder_no() : ei.ticket.getOrder_no());
        line.put("table_number", ei.order != null ? ei.order.getTable_number() : null);
        line.put("dineInOrTakeOut", ei.order != null ? ei.order.getDineInOrTakeOut() : null);
        line.put("screen_tag", ei.ticket.getScreen_tag());
        int st = ei.ticket.getItem_status() != null ? ei.ticket.getItem_status() : KdsItemStatus.PENDING;
        line.put("item_status", st);
        line.put("item_status_label", itemStatusLabel(st, queue));
        line.put("workflow_queue", ei.workflowQueue);
        line.put("archived", ei.ticket.getArchived());
        line.put("skewer_picked", ei.ticket.getSkewer_picked());
        line.put("name", ei.dishName);
        line.put("dish_name", ei.dishName);
        line.put("spec_norm", ei.specNorm);
        line.put("taste_norm", ei.tasteNorm);
        line.put("fifo_seq", ei.fifoSeq);
        line.put("first_order_time", ei.order != null ? ei.order.getOrder_time() : null);
        line.put("order_round", ei.orderRound);
        if (mergeGroupKey != null) {
            line.put("merge_group_key", mergeGroupKey);
        }
        int tabRemaining = queueRemainingInTab(ei, queue);
        line.put("quantity", tabRemaining);
        line.put("line_quantity", ei.lineQty);
        line.put("prep_quantity", ei.prepQty);
        line.put("cooked_quantity", ei.cookedQty);
        line.put("served_quantity", ei.servedQty);
        line.put("prep_remaining", ei.prepRemaining);
        line.put("cook_remaining", ei.cookRemaining);
        line.put("remaining_quantity", ei.remainingQty);
        boolean doneLine = computeDoneLine(ei, queue);
        line.put("done_line", doneLine ? 1 : 0);
        line.put("action_label", actionLabelForQueue(queue));
        if (!doneLine) {
            line.put("next_queue", nextQueueAfterTab(queue));
        }
        line.put("unit", ei.unit);
        line.put("done_at", ei.doneAt);
        if (ei.detail != null) {
            line.put("remark", ei.detail.getRemark());
            line.put("selectedSpicy", ei.detail.getSelectedSpicy());
            line.put("order_rece", ei.detail.getOrder_rece());
        }
        line.put("wait_seconds", ei.waitSeconds);
        line.put("serving_duration_minutes", ei.servingDurationMinutes);
        line.put("overdue_flag", ei.overdue);
        line.put("rush_flag", ei.rush ? 1 : 0);
        line.put("add_dish_flag", ei.addDish ? 1 : 0);
        line.put("hold_flag", ei.hold ? 1 : 0);
        line.put("pack_flag", packFlag(ei.order));
        line.put("takeout_flag", takeoutFlag(ei.order));
        line.put("combo_flag", comboFlag(ei.detail));
        if (ei.ticket.getId() != null) {
            line.put("flow_batches", flowBatchService.toBatchPayload(ei.ticket.getId()));
        }
        Map<String, Integer> lineBd = flowBatchService.sumDiningByStatus(
                ei.ticket.getId() != null ? ei.ticket.getId() : 0L, queueToBatchStatus(queue));
        if (lineBd.values().stream().mapToInt(Integer::intValue).sum() <= 0
                || (ei.qty > 0 && lineBd.values().stream().mapToInt(Integer::intValue).sum() != ei.qty)) {
            lineBd = fallbackDiningBreakdown(ei, ei.qty);
        }
        line.put("dining_breakdown", lineBd);
        line.put("dining_breakdown_text", diningBreakdownText(lineBd));
        return line;
    }

    private Map<String, Integer> aggregateDiningBreakdown(List<EnrichedItem> group, String queue, int totalQty) {
        Map<String, Integer> sum = new LinkedHashMap<>();
        sum.put("dine_in", 0);
        sum.put("pack", 0);
        sum.put("takeout", 0);
        String batchStatus = queueToBatchStatus(queue);
        for (EnrichedItem ei : group) {
            if (ei.ticket.getId() == null) {
                continue;
            }
            Map<String, Integer> one = flowBatchService.sumDiningByStatus(ei.ticket.getId(), batchStatus);
            for (Map.Entry<String, Integer> e : one.entrySet()) {
                sum.put(e.getKey(), sum.getOrDefault(e.getKey(), 0) + e.getValue());
            }
        }
        int bdSum = sum.values().stream().mapToInt(Integer::intValue).sum();
        if (bdSum <= 0 || (totalQty > 0 && bdSum != totalQty)) {
            sum.put("dine_in", 0);
            sum.put("pack", 0);
            sum.put("takeout", 0);
            for (EnrichedItem ei : group) {
                Map<String, Integer> fb = fallbackDiningBreakdown(ei, ei.qty);
                for (Map.Entry<String, Integer> e : fb.entrySet()) {
                    sum.put(e.getKey(), sum.getOrDefault(e.getKey(), 0) + e.getValue());
                }
            }
        }
        return sum;
    }

    private static Map<String, Integer> fallbackDiningBreakdown(EnrichedItem ei, int qty) {
        Map<String, Integer> out = new LinkedHashMap<>();
        out.put("dine_in", 0);
        out.put("pack", 0);
        out.put("takeout", 0);
        String ch = diningNorm(ei.order);
        if ("pack".equals(ch)) {
            out.put("pack", qty);
        } else if ("takeout".equals(ch)) {
            out.put("takeout", qty);
        } else {
            out.put("dine_in", qty);
        }
        return out;
    }

    private static String diningBreakdownText(Map<String, Integer> bd) {
        if (bd == null || bd.isEmpty()) {
            return "";
        }
        List<String> parts = new ArrayList<>();
        int dine = bd.getOrDefault("dine_in", 0);
        int pack = bd.getOrDefault("pack", 0);
        int takeout = bd.getOrDefault("takeout", 0);
        if (dine > 0) {
            parts.add("堂" + dine);
        }
        if (pack > 0) {
            parts.add("打包" + pack);
        }
        if (takeout > 0) {
            parts.add("外卖" + takeout);
        }
        return String.join("｜", parts);
    }

    private static String queueToBatchStatus(String queue) {
        if (QUEUE_PENDING_PREP.equals(queue) || QUEUE_PENDING.equals(queue)) {
            return KdsFlowBatchStatus.PENDING_PREP;
        }
        if (QUEUE_PENDING_COOK.equals(queue) || QUEUE_COOKING.equals(queue)) {
            return KdsFlowBatchStatus.PENDING_COOK;
        }
        if (QUEUE_READY_SERVE.equals(queue)) {
            return KdsFlowBatchStatus.READY_SERVE;
        }
        if (QUEUE_DONE.equals(queue)) {
            return KdsFlowBatchStatus.DONE;
        }
        return KdsFlowBatchStatus.PENDING_PREP;
    }

    private static String itemStatusLabel(int status, String queue) {
        if (QUEUE_PENDING_PREP.equals(queue) && status == KdsItemStatus.PENDING) {
            return "待配菜";
        }
        if (QUEUE_READY_SERVE.equals(queue)) {
            return "待传菜";
        }
        switch (status) {
            case KdsItemStatus.COOKING:
                return "制作中";
            case KdsItemStatus.DONE:
                return "已完成";
            case KdsItemStatus.VOID:
                return "已退菜";
            case KdsItemStatus.PENDING:
            default:
                return "待制作";
        }
    }

    private static String workflowQueueForResponse(String queue) {
        if (QUEUE_PENDING_PREP.equals(queue)) {
            return KdsWorkflowQueue.PENDING_PREP;
        }
        if (QUEUE_PENDING_COOK.equals(queue)) {
            return KdsWorkflowQueue.PENDING_COOK;
        }
        if (QUEUE_READY_SERVE.equals(queue)) {
            return KdsWorkflowQueue.READY_SERVE;
        }
        if (QUEUE_DONE.equals(queue)) {
            return KdsWorkflowQueue.DONE;
        }
        return queue;
    }

    private static Date earliestOrderTime(List<EnrichedItem> group) {
        return group.stream()
                .map(e -> e.order != null ? e.order.getOrder_time() : null)
                .filter(Objects::nonNull)
                .min(Date::compareTo)
                .orElse(null);
    }

    private static int orderRound(EnrichedItem ei) {
        if (ei.detail != null && ei.detail.getMorder_num() != null && ei.detail.getMorder_num() > 0) {
            return ei.detail.getMorder_num();
        }
        if (ei.ticket != null && ei.ticket.getOrder_number_snapshot() != null && ei.ticket.getOrder_number_snapshot() > 0) {
            return ei.ticket.getOrder_number_snapshot();
        }
        if (ei.order != null && ei.order.getOrderNumber() != null && ei.order.getOrderNumber() > 0) {
            return ei.order.getOrderNumber();
        }
        return 1;
    }

    private static int packFlag(Order order) {
        return order != null && "打包".equals(order.getDineInOrTakeOut()) ? 1 : 0;
    }

    private static int takeoutFlag(Order order) {
        if (order == null || order.getDineInOrTakeOut() == null) {
            return 0;
        }
        String t = order.getDineInOrTakeOut().trim();
        return "外卖".equals(t) ? 1 : 0;
    }

    private static int comboFlag(OrderDetail detail) {
        if (detail == null || detail.getLine_type() == null) {
            return 0;
        }
        String lt = detail.getLine_type().trim().toLowerCase(Locale.ROOT);
        return "combo_header".equals(lt) || "combo_component".equals(lt) ? 1 : 0;
    }

    private static final class EnrichedItem {
        KdsTicket ticket;
        Order order;
        OrderDetail detail;
        String workflowQueue;
        String dishName;
        String specNorm;
        String tasteNorm;
        String unit;
        long fifoSeq;
        int orderRound;
        int lineQty;
        int prepQty;
        int cookedQty;
        int servedQty;
        int prepRemaining;
        int cookRemaining;
        int remainingQty;
        int qty;
        Date doneAt;
        int waitSeconds;
        int servingDurationMinutes;
        boolean overdue;
        boolean rush;
        boolean addDish;
        boolean hold;
    }
}

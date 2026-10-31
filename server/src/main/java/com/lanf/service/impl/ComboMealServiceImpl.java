package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.*;
import com.lanf.mapper.ComboFixedItemMapper;
import com.lanf.mapper.ComboGroupItemMapper;
import com.lanf.mapper.ComboGroupMapper;
import com.lanf.mapper.ComboMapper;
import com.lanf.mapper.DishShopMapper;
import com.lanf.service.IComboMealService;
import com.lanf.service.IDishService;
import com.lanf.util.DishSoldOutSync;
import com.lanf.mapper.OrderDetailMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.context.request.RequestAttributes;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import javax.servlet.http.HttpServletRequest;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.stream.Collectors;

@Service
public class ComboMealServiceImpl implements IComboMealService {

    private static final double PRICE_EPS = 0.02;
    private static final TypeReference<Map<String, Object>> MAP_TYPE = new TypeReference<Map<String, Object>>() {};

    @Autowired
    private ComboMapper comboMapper;
    @Autowired
    private ComboFixedItemMapper comboFixedItemMapper;
    @Autowired
    private ComboGroupMapper comboGroupMapper;
    @Autowired
    private ComboGroupItemMapper comboGroupItemMapper;
    @Autowired
    private IDishService dishService;
    @Autowired
    private DishShopMapper dishShopMapper;
    @Autowired
    private OrderDetailMapper orderDetailMapper;
    @Autowired
    private ObjectMapper objectMapper;

    @Override
    public Combo getByDishId(int dishId) {
        return getByDishId(dishId, null);
    }

    @Override
    public Combo getByDishId(int dishId, Integer shopId) {
        if (shopId != null && shopId > 0) {
            Combo storeCombo = comboMapper.selectOne(new QueryWrapper<Combo>()
                    .eq("dish_id", dishId)
                    .eq("shop_id", shopId)
                    .last("LIMIT 1"));
            if (storeCombo != null) {
                return storeCombo;
            }
        }
        return comboMapper.selectOne(new QueryWrapper<Combo>()
                .eq("dish_id", dishId)
                .and(w -> w.eq("shop_id", 0).or().isNull("shop_id"))
                .last("LIMIT 1"));
    }

    @Override
    public Combo getById(long comboId) {
        return comboMapper.selectById(comboId);
    }

    @Override
    public Map<String, Object> buildComboMenuPayload(long comboId) {
        Combo c = comboMapper.selectById(comboId);
        if (c == null || (c.getStatus() != null && c.getStatus() == 0)) {
            return null;
        }
        Map<String, Object> root = new LinkedHashMap<>();
        root.put("comboId", c.getId());
        root.put("dishId", c.getDish_id());
        root.put("comboType", c.getCombo_type());
        root.put("status", c.getStatus());
        root.put("limitPerOrder", c.getLimit_per_order());
        root.put("limitPerUser", c.getLimit_per_user());
        root.put("limitCycle", c.getLimit_cycle());
        root.put("startTime", c.getStart_time());
        root.put("endTime", c.getEnd_time());
        root.put("availableDays", c.getAvailable_days());
        root.put("timeRangeStart", c.getTime_range_start());
        root.put("timeRangeEnd", c.getTime_range_end());
        root.put("applyDiningType", c.getApply_dining_type());
        root.put("allowCoupon", c.getAllow_coupon());
        root.put("dailyStock", c.getDaily_stock());

        List<ComboFixedItem> fixed = comboFixedItemMapper.selectList(
                new QueryWrapper<ComboFixedItem>().eq("combo_id", comboId).orderByAsc("sort_order", "id"));
        List<Map<String, Object>> fixedOut = new ArrayList<>();
        for (ComboFixedItem f : fixed) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("componentDishId", f.getComponent_dish_id());
            m.put("qtyPerCombo", f.getQty_per_combo());
            m.put("sortOrder", f.getSort_order());
            fixedOut.add(m);
        }
        root.put("fixedItems", fixedOut);

        List<ComboGroup> groups = comboGroupMapper.selectList(
                new QueryWrapper<ComboGroup>().eq("combo_id", comboId).orderByAsc("sort_order", "id"));
        List<Map<String, Object>> groupsOut = new ArrayList<>();
        for (ComboGroup g : groups) {
            Map<String, Object> gm = new LinkedHashMap<>();
            gm.put("groupKey", g.getGroup_key());
            gm.put("title", g.getTitle());
            gm.put("minPick", g.getMin_pick());
            gm.put("maxPick", g.getMax_pick());
            gm.put("sortOrder", g.getSort_order());
            List<ComboGroupItem> items = comboGroupItemMapper.selectList(
                    new QueryWrapper<ComboGroupItem>().eq("group_id", g.getId()).orderByAsc("sort_order", "id"));
            List<Map<String, Object>> itemOut = new ArrayList<>();
            for (ComboGroupItem it : items) {
                Map<String, Object> im = new LinkedHashMap<>();
                im.put("componentDishId", it.getComponent_dish_id());
                im.put("extraPrice", it.getExtra_price() != null ? it.getExtra_price().doubleValue() : 0d);
                im.put("sortOrder", it.getSort_order());
                itemOut.add(im);
            }
            gm.put("items", itemOut);
            groupsOut.add(gm);
        }
        root.put("groups", groupsOut);
        return root;
    }

    @Override
    public Map<String, Object> getCustomerComboDetail(int dishId, Integer shopId) {
        Combo c = getByDishId(dishId, shopId);
        if (c == null || c.getStatus() == null || c.getStatus() != 1) {
            return null;
        }
        Dish header = dishService.getById(dishId);
        if (header == null) {
            throw new RuntimeException("套餐头菜品不存在");
        }
        applyShopToDish(header, shopId);
        if (!header.isOnsale()) {
            throw new RuntimeException("套餐已下架");
        }
        return buildCustomerComboPayload(c.getId(), shopId);
    }

    @Override
    public Map<String, Object> buildCustomerComboPayload(long comboId, Integer shopId) {
        Combo c = comboMapper.selectById(comboId);
        if (c == null || (c.getStatus() != null && c.getStatus() == 0)) {
            return null;
        }
        Dish header = dishService.getById(c.getDish_id());
        if (header == null) {
            throw new RuntimeException("套餐头菜品不存在");
        }
        applyShopToDish(header, shopId);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("comboId", c.getId());
        out.put("dishId", c.getDish_id());
        out.put("comboType", c.getCombo_type());
        double baseUnitPrice = header.getUnitprice() != null ? header.getUnitprice().doubleValue() : 0d;
        out.put("baseUnitPrice", baseUnitPrice);
        out.put("header", toCustomerDishView(header, shopId));

        double originalPrice = 0d;

        List<Map<String, Object>> fixedOut = new ArrayList<>();
        List<ComboFixedItem> fixed = comboFixedItemMapper.selectList(
                new QueryWrapper<ComboFixedItem>().eq("combo_id", comboId).orderByAsc("sort_order", "id"));
        for (ComboFixedItem f : fixed) {
            Dish comp = dishService.getById(f.getComponent_dish_id());
            if (comp == null) {
                continue;
            }
            Map<String, Object> row = toCustomerDishView(comp, shopId);
            int q = f.getQty_per_combo() != null ? f.getQty_per_combo() : 1;
            row.put("qtyPerCombo", q);
            fixedOut.add(row);
            double compPrice = comp.getUnitprice() != null ? comp.getUnitprice().doubleValue() : 0d;
            originalPrice += compPrice * q;
        }
        out.put("fixedItems", fixedOut);

        List<Map<String, Object>> groupsOut = new ArrayList<>();
        List<ComboGroup> groups = comboGroupMapper.selectList(
                new QueryWrapper<ComboGroup>().eq("combo_id", comboId).orderByAsc("sort_order", "id"));
        for (ComboGroup g : groups) {
            Map<String, Object> gm = new LinkedHashMap<>();
            gm.put("groupKey", g.getGroup_key());
            gm.put("title", g.getTitle());
            gm.put("minPick", g.getMin_pick());
            gm.put("maxPick", g.getMax_pick());
            List<Map<String, Object>> options = new ArrayList<>();
            List<ComboGroupItem> items = comboGroupItemMapper.selectList(
                    new QueryWrapper<ComboGroupItem>().eq("group_id", g.getId()).orderByAsc("sort_order", "id"));
            double minCompPrice = 0d;
            boolean hasOpt = false;
            for (ComboGroupItem it : items) {
                Dish comp = dishService.getById(it.getComponent_dish_id());
                if (comp == null) {
                    continue;
                }
                Map<String, Object> opt = toCustomerDishView(comp, shopId);
                opt.put("extraPrice", it.getExtra_price() != null ? it.getExtra_price().doubleValue() : 0d);
                options.add(opt);
                double p = comp.getUnitprice() != null ? comp.getUnitprice().doubleValue() : 0d;
                if (!hasOpt || p < minCompPrice) {
                    minCompPrice = p;
                    hasOpt = true;
                }
            }
            int pick = g.getMin_pick() != null ? g.getMin_pick() : 1;
            originalPrice += minCompPrice * pick;
            gm.put("options", options);
            groupsOut.add(gm);
        }
        out.put("groups", groupsOut);

        originalPrice = Math.round(originalPrice * 100) / 100.0;
        double savedAmount = (originalPrice > baseUnitPrice) ? Math.round((originalPrice - baseUnitPrice) * 100) / 100.0 : 0d;
        out.put("originalPrice", originalPrice);
        out.put("savedAmount", savedAmount);
        out.put("limitPerOrder", c.getLimit_per_order());
        out.put("limitPerUser", c.getLimit_per_user());
        out.put("limitCycle", c.getLimit_cycle());
        out.put("applyDiningType", c.getApply_dining_type());
        out.put("allowCoupon", c.getAllow_coupon());
        out.put("startTime", c.getStart_time());
        out.put("endTime", c.getEnd_time());
        out.put("availableDays", c.getAvailable_days());
        out.put("timeRangeStart", c.getTime_range_start());
        out.put("timeRangeEnd", c.getTime_range_end());
        out.put("isAvailableNow", isComboAvailableNow(c));
        return out;
    }

    @Override
    public double calcComboTotalYuan(long comboId, Integer shopId, int comboQty, Map<String, List<Integer>> selections) {
        if (comboQty <= 0) {
            throw new RuntimeException("套餐份数须为正整数");
        }
        Combo comboRow = comboMapper.selectById(comboId);
        if (comboRow == null || (comboRow.getStatus() != null && comboRow.getStatus() == 0)) {
            throw new RuntimeException("套餐不存在或已停用");
        }
        Map<String, List<Integer>> sel = selections != null ? selections : Collections.emptyMap();
        validateAndFillSelections(comboRow, sel);
        return computeComboTotalYuan(comboId, shopId, comboQty, sel);
    }

    @Override
    public void saveComboDefinition(int dishId, String comboType, int status,
                                    List<Map<String, Object>> fixedItems,
                                    List<Map<String, Object>> groups) {
        saveComboDefinition(dishId, (Integer) null, comboType, status, fixedItems, groups, null);
    }

    @Override
    public void saveComboDefinition(int dishId, String comboType, int status,
                                    List<Map<String, Object>> fixedItems,
                                    List<Map<String, Object>> groups,
                                    Map<String, Object> commercialParams) {
        saveComboDefinition(dishId, (Integer) null, comboType, status, fixedItems, groups, commercialParams);
    }

    @Override
    public void saveComboDefinition(int dishId, Integer shopId, String comboType, int status,
                                    List<Map<String, Object>> fixedItems,
                                    List<Map<String, Object>> groups) {
        saveComboDefinition(dishId, shopId, comboType, status, fixedItems, groups, null);
    }

    @Override
    public void saveComboDefinition(int dishId, Integer shopId, String comboType, int status,
                                    List<Map<String, Object>> fixedItems,
                                    List<Map<String, Object>> groups,
                                    Map<String, Object> commercialParams) {
        Dish dish = dishService.getById(dishId);
        if (dish == null) {
            throw new RuntimeException("菜品不存在，无法绑定套餐");
        }
        String ct = comboType != null ? comboType.trim().toLowerCase(Locale.ROOT) : "groups";
        if (!"fixed".equals(ct) && !"groups".equals(ct)) {
            throw new RuntimeException("comboType 须为 fixed 或 groups");
        }
        int targetShopId = (shopId != null && shopId > 0) ? shopId : 0;
        Combo existing = comboMapper.selectOne(new QueryWrapper<Combo>()
                .eq("dish_id", dishId)
                .eq("shop_id", targetShopId)
                .last("LIMIT 1"));
        if (existing != null) {
            comboMapper.deleteById(existing.getId());
        }
        Combo c = new Combo();
        c.setDish_id(dishId);
        c.setShop_id(targetShopId);
        c.setCombo_type(ct);
        c.setStatus(status == 0 ? 0 : 1);
        if (commercialParams != null) {
            c.setLimit_per_order(intVal(getParam(commercialParams, "limitPerOrder", "limit_per_order")));
            c.setLimit_per_user(intVal(getParam(commercialParams, "limitPerUser", "limit_per_user")));
            Object lcycle = getParam(commercialParams, "limitCycle", "limit_cycle");
            c.setLimit_cycle(lcycle != null && StringUtils.hasText(lcycle.toString()) ? lcycle.toString().trim() : "daily");
            Object st = getParam(commercialParams, "startTime", "start_time");
            c.setStart_time(parseDate(st));
            Object et = getParam(commercialParams, "endTime", "end_time");
            c.setEnd_time(parseDate(et));
            Object ad = getParam(commercialParams, "availableDays", "available_days");
            c.setAvailable_days(ad != null && StringUtils.hasText(ad.toString()) ? ad.toString().trim() : null);
            Object trs = getParam(commercialParams, "timeRangeStart", "time_range_start");
            c.setTime_range_start(trs != null && StringUtils.hasText(trs.toString()) ? trs.toString().trim() : null);
            Object tre = getParam(commercialParams, "timeRangeEnd", "time_range_end");
            c.setTime_range_end(tre != null && StringUtils.hasText(tre.toString()) ? tre.toString().trim() : null);
            Object adt = getParam(commercialParams, "applyDiningType", "apply_dining_type");
            c.setApply_dining_type(adt != null && StringUtils.hasText(adt.toString()) ? adt.toString().trim() : "all");
            Object ac = getParam(commercialParams, "allowCoupon", "allow_coupon");
            c.setAllow_coupon(intVal(ac) != null ? intVal(ac) : 1);
            Object ds = getParam(commercialParams, "dailyStock", "daily_stock");
            c.setDaily_stock(intVal(ds));
        }
        comboMapper.insert(c);
        Long comboId = c.getId();

        if (fixedItems != null) {
            int ord = 0;
            for (Map<String, Object> row : fixedItems) {
                if (row == null) {
                    continue;
                }
                Integer cid = intVal(row.get("componentDishId"));
                if (cid == null) {
                    cid = intVal(row.get("component_dish_id"));
                }
                if (cid == null) {
                    throw new RuntimeException("固定子项缺少 componentDishId");
                }
                ComboFixedItem f = new ComboFixedItem();
                f.setCombo_id(comboId);
                f.setComponent_dish_id(cid);
                f.setQty_per_combo(intVal(row.get("qtyPerCombo")) != null ? intVal(row.get("qtyPerCombo")) : 1);
                f.setSort_order(intVal(row.get("sortOrder")) != null ? intVal(row.get("sortOrder")) : ord++);
                comboFixedItemMapper.insert(f);
            }
        }

        if (groups != null) {
            int gord = 0;
            for (Map<String, Object> gRow : groups) {
                if (gRow == null) {
                    continue;
                }
                String gk = strVal(gRow.get("groupKey"));
                if (!StringUtils.hasText(gk)) {
                    gk = strVal(gRow.get("group_key"));
                }
                if (!StringUtils.hasText(gk)) {
                    throw new RuntimeException("可选组缺少 groupKey");
                }
                ComboGroup g = new ComboGroup();
                g.setCombo_id(comboId);
                g.setGroup_key(gk.trim());
                g.setTitle(strVal(gRow.get("title")));
                g.setMin_pick(intVal(gRow.get("minPick")) != null ? intVal(gRow.get("minPick")) : 1);
                g.setMax_pick(intVal(gRow.get("maxPick")) != null ? intVal(gRow.get("maxPick")) : 1);
                g.setSort_order(intVal(gRow.get("sortOrder")) != null ? intVal(gRow.get("sortOrder")) : gord++);
                comboGroupMapper.insert(g);
                Long gid = g.getId();

                @SuppressWarnings("unchecked")
                List<Map<String, Object>> items = (List<Map<String, Object>>) gRow.get("items");
                if (items != null) {
                    int iord = 0;
                    for (Map<String, Object> itRow : items) {
                        if (itRow == null) {
                            continue;
                        }
                        Integer cid = intVal(itRow.get("componentDishId"));
                        if (cid == null) {
                            cid = intVal(itRow.get("component_dish_id"));
                        }
                        if (cid == null) {
                            throw new RuntimeException("组「" + gk + "」可选项缺少 componentDishId");
                        }
                        ComboGroupItem it = new ComboGroupItem();
                        it.setGroup_id(gid);
                        it.setComponent_dish_id(cid);
                        Object ep = itRow.get("extraPrice") != null ? itRow.get("extraPrice") : itRow.get("extra_price");
                        it.setExtra_price(toBd(ep));
                        it.setSort_order(intVal(itRow.get("sortOrder")) != null ? intVal(itRow.get("sortOrder")) : iord++);
                        comboGroupItemMapper.insert(it);
                    }
                }
            }
        }
    }

    private boolean isCashierContext(String openid) {
        if (openid != null && "cashier_system".equalsIgnoreCase(openid.trim())) {
            return true;
        }
        try {
            RequestAttributes attrs = RequestContextHolder.getRequestAttributes();
            if (attrs instanceof ServletRequestAttributes) {
                HttpServletRequest req = ((ServletRequestAttributes) attrs).getRequest();
                if (req != null) {
                    if (Boolean.TRUE.equals(req.getAttribute(com.lanf.controller.OrderController.CASHIER_QUICK_ORDER_ATTRIBUTE))) {
                        return true;
                    }
                    String uri = req.getRequestURI();
                    if (uri != null && (uri.contains("/cashier/order/") || uri.contains("/cashier/orders")
                            || uri.contains("/api/pos/orders") || uri.contains("/api/pos/"))) {
                        return true;
                    }
                }
            }
        } catch (Throwable ignored) {
        }
        return false;
    }

    @Override
    public void normalizeCartLines(List<OrderDetail> goodsList, Integer shopId) {
        normalizeCartLines(goodsList, shopId, null, null, false);
    }

    @Override
    public void normalizeCartLines(List<OrderDetail> goodsList, Integer shopId, String openid, String diningType) {
        normalizeCartLines(goodsList, shopId, openid, diningType, false);
    }

    @Override
    public void normalizeCartLines(List<OrderDetail> goodsList, Integer shopId, String openid, String diningType, boolean isCashier) {
        if (goodsList == null || goodsList.isEmpty()) {
            return;
        }
        boolean cashier = isCashier || isCashierContext(openid);
        // 1. 汇总整单中每个 comboId 的累计点选份数，统一执行风控与商业化规则校验
        Map<Long, Integer> totalQtyByCombo = new HashMap<>();
        for (OrderDetail line : goodsList) {
            if (line != null && isComboRequestLine(line) && line.getCombo_id() != null) {
                int q = parseQty(line.getQuantity());
                totalQtyByCombo.merge(line.getCombo_id(), q, Integer::sum);
            }
        }
        for (Map.Entry<Long, Integer> entry : totalQtyByCombo.entrySet()) {
            validateComboCommercialRules(entry.getKey(), shopId, entry.getValue(), openid, diningType, cashier);
        }

        List<OrderDetail> out = new ArrayList<>();
        for (OrderDetail line : goodsList) {
            if (line == null) {
                continue;
            }
            if (isComboRequestLine(line)) {
                out.addAll(expandOneComboLine(line, shopId));
            } else {
                if ("combo".equalsIgnoreCase(line.getLine_type())) {
                    line.setLine_type(null);
                }
                out.add(line);
            }
        }
        goodsList.clear();
        goodsList.addAll(out);
    }

    @Override
    public void validateComboCommercialRules(long comboId, Integer shopId, int comboQty, String openid, String diningType) {
        validateComboCommercialRules(comboId, shopId, comboQty, openid, diningType, false);
    }

    @Override
    public void validateComboCommercialRules(long comboId, Integer shopId, int comboQty, String openid, String diningType, boolean isCashier) {
        Combo c = comboMapper.selectById(comboId);
        if (c == null || (c.getStatus() != null && c.getStatus() == 0)) {
            throw new RuntimeException("套餐不存在或已停用");
        }
        if (isCashier || isCashierContext(openid)) {
            // 收银端下单/加菜免除商业化运营规则限制（限购、可用时段、可用星期、用餐方式、活动生效期等），仅保留套餐本身存在且未停用校验
            return;
        }
        Dish headerDish = dishService.getById(c.getDish_id());
        String comboName = headerDish != null ? headerDish.getName() : "套餐";

        Date now = new Date();
        // 1. 活动生效日期范围校验
        if (c.getStart_time() != null && now.before(c.getStart_time())) {
            throw new RuntimeException("套餐「" + comboName + "」活动尚未开始");
        }
        if (c.getEnd_time() != null && now.after(c.getEnd_time())) {
            throw new RuntimeException("套餐「" + comboName + "」活动已结束");
        }

        // 2. 可用星期校验（1~7，1表示周一，7表示周日）
        if (StringUtils.hasText(c.getAvailable_days())) {
            Calendar cal = Calendar.getInstance();
            cal.setTime(now);
            int dow = cal.get(Calendar.DAY_OF_WEEK);
            int currentDay = (dow == Calendar.SUNDAY) ? 7 : dow - 1;
            List<String> days = Arrays.stream(c.getAvailable_days().split(","))
                    .map(String::trim)
                    .filter(StringUtils::hasText)
                    .collect(Collectors.toList());
            if (!days.isEmpty() && !days.contains(String.valueOf(currentDay))) {
                throw new RuntimeException("套餐「" + comboName + "」今日不可售（可用星期：" + c.getAvailable_days() + "）");
            }
        }

        // 3. 每日可用时间段校验（如 11:00 ~ 14:00）
        if (StringUtils.hasText(c.getTime_range_start()) || StringUtils.hasText(c.getTime_range_end())) {
            SimpleDateFormat sdf = new SimpleDateFormat("HH:mm:ss");
            String currentTimeStr = sdf.format(now);
            if (StringUtils.hasText(c.getTime_range_start())) {
                String start = normalizeTimeString(c.getTime_range_start());
                if (currentTimeStr.compareTo(start) < 0) {
                    throw new RuntimeException("套餐「" + comboName + "」未到售卖时段（每日 " + c.getTime_range_start() + " 开始）");
                }
            }
            if (StringUtils.hasText(c.getTime_range_end())) {
                String end = normalizeTimeString(c.getTime_range_end());
                if (currentTimeStr.compareTo(end) > 0) {
                    throw new RuntimeException("套餐「" + comboName + "」已过售卖时段（每日 " + c.getTime_range_end() + " 截止）");
                }
            }
        }

        // 4. 用餐方式校验
        if (StringUtils.hasText(diningType) && StringUtils.hasText(c.getApply_dining_type()) && !"all".equalsIgnoreCase(c.getApply_dining_type().trim())) {
            String normDining = normalizeDiningType(diningType);
            String required = c.getApply_dining_type().trim().toLowerCase(Locale.ROOT);
            if (!required.equals(normDining)) {
                String reqLabel = "dine_in".equals(required) ? "堂食" : "外卖/打包";
                throw new RuntimeException("套餐「" + comboName + "」仅限" + reqLabel + "使用");
            }
        }

        // 5. 单笔订单限购校验
        if (c.getLimit_per_order() != null && c.getLimit_per_order() > 0) {
            if (comboQty > c.getLimit_per_order()) {
                throw new RuntimeException("套餐「" + comboName + "」单单限购 " + c.getLimit_per_order() + " 份");
            }
        }

        // 6. 用户周期限购校验
        if (c.getLimit_per_user() != null && c.getLimit_per_user() > 0 && StringUtils.hasText(openid)) {
            Date cycleStart = null;
            String cycle = StringUtils.hasText(c.getLimit_cycle()) ? c.getLimit_cycle().trim().toLowerCase(Locale.ROOT) : "daily";
            if ("daily".equals(cycle)) {
                Calendar cal = Calendar.getInstance();
                cal.set(Calendar.HOUR_OF_DAY, 0);
                cal.set(Calendar.MINUTE, 0);
                cal.set(Calendar.SECOND, 0);
                cal.set(Calendar.MILLISECOND, 0);
                cycleStart = cal.getTime();
            }
            Integer purchased = orderDetailMapper.sumUserPurchasedComboQty(openid.trim(), comboId, cycleStart);
            int bought = (purchased != null ? purchased : 0);
            if (bought + comboQty > c.getLimit_per_user()) {
                String cycleDesc = "lifetime".equals(cycle) ? "每人限购 " : "每日每人限购 ";
                throw new RuntimeException("套餐「" + comboName + "」" + cycleDesc + c.getLimit_per_user() + " 份（您已购买 " + bought + " 份）");
            }
        }
    }

    @Override
    public void assertHeaderPriceMatches(OrderDetail headerLine, Integer shopId) {
        if (headerLine == null || !"combo_header".equalsIgnoreCase(headerLine.getLine_type())) {
            return;
        }
        if (headerLine.getCombo_id() == null) {
            throw new RuntimeException("套餐头行缺少 combo_id");
        }
        Map<String, List<Integer>> selections = parseSelectionsJson(headerLine.getCombo_selection_json());
        int comboQty = parseQty(headerLine.getQuantity());
        double expected = computeComboTotalYuan(headerLine.getCombo_id(), shopId, comboQty, selections);
        double actual = headerLine.getTotal_price() != null ? headerLine.getTotal_price() : -1;
        if (Math.abs(actual - expected) > PRICE_EPS) {
            throw new RuntimeException("套餐「" + headerLine.getName() + "」金额与规则不符（应为 ¥"
                    + String.format(Locale.US, "%.2f", expected) + "）");
        }
    }

    private boolean isComboRequestLine(OrderDetail line) {
        if (line.getCombo_id() != null && line.getCombo_id() > 0) {
            return true;
        }
        return "combo".equalsIgnoreCase(line.getLine_type());
    }

    private List<OrderDetail> expandOneComboLine(OrderDetail req, Integer shopId) {
        if (req.getCombo_id() == null || req.getCombo_id() <= 0) {
            if (req.getDish_id() != null) {
                Combo c = getByDishId(req.getDish_id(), shopId);
                if (c != null) {
                    req.setCombo_id(c.getId());
                }
            }
        }
        if (req.getCombo_id() == null || req.getCombo_id() <= 0) {
            throw new RuntimeException("套餐行须提供 combo_id（t_combo.id）");
        }
        Combo comboRow = comboMapper.selectById(req.getCombo_id());
        if (comboRow == null || (comboRow.getStatus() != null && comboRow.getStatus() == 0)) {
            throw new RuntimeException("套餐不存在或已停用");
        }
        Dish headerDish = dishService.getById(comboRow.getDish_id());
        if (headerDish == null) {
            throw new RuntimeException("套餐头菜品不存在");
        }
        // 门店本地化：套餐头菜/子菜名称、单位、图片、分类等按门店覆盖（与 C 端菜单一致）
        applyShopToDish(headerDish, shopId);
        int comboQty = parseQty(req.getQuantity());
        if (comboQty <= 0) {
            throw new RuntimeException("套餐份数须为正整数");
        }

        Map<String, List<Integer>> selections = new LinkedHashMap<>();
        if (req.getComboSelections() != null && !req.getComboSelections().isEmpty()) {
            selections.putAll(coerceSelections(req.getComboSelections()));
        } else if (StringUtils.hasText(req.getCombo_selection_json())) {
            selections.putAll(parseSelectionsJson(req.getCombo_selection_json()));
        }

        validateAndFillSelections(comboRow, selections);

        double serverTotal = computeComboTotalYuan(comboRow.getId(), shopId, comboQty, selections);
        if (serverTotal <= 0) {
            throw new RuntimeException("套餐计算价格无效，请检查头菜单价与加价配置");
        }
        Double clientTotal = req.getTotal_price();
        if (clientTotal != null && Math.abs(clientTotal - serverTotal) > PRICE_EPS) {
            throw new RuntimeException("套餐「" + headerDish.getName() + "」金额与售价规则不符（应为 ¥"
                    + String.format(Locale.US, "%.2f", serverTotal) + "）");
        }

        String inst = UUID.randomUUID().toString().replace("-", "");
        inst = inst.length() > 36 ? inst.substring(0, 36) : inst;
        String json;
        try {
            json = objectMapper.writeValueAsString(selections);
        } catch (Exception e) {
            throw new RuntimeException("套餐选择序列化失败");
        }

        List<OrderDetail> lines = new ArrayList<>();
        OrderDetail header = new OrderDetail();
        header.setName(headerDish.getName());
        header.setQuantity(String.valueOf(comboQty));
        header.setUnit(headerDish.getUnit() != null ? headerDish.getUnit() : (StringUtils.hasText(req.getUnit()) ? req.getUnit() : "份"));
        header.setImage(headerDish.getImage());
        header.setTotal_price(Math.round(serverTotal * 100) / 100.0);
        header.setCid(headerDish.getTypeId() != null ? String.valueOf(headerDish.getTypeId()) : (StringUtils.hasText(req.getCid()) ? req.getCid() : "0"));
        header.setDish_id(headerDish.getId());
        header.setRemark(req.getRemark());
        header.setSelectedSpicy(req.getSelectedSpicy());
        header.setClient_line_id(req.getClient_line_id());
        header.setLine_type("combo_header");
        header.setCombo_id(comboRow.getId());
        header.setCombo_instance_id(inst);
        header.setParent_detail_id(null);
        header.setCombo_selection_json(json);
        lines.add(header);

        List<ComboFixedItem> fixed = comboFixedItemMapper.selectList(
                new QueryWrapper<ComboFixedItem>().eq("combo_id", comboRow.getId()).orderByAsc("sort_order", "id"));
        for (ComboFixedItem f : fixed) {
            Dish comp = dishService.getById(f.getComponent_dish_id());
            if (comp == null) {
                throw new RuntimeException("套餐固定子菜不存在，ID=" + f.getComponent_dish_id());
            }
            applyShopToDish(comp, shopId);
            int q = (f.getQty_per_combo() != null ? f.getQty_per_combo() : 1) * comboQty;
            OrderDetail component = buildComponentLine(comp, q, comboRow.getId(), inst, req.getSelectedSpicy());
            lines.add(component);
        }

        List<ComboGroup> groups = comboGroupMapper.selectList(
                new QueryWrapper<ComboGroup>().eq("combo_id", comboRow.getId()).orderByAsc("sort_order", "id"));
        for (ComboGroup g : groups) {
            List<Integer> picks = selections.getOrDefault(g.getGroup_key(), Collections.emptyList());
            for (Integer pickDishId : picks) {
                Dish comp = dishService.getById(pickDishId);
                if (comp == null) {
                    throw new RuntimeException("套餐所选子菜不存在，ID=" + pickDishId);
                }
                applyShopToDish(comp, shopId);
                int q = comboQty;
                OrderDetail component = buildComponentLine(comp, q, comboRow.getId(), inst, req.getSelectedSpicy());
                lines.add(component);
            }
        }


        return lines;
    }

    private OrderDetail buildComponentLine(Dish comp, int qty, Long comboId, String inst, String spicy) {
        OrderDetail c = new OrderDetail();
        c.setName(comp.getName());
        c.setQuantity(String.valueOf(qty));
        c.setUnit(comp.getUnit() != null ? comp.getUnit() : "份");
        c.setImage(comp.getImage());
        c.setTotal_price(0d);
        c.setCid(comp.getTypeId() != null ? String.valueOf(comp.getTypeId()) : "0");
        c.setDish_id(comp.getId());
        c.setLine_type("combo_component");
        c.setCombo_id(comboId);
        c.setCombo_instance_id(inst);
        c.setParent_detail_id(null);
        c.setCombo_selection_json(null);
        // 子菜规格（selectedSpicy）继承套餐头的规格选择，确保 KDS/打印展示一致
        c.setSelectedSpicy(spicy);
        return c;
    }

    private void validateAndFillSelections(Combo comboRow, Map<String, List<Integer>> selections) {
        List<ComboGroup> groups = comboGroupMapper.selectList(
                new QueryWrapper<ComboGroup>().eq("combo_id", comboRow.getId()).orderByAsc("sort_order", "id"));
        if ("fixed".equalsIgnoreCase(comboRow.getCombo_type())) {
            if (!groups.isEmpty()) {
                throw new RuntimeException("fixed 类型套餐不应配置可选组");
            }
            return;
        }
        for (ComboGroup g : groups) {
            List<Integer> picks = selections.getOrDefault(g.getGroup_key(), Collections.emptyList());
            int min = g.getMin_pick() != null ? g.getMin_pick() : 1;
            int max = g.getMax_pick() != null ? g.getMax_pick() : 1;
            String groupName = StringUtils.hasText(g.getTitle()) ? g.getTitle() : g.getGroup_key();
            if (picks.size() < min || picks.size() > max) {
                throw new RuntimeException("套餐组「" + groupName + "」须选 " + min + "~" + max + " 项");
            }
            List<ComboGroupItem> allowed = comboGroupItemMapper.selectList(
                    new QueryWrapper<ComboGroupItem>().eq("group_id", g.getId()));
            Set<Integer> allowIds = allowed.stream().map(ComboGroupItem::getComponent_dish_id).collect(Collectors.toSet());
            for (Integer pid : picks) {
                if (pid == null || !allowIds.contains(pid)) {
                    throw new RuntimeException("套餐组「" + groupName + "」含非法选项");
                }
            }
        }
    }

    private double computeComboTotalYuan(long comboId, Integer shopId, int comboQty, Map<String, List<Integer>> selections) {
        Combo comboRow = comboMapper.selectById(comboId);
        if (comboRow == null) {
            throw new RuntimeException("套餐不存在");
        }
        Dish headerDish = dishService.getById(comboRow.getDish_id());
        if (headerDish == null) {
            throw new RuntimeException("套餐头菜品不存在");
        }
        double base = effectiveUnitPrice(shopId, headerDish.getId(), headerDish);
        double extraPerInstance = 0d;
        List<ComboGroup> groups = comboGroupMapper.selectList(
                new QueryWrapper<ComboGroup>().eq("combo_id", comboId).orderByAsc("sort_order", "id"));
        for (ComboGroup g : groups) {
            List<Integer> picks = selections.getOrDefault(g.getGroup_key(), Collections.emptyList());
            List<ComboGroupItem> allowed = comboGroupItemMapper.selectList(
                    new QueryWrapper<ComboGroupItem>().eq("group_id", g.getId()));
            Map<Integer, BigDecimal> extraByDish = new HashMap<>();
            for (ComboGroupItem it : allowed) {
                extraByDish.put(it.getComponent_dish_id(), it.getExtra_price() != null ? it.getExtra_price() : BigDecimal.ZERO);
            }
            for (Integer pid : picks) {
                BigDecimal ep = extraByDish.getOrDefault(pid, BigDecimal.ZERO);
                extraPerInstance += ep.doubleValue();
            }
        }
        double per = base + extraPerInstance;
        return Math.round(per * comboQty * 100) / 100.0;
    }

    private Map<String, Object> toCustomerDishView(Dish d, Integer shopId) {
        if (shopId != null) {
            applyShopToDish(d, shopId);
        }
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("dishId", d.getId());
        m.put("name", d.getName());
        m.put("image", d.getImage());
        m.put("unit", d.getUnit());
        m.put("unitprice", d.getUnitprice());
        m.put("stock", d.getStock());
        m.put("onsale", d.isOnsale());
        m.put("sold_out", d.getSold_out());
        return m;
    }

    private void applyShopToDish(Dish d, Integer shopId) {
        if (d == null || d.getId() == null || shopId == null) {
            return;
        }
        DishShop link = dishShopMapper.selectOne(new QueryWrapper<DishShop>()
                .eq("shop_id", shopId)
                .eq("dish_id", d.getId())
                .last("LIMIT 1"));
        if (link == null) {
            return;
        }
        if (link.getOnsale_override() != null) {
            d.setOnsale(link.getOnsale_override() == 1);
        }
        if (link.getUnitprice() != null) {
            d.setUnitprice(link.getUnitprice().floatValue());
        }
        if (link.getStock() != null) {
            d.setStock(link.getStock());
        }
        if (link.getSold_out() != null) {
            d.setSold_out(link.getSold_out());
        } else if (link.getStock() != null) {
            DishSoldOutSync.applyFromStock(d);
        }
        // 门店本地化覆盖：名称/图片/单位/规格模板（与 C 端菜单一致，见 docs/db_migration_dish_shop_full_overrides.sql）
        if (StringUtils.hasText(link.getName_override())) {
            d.setName(link.getName_override());
        }
        if (StringUtils.hasText(link.getImage_override())) {
            d.setImage(link.getImage_override());
        }
        if (StringUtils.hasText(link.getUnit_override())) {
            d.setUnit(link.getUnit_override());
        }
        if (StringUtils.hasText(link.getSpecification_override())) {
            d.setSpecification(link.getSpecification_override());
        }
        if (link.getServing_duration_override() != null) {
            d.setServing_duration_minutes(link.getServing_duration_override());
        }
        if (link.getType_id_override() != null) {
            d.setTypeId(link.getType_id_override());
        }
    }

    private double effectiveUnitPrice(Integer shopId, Integer dishId, Dish dish) {
        if (shopId != null && dishId != null) {
            DishShop link = dishShopMapper.selectOne(new QueryWrapper<DishShop>()
                    .eq("shop_id", shopId)
                    .eq("dish_id", dishId)
                    .last("LIMIT 1"));
            if (link != null && link.getUnitprice() != null) {
                return link.getUnitprice().doubleValue();
            }
        }
        return dish.getUnitprice() != null ? dish.getUnitprice().doubleValue() : 0d;
    }

    private Map<String, List<Integer>> parseSelectionsJson(String json) {
        if (!StringUtils.hasText(json)) {
            return new LinkedHashMap<>();
        }
        try {
            Map<String, Object> raw = objectMapper.readValue(json.trim(), MAP_TYPE);
            return coerceSelections(raw);
        } catch (Exception e) {
            throw new RuntimeException("套餐选择 JSON 无效");
        }
    }

    private Map<String, List<Integer>> coerceSelections(Map<String, Object> raw) {
        Map<String, List<Integer>> out = new LinkedHashMap<>();
        if (raw == null) {
            return out;
        }
        for (Map.Entry<String, Object> e : raw.entrySet()) {
            String k = e.getKey();
            Object v = e.getValue();
            List<Integer> ids = new ArrayList<>();
            if (v instanceof List<?>) {
                for (Object o : (List<?>) v) {
                    Integer id = intVal(o);
                    if (id != null) {
                        ids.add(id);
                    }
                }
            } else {
                Integer id = intVal(v);
                if (id != null) {
                    ids.add(id);
                }
            }
            out.put(k, ids);
        }
        return out;
    }

    private static int parseQty(String quantityRaw) {
        if (!StringUtils.hasText(quantityRaw)) {
            return 1;
        }
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("(\\d+)").matcher(quantityRaw.trim());
        if (!m.find()) {
            throw new RuntimeException("套餐数量格式非法：" + quantityRaw);
        }
        int n = Integer.parseInt(m.group(1));
        if (n <= 0) {
            throw new RuntimeException("套餐份数须为正整数");
        }
        return n;
    }

    private static Integer intVal(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof Number) {
            return ((Number) o).intValue();
        }
        try {
            return Integer.parseInt(o.toString().trim());
        } catch (Exception e) {
            return null;
        }
    }

    private static String strVal(Object o) {
        return o == null ? null : o.toString();
    }

    private static BigDecimal toBd(Object o) {
        if (o == null) {
            return BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP);
        }
        if (o instanceof BigDecimal) {
            return ((BigDecimal) o).setScale(2, RoundingMode.HALF_UP);
        }
        if (o instanceof Number) {
            return BigDecimal.valueOf(((Number) o).doubleValue()).setScale(2, RoundingMode.HALF_UP);
        }
        try {
            return new BigDecimal(o.toString().trim()).setScale(2, RoundingMode.HALF_UP);
        } catch (Exception e) {
            return BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP);
        }
    }

    private static Object getParam(Map<String, Object> map, String camelKey, String snakeKey) {
        if (map == null) {
            return null;
        }
        Object val = map.get(camelKey);
        return val != null ? val : map.get(snakeKey);
    }

    private static Date parseDate(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof Date) {
            return (Date) o;
        }
        if (o instanceof Number) {
            return new Date(((Number) o).longValue());
        }
        String str = o.toString().trim();
        if (str.isEmpty()) {
            return null;
        }
        String[] patterns = new String[]{
                "yyyy-MM-dd HH:mm:ss",
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd"
        };
        for (String p : patterns) {
            try {
                return new SimpleDateFormat(p).parse(str);
            } catch (Exception ignored) {
            }
        }
        return null;
    }

    private boolean isComboAvailableNow(Combo c) {
        if (c == null || (c.getStatus() != null && c.getStatus() == 0)) {
            return false;
        }
        Date now = new Date();
        if (c.getStart_time() != null && now.before(c.getStart_time())) {
            return false;
        }
        if (c.getEnd_time() != null && now.after(c.getEnd_time())) {
            return false;
        }
        if (StringUtils.hasText(c.getAvailable_days())) {
            Calendar cal = Calendar.getInstance();
            cal.setTime(now);
            int dow = cal.get(Calendar.DAY_OF_WEEK);
            int currentDay = (dow == Calendar.SUNDAY) ? 7 : dow - 1;
            List<String> days = Arrays.stream(c.getAvailable_days().split(","))
                    .map(String::trim)
                    .filter(StringUtils::hasText)
                    .collect(Collectors.toList());
            if (!days.isEmpty() && !days.contains(String.valueOf(currentDay))) {
                return false;
            }
        }
        if (StringUtils.hasText(c.getTime_range_start()) || StringUtils.hasText(c.getTime_range_end())) {
            SimpleDateFormat sdf = new SimpleDateFormat("HH:mm:ss");
            String currentTimeStr = sdf.format(now);
            if (StringUtils.hasText(c.getTime_range_start())) {
                String start = normalizeTimeString(c.getTime_range_start());
                if (currentTimeStr.compareTo(start) < 0) {
                    return false;
                }
            }
            if (StringUtils.hasText(c.getTime_range_end())) {
                String end = normalizeTimeString(c.getTime_range_end());
                if (currentTimeStr.compareTo(end) > 0) {
                    return false;
                }
            }
        }
        return true;
    }

    private static String normalizeTimeString(String t) {
        if (!StringUtils.hasText(t)) {
            return "00:00:00";
        }
        String s = t.trim();
        if (s.length() == 5) {
            return s + ":00";
        }
        return s;
    }

    private static String normalizeDiningType(String raw) {
        if (!StringUtils.hasText(raw)) {
            return "all";
        }
        String t = raw.trim();
        if ("堂食".equals(t) || "dine_in".equalsIgnoreCase(t) || "dinein".equalsIgnoreCase(t)) {
            return "dine_in";
        }
        if ("打包".equals(t) || "外卖".equals(t) || "take_out".equalsIgnoreCase(t) || "takeout".equalsIgnoreCase(t)) {
            return "take_out";
        }
        return t.toLowerCase(Locale.ROOT);
    }
}

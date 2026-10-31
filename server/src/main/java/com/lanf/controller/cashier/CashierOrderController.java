package com.lanf.controller.cashier;
import com.lanf.audit.diff.OrderRefundDiffProvider;
import com.lanf.audit.annotation.AuditLog;
import org.springframework.util.StringUtils;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.lanf.config.ServiceFeeConfig;
import com.lanf.controller.OrderController;
import com.lanf.dto.OrderDTO;
import com.lanf.entity.*;
import com.lanf.order.OrderDetailLineStatus;
import com.lanf.order.OrderDetailQueryHelper;
import com.lanf.order.OrderRevisionService;
import com.lanf.service.IShopService;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderLogService;
import com.lanf.service.IOrderService;
import com.lanf.service.CashierCheckoutService;
import com.lanf.service.CashierClientRequestService;
import com.lanf.service.ITableService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.service.impl.OrderDetailRefundService;
import com.lanf.payment.service.WechatJsapiPaymentService;
import com.lanf.util.OrderCheckoutChangeHelper;
import com.lanf.util.OrderListTimeRangeResolver;
import com.lanf.util.OrderNetRevenue;
import com.lanf.util.OrderNumberGenerator;
import com.lanf.util.OrderPackagingFeeCalculator;
import com.lanf.util.OrderPayChannelAmounts;
import com.lanf.util.OrderManualDiscountCalculator;
import com.lanf.util.AdminShopRequest;
import com.lanf.util.AdminNameResolver;
import com.lanf.util.ShopBusinessWindowResolver;
import com.lanf.util.ShopOrderingOpenHelper;
import com.lanf.access.model.AccessDecision;
import com.lanf.access.service.HighRiskActionAuthorizationService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import com.lanf.interceptor.SysInterceptor;
import javax.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.Duration;
import java.time.ZoneId;
import java.util.*;
import java.util.function.Supplier;
import java.util.stream.Collectors;

/**
 * 收银端点餐与结账。
 */
@RestController
@RequestMapping({"/cashier/order", "/cashier/orders", "/api/pos/orders", "/api/pos"})
public class CashierOrderController {

    private static final String SENSITIVE_AUTHORIZED_ADMIN_ID =
            "com.lanf.security.sensitiveAuthorizedAdminId";

    private static final String CASHIER_OPENID = "cashier_system";
    private static final ZoneId BUSINESS_ZONE = ZoneId.of("Asia/Shanghai");
    private static final String BILL_CUSTOM_RANGE_PERMISSION = "admin:super";
    private static final int BILL_RECENT_HOURS = 3;
    private static final int BILL_CUSTOM_RANGE_MAX_DAYS = 31;

    @Autowired
    private OrderController orderController;
    @Autowired
    private CashierCheckoutService cashierCheckoutService;
    @Autowired
    private CashierClientRequestService clientRequestService;
    @Autowired
    private IShopService shopService;
    @Autowired
    private IAdminPermissionService adminPermissionService;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private ITableService tableService;
    @Autowired
    private IOrderLogService orderLogService;
    @Autowired
    private ServiceFeeConfig serviceFeeConfig;
    @Autowired
    private OrderDetailRefundService orderDetailRefundService;
    @Autowired
    private WechatJsapiPaymentService wechatJsapiPaymentService;
    @Autowired
    private ITakeoutDeliveryService takeoutDeliveryService;
    @Autowired
    private HttpServletRequest request;
    @Autowired
    private com.lanf.service.IDishService dishService;
    @Autowired
    private HighRiskActionAuthorizationService highRiskActionAuthorizationService;
    @Autowired
    private OrderRevisionService orderRevisionService;
    @Autowired(required = false)
    private com.lanf.mapper.DailyCloseSnapshotMapper dailyCloseSnapshotMapper;
    @Autowired(required = false)
    private com.lanf.service.IDailyStatService dailyStatService;
    @Autowired(required = false)
    private com.lanf.realtime.CashierEventWebSocketHub cashierEventWebSocketHub;
    @Autowired(required = false)
    private com.lanf.mapper.SystemConfigMapper systemConfigMapper;
    @Autowired(required = false)
    private com.lanf.service.IAdminService adminService;

    @PostMapping("/quickOrder")
    @AuditLog(module = "cashier", action = "cashier_order_create", target = "#p0['orderNo'] ?: #p0['order_no']")
    public R quickOrder(@RequestBody Map<String, Object> body) {
        return executeClientRequest("/cashier/order/quickOrder", body, () -> quickOrderInternal(body));
    }

    private R quickOrderInternal(Map<String, Object> body) {
        String tableNumber = bodyText(body, "tableNumber", "table_number");
        String diningType = normalizeDiningType(firstBodyValue(
                body, "dineInOrTakeOut", "diningType", "orderType", "order_type"));
        Object gl = body != null ? body.get("goods_list") : null;
        if (gl == null || !(gl instanceof List)) {
            return R.error("菜品列表不能为空");
        }
        if ("堂食".equals(diningType) && tableNumber == null) {
            return R.error("堂食订单桌号不能为空");
        }
        List<?> goodsListInput = (List<?>) gl;
        List<OrderDetail> goodsList = new ArrayList<>();
        double settAmount = 0;
        for (Object rawLine : goodsListInput) {
            if (!(rawLine instanceof Map)) {
                return R.error(400, "goods_list 每一项必须是对象");
            }
            @SuppressWarnings("unchecked")
            Map<String, Object> m = (Map<String, Object>) rawLine;
            OrderDetail d = new OrderDetail();
            try {
                d.setDish_id(parseInteger(m.get("dish_id"), "dish_id"));
            } catch (IllegalArgumentException ex) {
                return R.error(400, ex.getMessage());
            }
            d.setName(optionalText(m.get("name")));
            Object qty = m.get("quantity");
            d.setQuantity(qty != null ? qty.toString() : "1");
            d.setUnit(optionalText(m.get("unit")));
            d.setImage(optionalText(m.get("image")));
            double price;
            try {
                price = parseMoney(m.get("total_price"), "total_price");
            } catch (IllegalArgumentException ex) {
                return R.error(400, ex.getMessage());
            }
            d.setTotal_price(price);
            d.setCid(optionalText(m.get("cid")));
            d.setRemark(optionalText(m.get("remark")));
            d.setSelectedSpicy(optionalText(firstMapValue(m, "specification", "selectedSpicy", "selected_spicy")));
            d.setClient_line_id(optionalText(firstMapValue(m, "client_line_id", "clientLineId")));
            if (m.get("line_type") != null) {
                d.setLine_type(m.get("line_type").toString());
            }
            if (m.get("combo_id") != null) {
                try {
                    d.setCombo_id(parseLong(m.get("combo_id"), "combo_id"));
                } catch (IllegalArgumentException ex) {
                    return R.error(400, ex.getMessage());
                }
            }
            if (m.get("combo_selection_json") != null) {
                d.setCombo_selection_json(m.get("combo_selection_json").toString());
            }
            if (m.get("combo_selections") instanceof Map) {
                @SuppressWarnings("unchecked")
                Map<String, Object> sel = (Map<String, Object>) m.get("combo_selections");
                d.setComboSelections(sel);
            }
            goodsList.add(d);
            settAmount += price;
        }
        double packagingFee = "打包".equals(diningType)
                ? OrderPackagingFeeCalculator.calcYuan(settAmount) : 0d;
        double orderSettAmount = "打包".equals(diningType)
                ? OrderPackagingFeeCalculator.resolveSettForTakeOut(settAmount, settAmount)
                : OrderPackagingFeeCalculator.roundMoney(settAmount);
        OrderDTO dto = new OrderDTO();
        dto.setOrder_no(generateCashierOrderNo());
        dto.setTable_number(tableNumber);
        dto.setNumber_of_diners(body.get("number_of_diners") != null
                ? body.get("number_of_diners").toString()
                : "1");
        dto.setSett_amount(orderSettAmount);
        dto.setDiscount_amount(0.0);
        dto.setTransac_status("unsettled");
        dto.setOrder_receiving("mis_order");
        dto.setDineInOrTakeOut(diningType);
        dto.setOrderNumber(1);
        dto.setRemark(body.get("remark") != null ? (String) body.get("remark") : null);
        dto.setOpenid(CASHIER_OPENID);
        dto.setOrder_channel(OrderController.CHANNEL_CASHIER);
        dto.setMerchantId("1");
        dto.setGoods_list(goodsList);
        fillDishIdsByName(goodsList);

        Integer shopId = request == null ? null : AdminShopRequest.getResolvedShopId(request);
        if (shopId == null || shopId <= 0) {
            return R.error(4001, "缺少已授权的门店上下文");
        }
        dto.setShop_id(shopId);

        Shop shop = shopService != null ? shopService.getById(shopId) : null;
        if (!ShopOrderingOpenHelper.isOrderingOpen(shop)) {
            boolean force = "1".equals(body.get("force")) || Boolean.TRUE.equals(body.get("force"));
            boolean canForce = false;
            Object adminIdObj = request != null ? request.getAttribute(SysInterceptor.ATTR_ADMIN_ID) : null;
            Integer adminId = adminIdObj != null ? Integer.valueOf(adminIdObj.toString()) : null;
            if (force && adminId != null && adminPermissionService != null) {
                canForce = adminPermissionService.getPermissionCodesByAdminId(adminId).contains("admin:manage");
            }
            if (!canForce) {
                return R.error(4003, "门店暂未营业，请先开启营业");
            }
        }

        if ("堂食".equals(diningType) && tableNumber != null && tableService != null) {
            Table existingTable = tableService.getOne(new QueryWrapper<Table>()
                    .eq("shop_id", shopId).eq("number", tableNumber).last("LIMIT 1"));
            if (existingTable == null) {
                Table newTable = new Table();
                newTable.setNumber(tableNumber);
                newTable.setShop_id(shopId);
                newTable.setStatus(0);
                tableService.save(newTable);
            }
        }

        R r;
        if (request != null) {
            request.setAttribute(OrderController.CASHIER_QUICK_ORDER_ATTRIBUTE, Boolean.TRUE);
        }
        try {
            r = orderController.create(dto, request);
        } finally {
            if (request != null) {
                request.removeAttribute(OrderController.CASHIER_QUICK_ORDER_ATTRIBUTE);
            }
        }
        if (r.get("code") != null && Integer.valueOf(0).equals(r.get("code"))) {
            logOrder((String) dto.getOrder_no(), "create", "admin_id", getAdminIdStr());
            Integer createdOrderId = dto.getId() != null
                    ? dto.getId()
                    : (r.get("id") instanceof Number ? ((Number) r.get("id")).intValue() : null);
            Order committed = orderService != null && createdOrderId != null
                    ? orderService.getById(createdOrderId) : null;
            if ("打包".equals(diningType)) {
                r.put("packaging_fee", packagingFee);
                r.put("sett_amount", dto.getSett_amount());
            }
            r.put("accepted", true);
            r.put("fulfillment_status", "ready");
            r.put("cloud_acceptance_status", committed != null
                    ? committed.getOrder_receiving() : "mis_order");
            r.put("printSuccess", null);
            r.put("order_details", buildOrderDetailMappings(createdOrderId));
        }
        return r;
    }

    static String generateCashierOrderNo() {
        return OrderNumberGenerator.next();
    }

    private static String normalizeDiningType(Object raw) {
        if (raw == null) {
            return "堂食";
        }
        String value = raw.toString().trim();
        if ("打包".equals(value)
                || "外带".equals(value)
                || "pickup".equalsIgnoreCase(value)
                || "take_out".equalsIgnoreCase(value)
                || "takeout".equalsIgnoreCase(value)) {
            return "打包";
        }
        return "堂食";
    }

    private static Object firstBodyValue(Map<String, Object> body, String... keys) {
        if (body == null) return null;
        for (String key : keys) {
            Object value = body.get(key);
            if (value != null && !value.toString().trim().isEmpty()) return value;
        }
        return null;
    }

    private static Object firstMapValue(Map<String, Object> body, String... keys) {
        return firstBodyValue(body, keys);
    }

    private List<Map<String, Object>> buildOrderDetailMappings(Integer orderId) {
        if (orderId == null || orderId <= 0 || orderDetailService == null) {
            return Collections.emptyList();
        }
        List<OrderDetail> details = orderDetailService.list(new QueryWrapper<OrderDetail>()
                .eq("mId", orderId).orderByAsc("id"));
        List<Map<String, Object>> mappings = new ArrayList<>();
        for (OrderDetail detail : details) {
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("detail_id", detail.getId());
            item.put("dish_id", detail.getDish_id());
            item.put("quantity", parsePositiveQuantity(detail.getQuantity()));
            item.put("client_line_id", detail.getClient_line_id());
            item.put("line_type", detail.getLine_type());
            item.put("parent_detail_id", detail.getParent_detail_id());
            mappings.add(item);
        }
        return mappings;
    }

    private static int parsePositiveQuantity(String raw) {
        try { return Math.max(0, Integer.parseInt(raw)); }
        catch (Exception ignored) { return 0; }
    }

    private static String bodyText(Map<String, Object> body, String... keys) {
        Object value = firstBodyValue(body, keys);
        return value == null ? null : value.toString().trim();
    }

    private static Integer bodyInteger(Map<String, Object> body, String... keys) {
        Object value = firstBodyValue(body, keys);
        if (value instanceof Number) return ((Number) value).intValue();
        try {
            return value == null ? null : Integer.valueOf(value.toString().trim());
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    private static String optionalText(Object value) {
        if (value == null) return null;
        String text = value.toString().trim();
        return text.isEmpty() ? null : text;
    }

    private static Integer parseInteger(Object value, String field) {
        if (value == null) return null;
        if (value instanceof Number) return ((Number) value).intValue();
        try {
            return Integer.valueOf(value.toString().trim());
        } catch (RuntimeException ex) {
            throw new IllegalArgumentException(field + " 必须是整数");
        }
    }

    private static Long parseLong(Object value, String field) {
        if (value instanceof Number) return ((Number) value).longValue();
        try {
            return Long.valueOf(value.toString().trim());
        } catch (RuntimeException ex) {
            throw new IllegalArgumentException(field + " 必须是整数");
        }
    }

    private static double parseMoney(Object value, String field) {
        if (value == null) return 0d;
        final double parsed;
        try {
            parsed = value instanceof Number
                    ? ((Number) value).doubleValue()
                    : Double.parseDouble(value.toString().trim());
        } catch (RuntimeException ex) {
            throw new IllegalArgumentException(field + " 必须是有效金额");
        }
        if (!Double.isFinite(parsed)) {
            throw new IllegalArgumentException(field + " 必须是有效金额");
        }
        return parsed;
    }

    private static Double bodyDouble(Map<String, Object> body, String... keys) {
        Object value = firstBodyValue(body, keys);
        if (value instanceof Number) return ((Number) value).doubleValue();
        try {
            return value == null ? null : Double.valueOf(value.toString().trim());
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    private static Boolean bodyBoolean(Map<String, Object> body, String... keys) {
        Object value = firstBodyValue(body, keys);
        if (value instanceof Boolean) return (Boolean) value;
        if (value == null) return null;
        String text = value.toString().trim();
        if ("1".equals(text) || "yes".equalsIgnoreCase(text) || "true".equalsIgnoreCase(text)) return true;
        if ("0".equals(text) || "no".equalsIgnoreCase(text) || "false".equalsIgnoreCase(text)) return false;
        return null;
    }

    private static void appendManualDiscountRemark(Order order, String reason, double discount) {
        String old = order.getRemark() != null ? order.getRemark() : "";
        String tag = "【手动优惠】" + (reason != null ? reason : discount + "元");
        if (!old.contains(tag) && (reason != null || !old.contains("【手动优惠】"))) {
            order.setRemark(old + (old.isEmpty() ? "" : "；") + tag);
        }
    }

    private void syncDiscountedTableAmount(Order order, Integer shopId) {
        if (!"堂食".equals(order.getDineInOrTakeOut()) || order.getTable_number() == null) return;
        Table table = tableService.getOne(new QueryWrapper<Table>()
                .eq("shop_id", shopId).eq("number", order.getTable_number()).last("LIMIT 1"));
        if (table == null) return;
        List<Order> unsettled = orderService.list(new QueryWrapper<Order>()
                .eq("shop_id", shopId)
                .eq("table_number", order.getTable_number())
                .eq("transac_status", "unsettled"));
        table.setAmount(sumOutstanding(unsettled));
        if (!tableService.updateById(table)) {
            throw new IllegalStateException("桌台优惠金额同步失败");
        }
    }

    @PostMapping("/addDishes")
    @AuditLog(module = "cashier", action = "cashier_add_dish", target = "#p0['orderNo'] ?: #p0['order_no']")
    public R addDishes(@RequestBody Map<String, Object> body) {
        return executeClientRequest("/cashier/order/addDishes", body, () -> addDishesInternal(body));
    }

    private R addDishesInternal(Map<String, Object> body) {
        String orderNo = body != null ? (String) body.get("order_no") : null;
        String tableNumber = body != null ? (String) body.get("table_number") : null;
        Object gl = body != null ? body.get("goods_list") : null;
        if (orderNo == null || tableNumber == null || gl == null || !(gl instanceof List)) {
            return R.error("订单号、桌号与菜品列表不能为空");
        }
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> goodsListMap = (List<Map<String, Object>>) gl;
        List<OrderDetail> goodsList = new ArrayList<>();
        double addAmount = 0;
        for (Map<String, Object> m : goodsListMap) {
            OrderDetail d = new OrderDetail();
            try {
                d.setDish_id(parseInteger(m.get("dish_id"), "dish_id"));
            } catch (IllegalArgumentException ex) {
                return R.error(400, ex.getMessage());
            }
            d.setName(optionalText(m.get("name")));
            Object qty = m.get("quantity");
            d.setQuantity(qty != null ? qty.toString() : "1");
            d.setUnit(optionalText(m.get("unit")));
            d.setImage(optionalText(m.get("image")));
            Object tp = m.get("total_price");
            double price = tp != null ? ((Number) tp).doubleValue() : 0;
            d.setTotal_price(price);
            d.setCid(optionalText(m.get("cid")));
            d.setRemark(optionalText(m.get("remark")));
            d.setSelectedSpicy(optionalText(firstMapValue(
                    m, "selectedSpicy", "selected_spicy", "specification")));
            d.setClient_line_id(optionalText(firstMapValue(
                    m, "client_line_id", "clientLineId", "local_detail_id", "localDetailId")));
            if (m.get("line_type") != null) {
                d.setLine_type(m.get("line_type").toString());
            }
            if (m.get("combo_id") != null) {
                d.setCombo_id(((Number) m.get("combo_id")).longValue());
            }
            if (m.get("combo_selection_json") != null) {
                if (m.get("combo_selection_json") instanceof Map) {
                    @SuppressWarnings("unchecked")
                    Map<String, Object> sel = (Map<String, Object>) m.get("combo_selection_json");
                    d.setComboSelections(sel);
                } else {
                    d.setCombo_selection_json(m.get("combo_selection_json").toString());
                }
            }
            if (m.get("combo_selections") instanceof Map) {
                @SuppressWarnings("unchecked")
                Map<String, Object> sel = (Map<String, Object>) m.get("combo_selections");
                d.setComboSelections(sel);
            } else if (m.get("combo_selections") instanceof String) {
                d.setCombo_selection_json(m.get("combo_selections").toString());
            }
            goodsList.add(d);
            addAmount += price;
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null || shopId <= 0) {
            return R.error(4001, "缺少已授权的门店上下文");
        }
        Shop shop = shopService != null ? shopService.getById(shopId) : null;
        if (!ShopOrderingOpenHelper.isOrderingOpen(shop)) {
            boolean force = "1".equals(body.get("force")) || Boolean.TRUE.equals(body.get("force"));
            boolean canForce = false;
            Object adminIdObj = request != null ? request.getAttribute(SysInterceptor.ATTR_ADMIN_ID) : null;
            Integer adminId = adminIdObj != null ? Integer.valueOf(adminIdObj.toString()) : null;
            if (force && adminId != null && adminPermissionService != null) {
                canForce = adminPermissionService.getPermissionCodesByAdminId(adminId).contains("admin:manage");
            }
            if (!canForce) {
                return R.error(4003, "门店暂未营业，请先开启营业");
            }
        }
        QueryWrapper<Order> existingQuery = new QueryWrapper<Order>().eq("order_no", orderNo);
        if (Integer.valueOf(1).equals(shopId)) {
            existingQuery.and(w -> w.eq("shop_id", 1).or().isNull("shop_id"));
        } else {
            existingQuery.eq("shop_id", shopId);
        }
        Order existing = orderService.getOne(existingQuery.orderByDesc("id").last("LIMIT 1"));
        if (existing == null) {
            return R.error("订单不存在");
        }
        if (existing.getTable_number() != null
                && !existing.getTable_number().trim().equals(tableNumber.trim())) {
            return R.error(4003, "订单不属于当前桌台");
        }
        if (existing.getOpenid() == null || existing.getOpenid().trim().isEmpty()) {
            return R.error(403, "订单身份异常，无法加菜");
        }
        OrderDTO dto = new OrderDTO();
        dto.setOrder_no(orderNo);
        dto.setTable_number(existing.getTable_number() != null ? existing.getTable_number() : tableNumber);
        dto.setOrderNumber(existing.getOrderNumber() != null ? existing.getOrderNumber() : 1);
        dto.setSett_amount(addAmount);
        dto.setRemark(body.get("remark") != null ? (String) body.get("remark") : null);
        dto.setGoods_list(goodsList);
        dto.setOpenid(existing.getOpenid());
        dto.setOrder_channel(OrderController.CHANNEL_CASHIER);
        dto.setMerchantId("1");
        dto.setShop_id(shopId);
        dto.setExpectedVersion(orderRevisionService.readExpectedVersion(body));
        fillDishIdsByName(goodsList);

        if (request != null) {
            request.setAttribute(OrderController.CASHIER_QUICK_ORDER_ATTRIBUTE, Boolean.TRUE);
        }
        R r;
        try {
            r = orderController.addDishes(dto, request);
        } finally {
            if (request != null) {
                request.removeAttribute(OrderController.CASHIER_QUICK_ORDER_ATTRIBUTE);
            }
        }
        if (r.get("code") != null && Integer.valueOf(0).equals(r.get("code"))) {
            logOrder(orderNo, "add_dish", "admin_id", getAdminIdStr());
        }
        return r;
    }

    private void fillDishIdsByName(List<OrderDetail> goodsList) {
        if (dishService == null || goodsList == null || goodsList.isEmpty()) {
            return;
        }
        Set<String> names = goodsList.stream()
                .map(OrderDetail::getName)
                .filter(Objects::nonNull)
                .collect(Collectors.toSet());
        if (names.isEmpty()) {
            return;
        }
        List<com.lanf.entity.Dish> list = dishService.list(
                new QueryWrapper<com.lanf.entity.Dish>().select("id", "name").in("name", names));
        if (list == null || list.isEmpty()) {
            return;
        }
        Map<String, Integer> idByName = new HashMap<>();
        for (com.lanf.entity.Dish dish : list) {
            if (dish != null && dish.getName() != null && dish.getId() != null) {
                idByName.put(dish.getName(), dish.getId());
            }
        }
        for (OrderDetail d : goodsList) {
            if (d.getDish_id() == null && d.getName() != null) {
                d.setDish_id(idByName.get(d.getName()));
            }
        }
    }

    @PostMapping("/refundDish")
    @Transactional(rollbackFor = Exception.class)
    @AuditLog(module = "cashier", action = "cashier_refund_dish", target = "#p0['orderNo'] ?: #p0['order_no']", diff = OrderRefundDiffProvider.class)
    public R refundDish(@RequestBody Map<String, Object> body) {
        return executeClientRequest("/cashier/order/refundDish", body, () -> refundDishInternal(body));
    }

    private R refundDishInternal(Map<String, Object> body) {
        String orderNo = bodyText(body, "order_no", "orderNo");
        Integer detailId = bodyInteger(body, "detail_id", "detailId");
        Integer quantity = bodyInteger(body, "quantity");
        if (orderNo == null || detailId == null || quantity == null || quantity <= 0) {
            return R.error("订单号、明细 id 与退菜数量不能为空");
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null) {
            return R.error(4001, "缺少门店上下文");
        }

        // Keep the same lock order as checkout: order first, then its detail.
        // This serializes refund-vs-checkout and prevents stale amount writes.
        Order order = orderService.getOne(new QueryWrapper<Order>()
                .eq("order_no", orderNo)
                .eq("shop_id", shopId)
                .last("LIMIT 1 FOR UPDATE"));
        if (order == null) {
            return R.error("订单不存在或不属于当前门店");
        }
        if (!"unsettled".equals(order.getTransac_status())) {
            return R.error("仅未结账订单允许退菜");
        }
        int currentRevision = orderRevisionService.assertExpected(
                order, orderRevisionService.readExpectedVersion(body));
        OrderDetail detail = orderDetailService.getOne(new QueryWrapper<OrderDetail>()
                .eq("id", detailId)
                .eq("mId", order.getId())
                .eq("Morder_no", orderNo)
                .last("LIMIT 1 FOR UPDATE"));
        if (detail == null) {
            return R.error("明细不存在或不属于该订单");
        }
        if (OrderDetailLineStatus.isRefunded(detail.getLine_status())) {
            return R.error("该明细已退菜");
        }
        R authorizationError = authorizeHighRiskAction(
                body, "order:operate:refund", orderNo, null, "unsettled");
        if (authorizationError != null) {
            return authorizationError;
        }
        String rawStockAction = bodyText(body, "stock_action", "stockAction", "action");
        com.lanf.order.RefundStockAction stockAction = com.lanf.order.RefundStockAction.from(rawStockAction, com.lanf.order.RefundStockAction.RESTORE);
        String reason = bodyText(body, "reason", "remark");
        String operator = "authorized_admin:" + getSensitiveAuthorizedAdminIdStr();
        try {
            int currentQty = Integer.parseInt(detail.getQuantity() != null ? detail.getQuantity().trim() : "0");
            if (quantity >= currentQty) {
                orderDetailRefundService.refundFullLine(detail, order, stockAction, operator, reason);
            } else {
                orderDetailRefundService.refundPartial(detail, order, quantity, stockAction, operator, reason);
            }
        } catch (NumberFormatException e) {
            return R.error("数量格式错误");
        } catch (IllegalStateException | IllegalArgumentException e) {
            return R.error(e.getMessage());
        }
        int revision = orderRevisionService.increment(order, currentRevision);
        logOrder(orderNo, "refund", "authorized_admin_id", getSensitiveAuthorizedAdminIdStr());
        return R.ok().put("revision", revision);
    }



    /**
     * 人工退款（现金/组合支付订单）：收银员线下退回现金后，按实退金额回写订单 {@code refund_amount} 并扣减现金渠道列
     * {@code pay_amount_cash}。仅已支付订单；默认退「现金列剩余 ∩ 剩余可退」全部，可选 {@code refundAmount} 指定部分。
     * 服务端按当前门店锁定订单，与结账/退菜串行化；客户端应携带 X-Client-Request-Id。
     */
    @PostMapping("/refund")
    @Transactional(rollbackFor = Exception.class)
    @AuditLog(module = "cashier", action = "cashier_refund_cash", target = "#p0['orderNo'] ?: #p0['order_no']", diff = OrderRefundDiffProvider.class)
    public R refund(@RequestBody Map<String, Object> body) {
        return executeClientRequest("/cashier/order/refund", body, () -> refundInternal(body));
    }

    private R refundInternal(Map<String, Object> body) {
        String orderNo = bodyText(body, "order_no", "orderNo");
        if (orderNo == null) {
            return R.error("订单号不能为空");
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null) {
            return R.error(4001, "缺少门店上下文");
        }
        Order order = orderService.getOne(new QueryWrapper<Order>()
                .eq("order_no", orderNo.trim())
                .eq("shop_id", shopId)
                .last("LIMIT 1 FOR UPDATE"));
        if (order == null) {
            return R.error("订单不存在或不属于当前门店");
        }
        if (!"success".equals(order.getTransac_status())) {
            return R.error("仅已支付订单可人工退款");
        }
        String takeoutRefundBlock = takeoutDeliveryService.getRefundBlockReason(order);
        if (takeoutRefundBlock != null) {
            return R.error(takeoutRefundBlock);
        }

        R authorizationError = authorizeHighRiskAction(
                body, "order:operate:refund", orderNo,
                resolveCashRefundAmount(order, body), "success");
        if (authorizationError != null) {
            return authorizationError;
        }

        R result = cashierCheckoutService.refundCashComponent(shopId, body);
        if (Integer.valueOf(0).equals(result.get("code"))) {
            logOrder(orderNo, "refund", "authorized_admin_id", getSensitiveAuthorizedAdminIdStr());
        }
        return result;
    }

    @PostMapping("/updatePrice")
    @Transactional(rollbackFor = Exception.class)
    @AuditLog(module = "cashier", action = "cashier_change_price", target = "#p0['orderNo'] ?: #p0['order_no']")
    public R updatePrice(@RequestBody Map<String, Object> body) {
        String orderNo = body != null && body.get("order_no") != null
                ? body.get("order_no").toString().trim() : null;
        Integer detailId = body != null && body.get("detail_id") instanceof Number
                ? ((Number) body.get("detail_id")).intValue() : null;
        Double totalPrice = body != null && body.get("total_price") instanceof Number
                ? ((Number) body.get("total_price")).doubleValue() : null;
        if (orderNo == null || detailId == null || totalPrice == null) {
            return R.error("订单号、明细 id 与总价不能为空");
        }
        if (totalPrice < 0d || totalPrice.isNaN() || totalPrice.isInfinite()) {
            return R.error("总价必须为大于等于 0 的有效金额");
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null) {
            return R.error(4001, "缺少门店上下文");
        }
        Order order = orderService.getOne(new QueryWrapper<Order>()
                .eq("order_no", orderNo).eq("shop_id", shopId).last("LIMIT 1 FOR UPDATE"));
        if (order == null) {
            return R.error("订单不存在或不属于当前门店");
        }
        if (!"unsettled".equals(order.getTransac_status())) {
            return R.error("仅未结账订单允许改价或赠送菜品");
        }
        int currentRevision = orderRevisionService.assertExpected(
                order, orderRevisionService.readExpectedVersion(body));
        OrderDetail detail = orderDetailService.getById(detailId);
        if (detail == null || !orderNo.equals(detail.getMorder_no())
                || !order.getId().equals(detail.getMId())) {
            return R.error("明细不存在或不属于该订单");
        }
        R authorizationError = authorizeHighRiskAction(
                body, "order:operate:changePrice", orderNo, BigDecimal.valueOf(totalPrice), "unsettled");
        if (authorizationError != null) {
            return authorizationError;
        }
        order = wechatJsapiPaymentService.prepareForAmountMutation(order);
        detail.setTotal_price(totalPrice);
        if (!orderDetailService.updateById(detail)) {
            throw new IllegalStateException("订单明细金额更新失败");
        }
        recalcSettFromActiveDetails(order);
        int revision = orderRevisionService.increment(order, currentRevision);
        logOrder(orderNo, totalPrice == 0d ? "gift_dish" : "change_price",
                "authorized_admin_id", getSensitiveAuthorizedAdminIdStr());
        return R.ok(totalPrice == 0d ? "赠送成功" : "改价成功")
                .put("sett_amount", order.getSett_amount())
                .put("service_fee", order.getService_fee())
                .put("revision", revision);
    }

    @PostMapping("/discount")
    @Transactional(rollbackFor = Exception.class)
    @AuditLog(module = "cashier", action = "cashier_discount", target = "#p0['orderNo'] ?: #p0['order_no']")
    public R discount(@RequestBody Map<String, Object> body) {
        if (body == null) {
            return R.error("请求体不能为空");
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null) {
            return R.error(4001, "缺少门店上下文");
        }
        Integer orderId = bodyInteger(body, "orderId", "id");
        String orderNo = bodyText(body, "orderNo", "order_no");
        if (orderId == null && orderNo == null) {
            return R.error("orderId 与 orderNo 至少传一项");
        }
        QueryWrapper<Order> orderQuery = new QueryWrapper<Order>().eq("shop_id", shopId);
        if (orderId != null) {
            orderQuery.eq("id", orderId);
        } else {
            orderQuery.eq("order_no", orderNo);
        }
        Order order = orderService.getOne(orderQuery.last("LIMIT 1 FOR UPDATE"));
        if (order == null) {
            return R.error("订单不存在或不属于当前门店");
        }
        if (!"unsettled".equalsIgnoreCase(order.getTransac_status())) {
            return R.error("仅未结账订单可手动优惠");
        }
        int currentRevision = orderRevisionService.assertExpected(
                order, orderRevisionService.readExpectedVersion(body));
        order = wechatJsapiPaymentService.prepareForAmountMutation(order);
        Double discountAmount = bodyDouble(body, "discountAmount", "discount_amount");
        Double payRate = bodyDouble(body, "payRate", "pay_rate", "discountRate", "discount_rate");
        Boolean wipeZero = bodyBoolean(body, "wipeZero", "wipe_zero");
        if (discountAmount == null && payRate == null && !Boolean.TRUE.equals(wipeZero)) {
            return R.error("discountAmount、payRate 或 wipeZero 至少传一项");
        }
        double newDiscount;
        try {
            newDiscount = OrderManualDiscountCalculator.resolveDiscountYuan(
                    order, discountAmount, payRate, wipeZero);
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        }
        double gross = OrderManualDiscountCalculator.orderGrossYuan(order);
        if (gross <= 0d) {
            return R.error("订单金额异常，无法优惠");
        }
        R authorizationError = authorizeHighRiskAction(
                body, "order:operate:discount", order.getOrder_no(),
                BigDecimal.valueOf(newDiscount), "unsettled");
        if (authorizationError != null) {
            return authorizationError;
        }
        order.setDiscount_amount(newDiscount);
        appendManualDiscountRemark(order, bodyText(body, "reason", "remark"), newDiscount);
        if (!orderService.updateById(order)) {
            throw new IllegalStateException("订单优惠更新失败");
        }
        syncDiscountedTableAmount(order, shopId);
        takeoutDeliveryService.enrichOrder(order);
        double payable = OrderManualDiscountCalculator.payableAfterDiscountYuan(order, newDiscount);
        int revision = orderRevisionService.increment(order, currentRevision);
        logOrder(order.getOrder_no(), "manual_discount",
                "authorized_admin_id", getSensitiveAuthorizedAdminIdStr());
        return R.ok()
                .put("order", order)
                .put("grossYuan", gross)
                .put("discount_amount", newDiscount)
                .put("payableYuan", payable)
                .put("revision", revision);
    }

    @PostMapping("/checkout")
    @AuditLog(module = "cashier", action = "cashier_checkout", target = "#p0['orderNo'] ?: #p0['order_no']")
    public R checkout(@RequestBody Map<String, Object> body) {
        return executeClientRequest("/cashier/order/checkout", body, () -> checkoutInternal(body));
    }

    @PostMapping("/force-checkout")
    @AuditLog(module = "cashier", action = "cashier_force_checkout", target = "#p0['orderNo'] ?: #p0['order_no']")
    public R forceCheckout(@RequestBody Map<String, Object> body) {
        Map<String, Object> req = body != null ? new LinkedHashMap<>(body) : new LinkedHashMap<>();
        req.put("force", true);
        return executeClientRequest("/cashier/order/force-checkout", req, () -> checkoutInternal(req));
    }

    private R checkoutInternal(Map<String, Object> body) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        R result = cashierCheckoutService.checkout(shopId, body);
        if (Integer.valueOf(0).equals(result.get("code"))
                && !Boolean.TRUE.equals(result.get("idempotent"))) {
            logOrder(bodyText(body, "order_no", "orderNo"), "checkout", "admin_id", getAdminIdStr());
        }
        return result;
    }

    private R executeClientRequest(String requestPath, Object requestBody, Supplier<R> operation) {
        String requestId = request != null ? request.getHeader("X-Client-Request-Id") : null;
        if (requestId == null || requestId.trim().isEmpty() || clientRequestService == null) {
            return operation.get();
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        Object rawAdminId = request != null ? request.getAttribute(com.lanf.interceptor.SysInterceptor.ATTR_ADMIN_ID) : null;
        Integer adminId = rawAdminId instanceof Integer ? (Integer) rawAdminId : null;
        return clientRequestService.execute(shopId, adminId, requestId, requestPath, requestBody, operation);
    }
    @PostMapping("/hang")
    @AuditLog(module = "cashier", action = "cashier_order_hang", target = "#p0['orderNo'] ?: #p0['order_no']")
    public R hang(@RequestBody Map<String, Object> body) {
        String orderNo = bodyText(body, "order_no", "orderNo");
        if (!StringUtils.hasText(orderNo)) {
            return R.error("订单号不能为空");
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        QueryWrapper<Order> q = new QueryWrapper<Order>().eq("order_no", orderNo.trim());
        if (shopId != null) {
            if (shopId == 1) {
                q.and(w -> w.eq("shop_id", 1).or().isNull("shop_id"));
            } else {
                q.eq("shop_id", shopId);
            }
        }
        Order order = orderService.getOne(q, false);
        if (order == null) {
            return R.error("订单不存在或不属于当前门店");
        }
        if (!"unsettled".equalsIgnoreCase(order.getTransac_status())) {
            return R.error("已结账或已取消的订单不可挂单");
        }
        String reason = bodyText(body, "reason", "hang_reason", "remark");
        Integer adminId = null;
        Object rawAdminId = request != null ? request.getAttribute(com.lanf.interceptor.SysInterceptor.ATTR_ADMIN_ID) : null;
        if (rawAdminId instanceof Integer) {
            adminId = (Integer) rawAdminId;
        }

        order.setHang_status(1);
        order.setHang_time(new Date());
        order.setHang_reason(StringUtils.hasText(reason) ? reason.trim() : null);
        order.setHang_admin_id(adminId);
        orderService.updateById(order);

        logOrder(orderNo, "hang", "admin_id", getAdminIdStr());
        return R.ok()
                .put("order_no", orderNo)
                .put("hang_status", 1)
                .put("hang_time", order.getHang_time())
                .put("hang_reason", order.getHang_reason());
    }

    @PostMapping("/unhang")
    @AuditLog(module = "cashier", action = "cashier_order_unhang", target = "#p0['orderNo'] ?: #p0['order_no']")
    public R unhang(@RequestBody Map<String, Object> body) {
        String orderNo = bodyText(body, "order_no", "orderNo");
        if (!StringUtils.hasText(orderNo)) {
            return R.error("订单号不能为空");
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        QueryWrapper<Order> q = new QueryWrapper<Order>().eq("order_no", orderNo.trim());
        if (shopId != null) {
            if (shopId == 1) {
                q.and(w -> w.eq("shop_id", 1).or().isNull("shop_id"));
            } else {
                q.eq("shop_id", shopId);
            }
        }
        Order order = orderService.getOne(q, false);
        if (order == null) {
            return R.error("订单不存在或不属于当前门店");
        }
        order.setHang_status(0);
        order.setHang_time(null);
        order.setHang_reason(null);
        order.setHang_admin_id(null);
        orderService.updateById(order);

        logOrder(orderNo, "unhang", "admin_id", getAdminIdStr());
        return R.ok()
                .put("order_no", orderNo)
                .put("hang_status", 0);
    }

    @GetMapping("/hang-list")
    public R hangList() {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        QueryWrapper<Order> q = new QueryWrapper<Order>()
                .eq("transac_status", "unsettled")
                .eq("hang_status", 1)
                .orderByAsc("hang_time");
        if (shopId != null) {
            if (shopId == 1) {
                q.and(w -> w.eq("shop_id", 1).or().isNull("shop_id"));
            } else {
                q.eq("shop_id", shopId);
            }
        }
        List<Order> list = orderService.list(q);
        if (list == null) {
            list = Collections.emptyList();
        }
        List<Map<String, Object>> result = new ArrayList<>();
        long now = System.currentTimeMillis();
        for (Order o : list) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("order_id", o.getId());
            m.put("order_no", o.getOrder_no());
            m.put("table_number", o.getTable_number());
            m.put("number_of_diners", o.getNumber_of_diners());
            m.put("sett_amount", o.getSett_amount());
            m.put("hang_time", o.getHang_time());
            m.put("hang_reason", o.getHang_reason());
            m.put("hang_admin_id", o.getHang_admin_id());
            long hangMinutes = 0L;
            if (o.getHang_time() != null) {
                hangMinutes = Math.max(0L, (now - o.getHang_time().getTime()) / 60000L);
            }
            m.put("hang_minutes", hangMinutes);
            result.add(m);
        }
        return R.ok().put("list", result).put("total", result.size());
    }

    @PostMapping("/unCheckout")
    @AuditLog(module = "cashier", action = "cashier_un_checkout", target = "#p0['orderNo'] ?: #p0['order_no']")
    public R unCheckout(@RequestBody Map<String, Object> body) {
        String orderNo = bodyText(body, "order_no", "orderNo");
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        R authorizationError = authorizeHighRiskAction(
                body, "order:operate:reopen", orderNo, null, "success");
        if (authorizationError != null) {
            return authorizationError;
        }
        R result = cashierCheckoutService.unCheckout(shopId, orderNo);
        if (Integer.valueOf(0).equals(result.get("code"))
                && !Boolean.TRUE.equals(result.get("alreadyUnChecked"))) {
            logOrder(orderNo, "un_checkout", "admin_id", getAdminIdStr());
        }
        return result;
    }

    @PostMapping("/updateDiners")
    @AuditLog(module = "cashier", action = "cashier_update_diners", target = "#p0['orderNo'] ?: #p0['order_no']")
    public R updateDiners(@RequestBody Map<String, Object> body) {
        return executeClientRequest("/cashier/order/updateDiners", body, () -> updateDinersInternal(body));
    }

    private R updateDinersInternal(Map<String, Object> body) {
        if (body == null) {
            return R.error(400, "请求体不能为空");
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null) {
            return R.error(4001, "缺少门店上下文");
        }
        Integer orderId = bodyInteger(body, "orderId", "order_id", "id");
        String orderNo = bodyText(body, "orderNo", "order_no");
        if (orderId == null && (orderNo == null || orderNo.trim().isEmpty())) {
            return R.error(400, "orderNo 与 orderId 至少提供一项");
        }
        Object rawDiners = firstBodyValue(body, "number_of_diners", "numberOfDiners", "diners", "numberOfPeople", "number_of_people");
        if (rawDiners == null || (rawDiners instanceof String && ((String) rawDiners).trim().isEmpty())) {
            return R.error(400, "用餐人数不能为空");
        }
        int diners;
        try {
            if (rawDiners instanceof Number) {
                diners = ((Number) rawDiners).intValue();
            } else {
                diners = Integer.parseInt(rawDiners.toString().trim());
            }
        } catch (NumberFormatException e) {
            return R.error(400, "用餐人数格式错误，必须为正整数");
        }
        if (diners < 1 || diners > 999) {
            return R.error(400, "用餐人数必须在 1 到 999 之间");
        }

        QueryWrapper<Order> orderQuery = new QueryWrapper<Order>().eq("shop_id", shopId);
        if (orderId != null) {
            orderQuery.eq("id", orderId);
        } else {
            orderQuery.eq("order_no", orderNo);
        }
        Order order = orderService.getOne(orderQuery.last("LIMIT 1"));
        if (order == null) {
            return R.error(404, "订单不存在或不属于当前门店");
        }

        String transacStatus = order.getTransac_status();
        if ("cancelled".equalsIgnoreCase(transacStatus) || "closed".equalsIgnoreCase(transacStatus)) {
            return R.error(4003, "已作废或已关闭订单不允许修改用餐人数");
        }

        if ("success".equalsIgnoreCase(transacStatus)) {
            Shop shop = shopService != null ? shopService.getById(shopId) : null;
            LocalTime settleTime = ShopBusinessWindowResolver.resolveSettleTimeOrDefault(shop);
            Date targetDate = order.getPay_time() != null ? order.getPay_time() : order.getOrder_time();
            if (targetDate != null) {
                LocalDateTime orderLdt = targetDate.toInstant().atZone(BUSINESS_ZONE).toLocalDateTime();
                LocalDate orderBizDay = orderLdt.toLocalTime().isBefore(settleTime)
                        ? orderLdt.toLocalDate().minusDays(1)
                        : orderLdt.toLocalDate();
                boolean isClosed = (dailyCloseSnapshotMapper != null && dailyCloseSnapshotMapper.selectCount(
                        new QueryWrapper<DailyCloseSnapshot>()
                                .eq("shop_id", shopId)
                                .eq("business_day", orderBizDay)
                                .eq("state", DailyCloseSnapshot.STATE_CLOSED)) > 0)
                        || (dailyStatService != null && (
                                dailyStatService.count(new QueryWrapper<DailyStat>()
                                        .eq("stat_date", orderBizDay).eq("shop_id", shopId)) > 0
                                || dailyStatService.count(new QueryWrapper<DailyStat>()
                                        .eq("stat_date", orderBizDay).isNull("shop_id")) > 0
                        ));
                if (isClosed) {
                    return R.error(40936, "该订单所属营业日(" + orderBizDay + ")已完成日结封账，禁止修改用餐人数");
                }
            }
        }

        String previousDiners = order.getNumber_of_diners();
        int oldDiners = 1;
        if (previousDiners != null && !previousDiners.trim().isEmpty()) {
            try { oldDiners = Integer.parseInt(previousDiners.trim()); } catch (Exception ignored) {}
        }

        order.setNumber_of_diners(String.valueOf(diners));
        if (!orderService.updateById(order)) {
            return R.error(500, "更新用餐人数失败");
        }

        adjustTeaFeeForDiners(order, oldDiners, diners);

        if (cashierEventWebSocketHub != null) {
            cashierEventWebSocketHub.broadcastTableOrderChanged(
                    order.getShop_id() != null ? order.getShop_id() : shopId,
                    order.getTable_number(),
                    order.getOrder_no(),
                    diners
            );
        }

        logOrder(order.getOrder_no(), "update_diners", "admin_id", getAdminIdStr());

        Map<String, Object> resData = new LinkedHashMap<>();
        resData.put("order_no", order.getOrder_no());
        resData.put("number_of_diners", diners);
        resData.put("previous_diners", previousDiners);
        resData.put("table_number", order.getTable_number());
        resData.put("amount", order.getSett_amount());

        return R.ok("修改用餐人数成功")
                .put("code", 200)
                .put("order_no", order.getOrder_no())
                .put("number_of_diners", diners)
                .put("previous_diners", previousDiners)
                .put("data", resData);
    }

    @PutMapping({"/orders/{orderNo}/diners", "/{orderNo}/diners", "/order/{orderNo}/diners"})
    @AuditLog(module = "pos", action = "pos_update_diners", target = "#p0")
    public R putOrderDiners(@PathVariable("orderNo") String orderNo,
                            @RequestBody Map<String, Object> body) {
        Map<String, Object> reqBody = new LinkedHashMap<>();
        if (body != null) {
            reqBody.putAll(body);
        }
        reqBody.put("order_no", orderNo);
        return executeClientRequest("/api/pos/orders/" + orderNo + "/diners", reqBody, () -> updateDinersInternal(reqBody));
    }

    private void adjustTeaFeeForDiners(Order order, int oldDiners, int newDiners) {
        if (order == null || oldDiners == newDiners) return;
        int delta = newDiners - oldDiners;
        Integer shopId = order.getShop_id();

        boolean teaFeeEnabled = false;
        double unitPrice = 2.0;
        String feeName = "餐位茶位费";

        if (systemConfigMapper != null && shopId != null) {
            com.lanf.entity.SystemConfig cfgEnabled = systemConfigMapper.selectOne(new QueryWrapper<com.lanf.entity.SystemConfig>()
                    .eq("shop_id", shopId).eq("config_key", "tea_fee_enabled"));
            if (cfgEnabled == null) {
                cfgEnabled = systemConfigMapper.selectOne(new QueryWrapper<com.lanf.entity.SystemConfig>()
                        .eq("shop_id", 0).eq("config_key", "tea_fee_enabled"));
            }
            if (cfgEnabled != null && ("1".equals(cfgEnabled.getConfig_value()) || "true".equalsIgnoreCase(cfgEnabled.getConfig_value()))) {
                teaFeeEnabled = true;
            }
            com.lanf.entity.SystemConfig cfgPrice = systemConfigMapper.selectOne(new QueryWrapper<com.lanf.entity.SystemConfig>()
                    .eq("shop_id", shopId).eq("config_key", "tea_fee_per_person"));
            if (cfgPrice == null) {
                cfgPrice = systemConfigMapper.selectOne(new QueryWrapper<com.lanf.entity.SystemConfig>()
                        .eq("shop_id", 0).eq("config_key", "tea_fee_per_person"));
            }
            if (cfgPrice != null && cfgPrice.getConfig_value() != null) {
                try {
                    unitPrice = Double.parseDouble(cfgPrice.getConfig_value().trim());
                } catch (Exception ignored) {}
            }
            com.lanf.entity.SystemConfig cfgName = systemConfigMapper.selectOne(new QueryWrapper<com.lanf.entity.SystemConfig>()
                    .eq("shop_id", shopId).eq("config_key", "tea_fee_name"));
            if (cfgName != null && cfgName.getConfig_value() != null && !cfgName.getConfig_value().trim().isEmpty()) {
                feeName = cfgName.getConfig_value().trim();
            }
        }

        List<OrderDetail> details = orderDetailService.list(new QueryWrapper<OrderDetail>()
                .eq("mId", order.getId()));
        OrderDetail teaDetail = null;
        if (details != null) {
            for (OrderDetail d : details) {
                if (d.getName() != null && (d.getName().contains("茶位") || d.getName().contains("餐位") || d.getName().contains("餐具")
                        || "tea_fee".equalsIgnoreCase(d.getLine_type()))) {
                    teaDetail = d;
                    teaFeeEnabled = true;
                    if (d.getTotal_price() != null && d.getQuantity() != null) {
                        try {
                            int q = Integer.parseInt(d.getQuantity().trim());
                            if (q > 0) {
                                unitPrice = Math.round((d.getTotal_price() / q) * 100.0) / 100.0;
                            }
                        } catch (Exception ignored) {}
                    }
                    if (d.getName() != null) {
                        feeName = d.getName();
                    }
                    break;
                }
            }
        }

        if (!teaFeeEnabled) {
            return;
        }

        if (!"unsettled".equalsIgnoreCase(order.getTransac_status())) {
            return;
        }

        double priceDiff = 0.0;
        if (delta > 0) {
            if (teaDetail != null && !"refunded".equalsIgnoreCase(teaDetail.getLine_status())) {
                int oldQ = 0;
                try { oldQ = Integer.parseInt(teaDetail.getQuantity().trim()); } catch (Exception ignored) {}
                int newQ = oldQ + delta;
                teaDetail.setQuantity(String.valueOf(newQ));
                double newTotal = Math.round(newQ * unitPrice * 100.0) / 100.0;
                priceDiff = Math.round((newTotal - (teaDetail.getTotal_price() != null ? teaDetail.getTotal_price() : 0.0)) * 100.0) / 100.0;
                teaDetail.setTotal_price(newTotal);
                orderDetailService.updateById(teaDetail);
            } else {
                OrderDetail newDetail = new OrderDetail();
                newDetail.setMId(order.getId());
                newDetail.setMorder_no(order.getOrder_no());
                newDetail.setName(feeName);
                newDetail.setQuantity(String.valueOf(delta));
                newDetail.setUnit("位");
                double newTotal = Math.round(delta * unitPrice * 100.0) / 100.0;
                newDetail.setTotal_price(newTotal);
                newDetail.setLine_status("normal");
                newDetail.setLine_type("tea_fee");
                orderDetailService.save(newDetail);
                priceDiff = newTotal;
            }
        } else {
            int reduceCount = Math.abs(delta);
            if (teaDetail != null) {
                int currQ = 0;
                try { currQ = Integer.parseInt(teaDetail.getQuantity().trim()); } catch (Exception ignored) {}
                int newQ = Math.max(0, currQ - reduceCount);
                int actualReduced = currQ - newQ;
                double newTotal = Math.round(newQ * unitPrice * 100.0) / 100.0;
                priceDiff = -Math.round(actualReduced * unitPrice * 100.0) / 100.0;
                teaDetail.setQuantity(String.valueOf(newQ));
                teaDetail.setTotal_price(newTotal);
                if (newQ == 0) {
                    teaDetail.setLine_status("refunded");
                }
                orderDetailService.updateById(teaDetail);
            }
        }

        if (priceDiff != 0.0) {
            double currentSett = order.getSett_amount() != null ? order.getSett_amount() : 0.0;
            double nextSett = Math.max(0.0, Math.round((currentSett + priceDiff) * 100.0) / 100.0);
            order.setSett_amount(nextSett);
            orderService.updateById(order);

            if (order.getTable_number() != null && shopId != null) {
                Table table = tableService.getOne(new QueryWrapper<Table>()
                        .eq("shop_id", shopId).eq("number", order.getTable_number()));
                if (table != null && Integer.valueOf(1).equals(table.getStatus())) {
                    table.setAmount(nextSett);
                    tableService.updateById(table);
                }
            }
            logOrder(order.getOrder_no(), "tea_fee_adjust", "amount_diff", String.valueOf(priceDiff));
        }
    }

    @GetMapping("/today")
    public R today(@RequestParam(required = false) Integer shopId,
                   @RequestParam(required = false) String transac_status,
                   @RequestParam(required = false) String date,
                   @RequestParam(required = false) String startTime,
                   @RequestParam(required = false) String endTime) {
        Integer resolvedShopId = AdminShopRequest.getResolvedShopId(request);
        if (resolvedShopId == null) {
            return R.error(4001, "缺少门店上下文");
        }
        if (shopId != null && !shopId.equals(resolvedShopId)) {
            return R.error(4003, "无权访问其他门店订单");
        }
        boolean hasDate = hasText(date);
        boolean hasStart = hasText(startTime);
        boolean hasEnd = hasText(endTime);
        boolean customTimeRequested = hasDate || hasStart || hasEnd;
        if (customTimeRequested && !hasBillCustomRangePermission()) {
            return R.error(403, "无权限：admin:super");
        }

        QueryWrapper<Order> q = new QueryWrapper<Order>().eq("shop_id", resolvedShopId);
        if (!customTimeRequested) {
            LocalDateTime now = LocalDateTime.now(BUSINESS_ZONE);
            Date cutoff = Date.from(now.minusHours(BILL_RECENT_HOURS).atZone(BUSINESS_ZONE).toInstant());
            Date current = Date.from(now.atZone(BUSINESS_ZONE).toInstant());
            q.and(w -> w.eq("transac_status", "unsettled")
                    .or(pw -> pw.ge("order_time", cutoff).le("order_time", current)));
        } else if (hasDate) {
            if (hasStart || hasEnd) {
                return R.error(4002, "date 不能与 startTime/endTime 同时使用");
            }
            Shop shop = shopService.getById(resolvedShopId);
            Date[] win;
            try {
                win = ShopBusinessWindowResolver.resolveOperationalWindow(shop, date.trim());
            } catch (IllegalArgumentException e) {
                return R.error(4002, "date 格式错误，应为 yyyy-MM-dd");
            }
            q.and(w -> w.ge("order_time", win[0]).lt("order_time", win[1])
                    .or(pw -> pw.ge("pay_time", win[0]).lt("pay_time", win[1])));
        } else {
            if (!hasStart || !hasEnd) {
                return R.error(4002, "startTime 与 endTime 必须同时提供");
            }
            Shop shop = shopService != null ? shopService.getById(resolvedShopId) : null;
            LocalTime settleTime = ShopBusinessWindowResolver.resolveSettleTimeOrDefault(shop);
            OrderListTimeRangeResolver.Range range;
            try {
                range = OrderListTimeRangeResolver.resolve(
                        LocalDateTime.now(BUSINESS_ZONE), startTime, endTime, settleTime);
            } catch (IllegalArgumentException e) {
                return R.error(4002, "时间格式错误或 endTime 早于 startTime");
            }
            if (Duration.between(range.getStart(), range.getEnd())
                    .compareTo(Duration.ofDays(BILL_CUSTOM_RANGE_MAX_DAYS)) > 0) {
                return R.error(4002, "自定义时间范围不能超过31天");
            }
            Date start = Date.from(range.getStart().atZone(BUSINESS_ZONE).toInstant());
            Date end = Date.from(range.getEnd().atZone(BUSINESS_ZONE).toInstant());
            if (range.isEndPureDate()) {
                q.and(w -> w.ge("order_time", start).lt("order_time", end)
                        .or(pw -> pw.ge("pay_time", start).lt("pay_time", end)));
            } else {
                q.and(w -> w.ge("order_time", start).le("order_time", end)
                        .or(pw -> pw.ge("pay_time", start).le("pay_time", end)));
            }
        }
        if (transac_status != null && !transac_status.isEmpty()) {
            q.eq("transac_status", transac_status);
        }
        q.orderByDesc("order_time");
        List<Order> list = orderService.list(q);
        if (adminService != null) {
            AdminNameResolver.enrichOrdersCashierInfo(list, adminService);
        }
        return R.ok().put("list", list);
    }

    /** 保留控制器单元测试及内部调用的旧签名；HTTP 契约由五参数方法提供。 */
    R today(Integer shopId, String transacStatus, String date) {
        return today(shopId, transacStatus, date, null, null);
    }

    private boolean hasBillCustomRangePermission() {
        Object value = request != null ? request.getAttribute(SysInterceptor.ATTR_ADMIN_ID) : null;
        if (!(value instanceof Integer) || adminPermissionService == null) {
            return false;
        }
        try {
            Set<String> permissions = adminPermissionService.getPermissionCodesByAdminId((Integer) value);
            return permissions != null && permissions.contains(BILL_CUSTOM_RANGE_PERMISSION);
        } catch (RuntimeException ignored) {
            return false;
        }
    }

    private static boolean hasText(String value) {
        return value != null && !value.trim().isEmpty();
    }

    @GetMapping("/search")
    public R search(@RequestParam(required = false) String tableNumber,
                    @RequestParam(required = false) String startTime,
                    @RequestParam(required = false) String endTime,
                    @RequestParam(required = false) Integer cashierId,
                    @RequestParam(required = false) Integer pageNum,
                    @RequestParam(required = false) Integer pageSize) {
        Integer resolvedShopId = AdminShopRequest.getResolvedShopId(request);
        if (resolvedShopId == null) {
            return R.error(4001, "缺少门店上下文");
        }
        QueryWrapper<Order> q = new QueryWrapper<>();
        q.eq("shop_id", resolvedShopId);
        if (tableNumber != null && !tableNumber.isEmpty()) {
            q.eq("table_number", tableNumber);
        }
        if (cashierId != null && cashierId > 0) {
            q.and(w -> w.eq("cashier_id", cashierId).or(w2 -> w2.isNull("cashier_id").eq("order_admin_id", cashierId)));
        }
        Shop shop = shopService != null ? shopService.getById(resolvedShopId) : null;
        LocalTime settleTime = ShopBusinessWindowResolver.resolveSettleTimeOrDefault(shop);
        if (hasText(startTime) && hasText(endTime)) {
            try {
                OrderListTimeRangeResolver.Range range = OrderListTimeRangeResolver.resolve(
                        LocalDateTime.now(BUSINESS_ZONE), startTime, endTime, settleTime);
                Date startDate = Date.from(range.getStart().atZone(BUSINESS_ZONE).toInstant());
                Date endDate = Date.from(range.getEnd().atZone(BUSINESS_ZONE).toInstant());
                if (range.isEndPureDate()) {
                    q.and(w -> w.ge("order_time", startDate).lt("order_time", endDate)
                            .or(pw -> pw.ge("pay_time", startDate).lt("pay_time", endDate)));
                } else {
                    q.and(w -> w.ge("order_time", startDate).le("order_time", endDate)
                            .or(pw -> pw.ge("pay_time", startDate).le("pay_time", endDate)));
                }
            } catch (IllegalArgumentException ex) {
                return R.error(4002, "时间格式错误: " + ex.getMessage());
            }
        } else if (hasText(startTime)) {
            try {
                LocalDateTime s = OrderListTimeRangeResolver.parseDateTime(startTime, true, settleTime);
                Date startDate = Date.from(s.atZone(BUSINESS_ZONE).toInstant());
                q.ge("order_time", startDate);
            } catch (IllegalArgumentException ex) {
                return R.error(4002, "时间格式错误: " + ex.getMessage());
            }
        } else if (hasText(endTime)) {
            try {
                boolean isPure = OrderListTimeRangeResolver.isPureDate(endTime);
                LocalDateTime e = OrderListTimeRangeResolver.parseDateTime(endTime, false, settleTime);
                Date endDate = Date.from(e.atZone(BUSINESS_ZONE).toInstant());
                if (isPure) {
                    q.lt("order_time", endDate);
                } else {
                    q.le("order_time", endDate);
                }
            } catch (IllegalArgumentException ex) {
                return R.error(4002, "时间格式错误: " + ex.getMessage());
            }
        }
        q.orderByDesc("order_time");
        int pn = pageNum != null && pageNum > 0 ? pageNum : 1;
        int ps = pageSize != null && pageSize > 0 ? Math.min(pageSize, 100) : 20;
        IPage<Order> page = orderService.page(new Page<>(pn, ps), q);
        if (adminService != null) {
            AdminNameResolver.enrichOrdersCashierInfo(page.getRecords(), adminService);
        }
        return R.ok().put("list", page.getRecords()).put("total", page.getTotal());
    }

    @GetMapping("/printContent")
    public R printContent(@RequestParam Integer orderId,
                          @RequestParam(required = false, defaultValue = "false") Boolean type) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null) {
            return R.error(4001, "缺少门店上下文");
        }
        R result = orderController.printContentForCashier(orderId, type, shopId);
        if (Integer.valueOf(0).equals(result.get("code")) && result.get("order_no") != null) {
            logOrder(result.get("order_no").toString(), "print_content", "admin_id", getAdminIdStr());
        }
        return result;
    }

    private void recalcSettFromActiveDetails(Order order) {
        QueryWrapper<OrderDetail> q = new QueryWrapper<OrderDetail>().eq("mId", order.getId());
        OrderDetailQueryHelper.onlyActive(q);
        List<OrderDetail> details = orderDetailService.list(q);
        double newSett = details.stream().mapToDouble(d -> d.getTotal_price() != null ? d.getTotal_price() : 0).sum();
        newSett = Math.round(newSett * 100) / 100.0;
        order.setSett_amount(newSett);
        double fee = serviceFeeConfig.isServiceFeeCharged() ? Math.round(newSett * 0.05 * 100) / 100.0 : 0d;
        order.setService_fee(fee);
        if (!orderService.updateById(order)) {
            throw new IllegalStateException("订单金额更新失败");
        }
        if ("堂食".equals(order.getDineInOrTakeOut()) && order.getTable_number() != null) {
            QueryWrapper<Table> tableQuery = new QueryWrapper<Table>().eq("number", order.getTable_number());
            if (order.getShop_id() != null) tableQuery.eq("shop_id", order.getShop_id());
            Table table = tableService.getOne(tableQuery.last("LIMIT 1"));
            if (table != null) {
                List<Order> unsettled = orderService.list(new QueryWrapper<Order>()
                        .eq("shop_id", order.getShop_id())
                        .eq("table_number", order.getTable_number())
                        .eq("transac_status", "unsettled"));
                table.setAmount(sumOutstanding(unsettled));
                if (!tableService.updateById(table)) {
                    throw new IllegalStateException("桌台金额更新失败");
                }
            }
        }
    }

    private static double sumOutstanding(List<Order> orders) {
        double total = 0d;
        if (orders != null) {
            for (Order item : orders) {
                if (item != null && "unsettled".equals(item.getTransac_status())) {
                    total += OrderNetRevenue.netRevenueYuan(item);
                }
            }
        }
        return Math.round(Math.max(0d, total) * 100d) / 100d;
    }

    private void logOrder(String orderNo, String action, String operatorType, String operatorId) {
        if (orderLogService == null || orderNo == null) {
            return;
        }
        OrderLog log = new OrderLog();
        log.setOrder_no(orderNo);
        log.setAction(action);
        log.setOperator_type(operatorType);
        log.setOperator_id(operatorId);
        log.setShop_id(request == null ? null : AdminShopRequest.getResolvedShopId(request));
        orderLogService.save(log);
    }

    private String getAdminIdStr() {
        Object id = request != null ? request.getAttribute(com.lanf.interceptor.SysInterceptor.ATTR_ADMIN_ID) : null;
        return id != null ? id.toString() : null;
    }

    private String getSensitiveAuthorizedAdminIdStr() {
        Object id = request != null ? request.getAttribute(SENSITIVE_AUTHORIZED_ADMIN_ID) : null;
        return id != null ? id.toString() : null;
    }

    private R authorizeHighRiskAction(Map<String, Object> body,
                                      String requiredPermission,
                                      String resourceId,
                                      BigDecimal amount,
                                      String orderStatus) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null) {
            return R.error(4001, "缺少门店上下文");
        }
        Integer operatorId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        String terminalId = request.getHeader("X-Terminal-Id");
        if (!StringUtils.hasText(terminalId)) {
            terminalId = bodyText(body, "terminalId", "terminal_id");
        }
        String requestId = request.getHeader("X-Client-Request-Id");
        if (!StringUtils.hasText(requestId)) {
            requestId = bodyText(body, "requestId", "request_id");
        }
        HighRiskActionAuthorizationService.Result result = highRiskActionAuthorizationService.authorize(
                HighRiskActionAuthorizationService.Request.builder()
                        .body(body)
                        .operatorId(operatorId)
                        .shopId(shopId)
                        .permissionCode(requiredPermission)
                        .resourceType("ORDER")
                        .resourceId(resourceId)
                        .amount(amount)
                        .discountRate(bodyDecimal(body, "payRate", "pay_rate", "discountRate", "discount_rate"))
                        .orderStatus(orderStatus)
                        .terminalId(terminalId)
                        .requestId(requestId)
                        .build());
        if (!result.isAllowed()) {
            AccessDecision decision = result.getDecision();
            R error = R.error(result.getCode(), decision != null
                    ? decision.getExplanation() : "高风险操作授权失败");
            if (decision != null) {
                error.put("outcome", decision.getOutcome() != null ? decision.getOutcome().name() : "DENY")
                        .put("reasonCode", decision.getReasonCode());
                if (decision.getApproval() != null) {
                    error.put("approval", decision.getApproval());
                }
            }
            return error;
        }
        request.setAttribute(SENSITIVE_AUTHORIZED_ADMIN_ID, result.getAuthorizedAdminId());
        return null;
    }

    private static BigDecimal bodyDecimal(Map<String, Object> body, String... keys) {
        Object value = firstBodyValue(body, keys);
        if (value == null || !StringUtils.hasText(String.valueOf(value))) {
            return null;
        }
        try {
            return new BigDecimal(String.valueOf(value).trim());
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    private static BigDecimal resolveCashRefundAmount(Order order, Map<String, Object> body) {
        BigDecimal requested = bodyDecimal(body, "refundAmount", "refund_amount");
        if (requested != null) {
            return requested;
        }
        long totalFen = Math.round((nz(order.getSett_amount()) + nz(order.getService_fee())
                - nz(order.getDiscount_amount())) * 100d);
        long remainingFen = Math.max(0L, totalFen - Math.round(nz(order.getRefund_amount()) * 100d));
        long cashRemainingFen = Math.max(0L, Math.round(nz(order.getPay_amount_cash()) * 100d));
        return BigDecimal.valueOf(Math.min(remainingFen, cashRemainingFen), 2);
    }

    private static double nz(Double value) {
        return value == null ? 0d : value;
    }
}

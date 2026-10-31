package com.lanf.controller.cashier;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.dto.CashierTableOperationRequest;
import com.lanf.dto.CashierTableOperationResult;
import com.lanf.entity.R;
import com.lanf.entity.Table;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.ITableService;
import com.lanf.service.impl.CashierTableOperationService;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import javax.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/** Cashier table operations, strictly scoped to the active shop. */
@RestController
@RequestMapping({"/cashier/table", "/api/pos/tables", "/api/pos"})
public class CashierTableController {

    @Autowired
    private ITableService tableService;
    @Autowired
    private CashierTableOperationService tableOperationService;
    @Autowired
    private com.lanf.service.IOrderService orderService;
    @Autowired
    private com.lanf.service.CashierCheckoutService cashierCheckoutService;
    @Autowired
    private HttpServletRequest request;

    @PostMapping("/open")
    public R open(@RequestBody Map<String, Object> body) {
        return execute("OPEN", text(first(body, "tableNumber", "table_number", "number")), null, body);
    }

    @PostMapping("/merge")
    public R merge(@RequestBody Map<String, Object> body) {
        String source = text(first(body, "sourceTableNumber", "source_table_number", "source"));
        String target = text(first(body, "targetTableNumber", "target_table_number", "target"));
        return execute("MERGE", source, target, body);
    }

    @PostMapping("/transfer")
    public R transfer(@RequestBody Map<String, Object> body) {
        String orderNo = text(first(body, "orderNo", "order_no"));
        String target = text(first(body, "targetTableNumber", "target_table_number", "target"));
        if (orderNo == null || target == null) return R.error("订单号与目标桌号不能为空");
        return execute("TRANSFER", null, target, orderNo, body);
    }

    @PostMapping("/clear")
    public R clear(@RequestBody Map<String, Object> body) {
        String number = text(first(body, "tableNumber", "table_number", "number"));
        return execute("CLEAR", number, null, body);
    }

    @PostMapping("/checkout")
    @Transactional(rollbackFor = Exception.class)
    public R checkout(@RequestBody Map<String, Object> body) {
        Integer shopId = currentShopId();
        if (shopId == null) return R.error(4001, "缺少门店上下文");
        String tableNumber = text(first(body, "tableNumber", "table_number", "number"));
        if (!StringUtils.hasText(tableNumber)) {
            return R.error("桌号不能为空");
        }
        Table table = tableService.getOne(new QueryWrapper<Table>()
                .eq("shop_id", shopId).eq("number", tableNumber));
        if (table == null) {
            return R.error("桌台不存在");
        }

        List<com.lanf.entity.Order> unsettledOrders = orderService.list(new QueryWrapper<com.lanf.entity.Order>()
                .eq("shop_id", shopId)
                .eq("table_number", tableNumber)
                .eq("transac_status", "unsettled")
                .orderByAsc("id"));
        if (unsettledOrders == null || unsettledOrders.isEmpty()) {
            return R.error("该桌台暂无待结账订单");
        }

        boolean force = cashierCheckoutService.isForceCheckout(body);
        Integer[] authorizedAdminId = new Integer[1];
        if (force) {
            R permError = cashierCheckoutService.checkForceCheckoutPermission(shopId, body, authorizedAdminId);
            if (permError != null) {
                return permError;
            }
        }

        String paymentMethod = text(first(body, "paymentMethod", "payment_method"));
        if (!StringUtils.hasText(paymentMethod)) {
            paymentMethod = "cash";
        }
        Double cashAmount = null;
        Object rawCash = first(body, "cashAmount", "cash_amount", "checkoutCashAmount", "checkout_cash_amount");
        if (rawCash instanceof Number) {
            cashAmount = ((Number) rawCash).doubleValue();
        } else if (rawCash instanceof String && StringUtils.hasText((String) rawCash)) {
            try {
                cashAmount = Double.parseDouble(((String) rawCash).trim());
            } catch (NumberFormatException ignored) {}
        }

        double totalPayable = 0d;
        for (com.lanf.entity.Order o : unsettledOrders) {
            totalPayable += com.lanf.util.OrderNetRevenue.netRevenueYuan(o);
        }
        totalPayable = Math.round(totalPayable * 100d) / 100d;

        if (cashAmount != null && cashAmount < totalPayable) {
            return R.error("实收现金金额不足，总应付：" + totalPayable + " 元");
        }

        List<String> settledOrderNos = new ArrayList<>();
        double settledTotal = 0d;
        for (int i = 0; i < unsettledOrders.size(); i++) {
            com.lanf.entity.Order o = unsettledOrders.get(i);
            Map<String, Object> orderCheckoutBody = new LinkedHashMap<>();
            if (body != null) {
                orderCheckoutBody.putAll(body);
            }
            orderCheckoutBody.put("order_no", o.getOrder_no());
            orderCheckoutBody.put("payment_method", paymentMethod);
            orderCheckoutBody.put("allowSlaveOrderCheckout", Boolean.TRUE);
            orderCheckoutBody.put("table_checkout", Boolean.TRUE);
            if (force) {
                orderCheckoutBody.put("_forcePreAuthorized", Boolean.TRUE);
                orderCheckoutBody.put("_authorizedAdminId", authorizedAdminId[0]);
            }
            if (cashAmount != null) {
                if (i == unsettledOrders.size() - 1) {
                    double prevPaid = totalPayable - com.lanf.util.OrderNetRevenue.netRevenueYuan(o);
                    double lastCash = Math.round((cashAmount - prevPaid) * 100d) / 100d;
                    orderCheckoutBody.put("cash_amount", lastCash);
                } else {
                    orderCheckoutBody.put("cash_amount", com.lanf.util.OrderNetRevenue.netRevenueYuan(o));
                }
            }
            R res = cashierCheckoutService.checkout(shopId, orderCheckoutBody);
            if (!Integer.valueOf(0).equals(res.get("code"))) {
                org.springframework.transaction.interceptor.TransactionAspectSupport.currentTransactionStatus().setRollbackOnly();
                return res;
            }
            settledOrderNos.add(o.getOrder_no());
            settledTotal += com.lanf.util.OrderNetRevenue.netRevenueYuan(o);
        }

        double changeAmount = cashAmount != null ? Math.round((cashAmount - totalPayable) * 100d) / 100d : 0d;
        Table latestTable = tableService.getOne(new QueryWrapper<Table>()
                .eq("shop_id", shopId).eq("number", tableNumber));

        R response = R.ok("整桌结账成功")
                .put("tableNumber", tableNumber)
                .put("settledOrders", settledOrderNos)
                .put("totalAmount", Math.round(settledTotal * 100d) / 100d)
                .put("cashAmount", cashAmount)
                .put("changeAmount", changeAmount)
                .put("table", latestTable);
        if (force) {
            response.put("forced", true);
        }
        return response;
    }

    @GetMapping("/statusMap")
    public R statusMap(@RequestParam(required = false) Integer shopId) {
        Integer resolved = currentShopId();
        if (resolved == null) return R.error(4001, "缺少门店上下文");
        List<Table> list = tableService.list(new QueryWrapper<Table>()
                .eq("shop_id", resolved).orderByAsc("number"));
        Map<String, Integer> map = list.stream().collect(
                Collectors.toMap(Table::getNumber, Table::getStatus, (a, b) -> a));
        return R.ok().put("map", map).put("list", list);
    }

    @GetMapping({"/areas", "/table-areas", "/tables/areas"})
    public R tableAreas() {
        Integer shopId = currentShopId();
        if (shopId == null) return R.error(4001, "缺少门店上下文");

        List<Map<String, Object>> areas = new ArrayList<>();
        Map<String, Object> hall = new LinkedHashMap<>();
        hall.put("code", "hall");
        hall.put("name", "大厅散座");
        hall.put("sort", 1);
        areas.add(hall);

        Map<String, Object> box = new LinkedHashMap<>();
        box.put("code", "box");
        box.put("name", "特色包厢");
        box.put("sort", 2);
        areas.add(box);

        Map<String, Object> patio = new LinkedHashMap<>();
        patio.put("code", "patio");
        patio.put("name", "露天外摆");
        patio.put("sort", 3);
        areas.add(patio);

        return R.ok("success").put("code", 200).put("data", areas);
    }

    @PostMapping({"/batch-clear", "/tables/batch-clear"})
    public R batchClear(@RequestBody Map<String, Object> body) {
        Integer shopId = currentShopId();
        if (shopId == null) return R.error(4001, "缺少门店上下文");

        List<Integer> tableIds = extractIntegerList(body, "table_ids", "tableIds", "ids");
        List<String> tableNumbers = extractStringList(body, "table_numbers", "tableNumbers", "numbers");
        String operatorAccount = text(first(body, "operator_account", "operatorAccount", "operator"));

        if ((tableIds == null || tableIds.isEmpty()) && (tableNumbers == null || tableNumbers.isEmpty())) {
            return R.error(400, "table_ids 与 table_numbers 至少提供一项");
        }

        QueryWrapper<Table> qw = new QueryWrapper<Table>().eq("shop_id", shopId);
        if (tableIds != null && !tableIds.isEmpty()) {
            qw.in("id", tableIds);
        } else {
            qw.in("number", tableNumbers);
        }
        List<Table> tables = tableService.list(qw);

        Object operator = request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        Integer operatorId = operator instanceof Integer ? (Integer) operator : null;
        String traceId = text(request.getAttribute(SysInterceptor.ATTR_TRACE_ID));

        Map<String, Object> res = tableOperationService.batchClear(shopId, tables, operatorId, operatorAccount, traceId);

        R response = R.ok("批量清台成功");
        response.put("code", 200);
        response.put("data", res);
        return response;
    }

    @GetMapping({"/pulse", "/tables/pulse"})
    public R pulse() {
        Integer shopId = currentShopId();
        if (shopId == null) return R.error(4001, "缺少门店上下文");

        List<Table> list = tableService.list(new QueryWrapper<Table>()
                .eq("shop_id", shopId));
        int totalTables = list.size();
        int activeDiningCount = 0;
        int pendingClearCount = 0;
        double totalSeatedAmount = 0.0;

        for (Table t : list) {
            Integer status = t.getStatus();
            if (status != null && status == 1) {
                activeDiningCount++;
                if (t.getAmount() != null && t.getAmount() > 0) {
                    totalSeatedAmount += t.getAmount();
                }
            } else if (status != null && status == 2) {
                pendingClearCount++;
            }
        }
        totalSeatedAmount = Math.round(totalSeatedAmount * 100.0) / 100.0;

        double occupancyRate = totalTables > 0 ? (double) activeDiningCount / totalTables : 0.0;
        double occupancyRatePercent = Math.round(occupancyRate * 1000.0) / 10.0;

        Map<String, Object> data = new LinkedHashMap<>();
        data.put("occupancy_rate", Math.round(occupancyRate * 10000.0) / 10000.0);
        data.put("occupancy_rate_percent", occupancyRatePercent);
        data.put("active_dining_count", activeDiningCount);
        data.put("total_tables", totalTables);
        data.put("available_table_count", totalTables);
        data.put("total_seated_amount", totalSeatedAmount);
        data.put("pending_clear_count", pendingClearCount);

        R response = R.ok("success");
        response.put("code", 200);
        response.put("data", data);
        return response;
    }

    private Integer currentShopId() {
        return AdminShopRequest.getResolvedShopId(request);
    }

    private R execute(String action, String source, String target, Map<String, Object> body) {
        return execute(action, source, target, null, body);
    }

    private R execute(String action, String source, String target, String orderNo, Map<String, Object> body) {
        Integer shopId = currentShopId();
        if (shopId == null) return R.error(4001, "缺少门店上下文");
        CashierTableOperationRequest command = new CashierTableOperationRequest();
        command.setAction(action);
        command.setShopId(shopId);
        Object operator = request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        command.setOperatorId(operator instanceof Integer ? (Integer) operator : null);
        command.setSourceTable(source);
        command.setTargetTable(target);
        command.setOrderNo(orderNo);
        command.setTraceId(text(request.getAttribute(SysInterceptor.ATTR_TRACE_ID)));
        command.setRequestKey(firstText(
                text(first(body, "idempotencyKey", "idempotency_key", "requestId", "request_id")),
                text(request.getHeader("Idempotency-Key")), text(request.getHeader("X-Request-ID")),
                command.getTraceId()));
        command.setIp(request.getRemoteAddr());
        CashierTableOperationResult result = tableOperationService.execute(command);
        R response = result.isSuccess() ? R.ok(result.getMessage()) : R.error(result.getCode(), result.getMessage());
        response.put("action", action.toLowerCase(java.util.Locale.ROOT));
        response.put("idempotent", result.isIdempotent());
        response.put("requestId", command.getRequestKey());
        response.put("traceId", command.getTraceId());
        if (result.getTable() != null) response.put("table", result.getTable());
        return response;
    }

    private static List<Integer> extractIntegerList(Map<String, Object> body, String... keys) {
        Object val = first(body, keys);
        if (val instanceof List) {
            List<?> list = (List<?>) val;
            List<Integer> res = new ArrayList<>();
            for (Object o : list) {
                if (o instanceof Number) {
                    res.add(((Number) o).intValue());
                } else if (o instanceof String && StringUtils.hasText((String) o)) {
                    try {
                        res.add(Integer.parseInt(((String) o).trim()));
                    } catch (NumberFormatException ignored) {}
                }
            }
            return res;
        }
        return null;
    }

    private static List<String> extractStringList(Map<String, Object> body, String... keys) {
        Object val = first(body, keys);
        if (val instanceof List) {
            List<?> list = (List<?>) val;
            List<String> res = new ArrayList<>();
            for (Object o : list) {
                if (o != null && StringUtils.hasText(o.toString())) {
                    res.add(o.toString().trim());
                }
            }
            return res;
        }
        return null;
    }

    private static Object first(Map<String, Object> body, String... keys) {
        if (body == null) return null;
        for (String key : keys) {
            if (body.containsKey(key) && text(body.get(key)) != null) return body.get(key);
        }
        return null;
    }

    private static String text(Object value) {
        if (value == null) return null;
        String text = value.toString().trim();
        return text.isEmpty() ? null : text;
    }

    private static String firstText(String... values) {
        for (String value : values) if (value != null) return value;
        return null;
    }
}

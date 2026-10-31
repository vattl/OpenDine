package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.order.OrderDetailLineStatus;
import com.lanf.payment.support.PaymentDiningTypeUtil;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 待传菜划单后打印传菜单（飞鹅），按订单明细行逐条打印（每条明细一张）。
 */
@Service
public class KdsServePrintService {

    private static final Logger log = LoggerFactory.getLogger(KdsServePrintService.class);
    private static final ObjectMapper SPEC_MAPPER = new ObjectMapper();

    @Autowired
    private IOrderService orderService;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private com.lanf.printing.service.PrintDispatcherService printDispatcherService;
    @Autowired
    private KdsConfigService configService;
    @Autowired
    private JdbcTemplate jdbc;

    public static final class ServeLine {
        public final int detailId;
        public final int quantity;
        public final long transitionVersion;

        public ServeLine(int detailId, int quantity) {
            this(detailId, quantity, 0);
        }

        public ServeLine(int detailId, int quantity, long transitionVersion) {
            this.detailId = detailId;
            this.quantity = quantity;
            this.transitionVersion = transitionVersion;
        }
    }

    public void printDetailLine(int shopId, int detailId, int quantity) {
        if (quantity <= 0 || shopId <= 0) {
            return;
        }
        schedulePrint(shopId, Collections.singletonList(new ServeLine(detailId, quantity)));
    }

    public void printDetailLine(int shopId, int detailId, int quantity, long transitionVersion) {
        if (quantity <= 0 || transitionVersion <= 0 || shopId <= 0) return;
        schedulePrint(shopId, Collections.singletonList(
                new ServeLine(detailId, quantity, transitionVersion)));
    }

    public void printByDetails(int shopId, List<ServeLine> lines) {
        schedulePrint(shopId, lines);
    }

    /**
     * 手动触发/补打传菜单接口调用（同步执行并返回打印详情）
     */
    public Map<String, Object> printManual(int shopId, Integer orderId, Integer detailId, Integer quantity, List<Map<String, Object>> rawLines) {
        if (configService != null && !configService.isServePrintEnabled(shopId)) {
            throw new IllegalStateException("当前门店待传菜打印功能未启用(serve_print_enabled=0)");
        }
        List<ServeLine> lines = new ArrayList<>();
        if (rawLines != null && !rawLines.isEmpty()) {
            for (Map<String, Object> m : rawLines) {
                if (m == null) continue;
                Integer did = asInt(m.get("detail_id"), m.get("detailId"), m.get("id"));
                Integer qty = asInt(m.get("quantity"), m.get("qty"));
                if (did != null && did > 0) {
                    lines.add(new ServeLine(did, qty != null && qty > 0 ? qty : 1));
                }
            }
        } else if (detailId != null && detailId > 0) {
            int q = quantity != null && quantity > 0 ? quantity : 1;
            lines.add(new ServeLine(detailId, q));
        } else if (orderId != null && orderId > 0) {
            Order order = orderService.getById(orderId);
            if (order == null || order.getShop_id() == null || !order.getShop_id().equals(shopId)) {
                throw new IllegalArgumentException("订单不存在或不属于当前门店");
            }
            List<OrderDetail> details = orderDetailService.list(new QueryWrapper<OrderDetail>().eq("mId", orderId));
            for (OrderDetail d : details) {
                if (d != null && !OrderDetailLineStatus.isRefunded(d.getLine_status())) {
                    int q = parseQty(d.getQuantity());
                    lines.add(new ServeLine(d.getId(), q > 0 ? q : 1));
                }
            }
        }
        if (lines.isEmpty()) {
            throw new IllegalArgumentException("未找到可打印的有效菜品明细");
        }
        int printedCount = 0;
        List<Map<String, Object>> printedLines = new ArrayList<>();
        Map<Integer, Integer> qtyByDetail = mergeQuantities(lines);
        for (Map.Entry<Integer, Integer> e : qtyByDetail.entrySet()) {
            OrderDetail detail = orderDetailService.getById(e.getKey());
            if (detail == null || OrderDetailLineStatus.isRefunded(detail.getLine_status())) {
                continue;
            }
            if (detail.getMId() == null) {
                continue;
            }
            Order order = orderService.getById(detail.getMId());
            if (order == null || order.getShop_id() == null || !order.getShop_id().equals(shopId)) {
                continue;
            }
            String printResult = "SENT";
            String payloadText = null;
            try {
                if (printDispatcherService != null) {
                    List<com.lanf.printing.model.PrintDispatchResult> results = printDispatcherService.dispatch(
                            shopId, com.lanf.printing.model.PrintScenario.SERVE,
                            com.lanf.printing.model.PrintContext.ofServe(order, detail, e.getValue()));
                    if (results.isEmpty()) {
                        throw new IllegalStateException("未配置生效的传菜出票规则或已被禁用，无法打印传菜单");
                    }
                    boolean success = results.stream().anyMatch(com.lanf.printing.model.PrintDispatchResult::isSuccess);
                    if (!success) {
                        String err = results.get(0).getError();
                        throw new RuntimeException(err != null ? err : "传菜单打印失败");
                    }
                    if (!results.isEmpty()) {
                        printResult = results.get(0).getStatus();
                        payloadText = results.get(0).getPayloadText();
                    }
                }
            } catch (Exception ex) {
                log.warn("[kds] 手动传菜单打印失败 shop_id={} detail_id={}: {}",
                        shopId, detail.getId(), ex.getMessage());
                throw new IllegalStateException("传菜单打印失败，明细 " + detail.getId() + ": "
                        + (ex.getMessage() != null ? ex.getMessage() : "打印服务异常"), ex);
            }
            printedCount++;
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("detail_id", detail.getId());
            item.put("dish_name", detail.getName());
            item.put("quantity", e.getValue());
            item.put("table_number", tableLabel(order));
            item.put("print_result", printResult);
            item.put("payloadText", payloadText);
            printedLines.add(item);
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("printed_count", printedCount);
        result.put("lines", printedLines);
        return result;
    }

    private static Integer asInt(Object... candidates) {
        for (Object o : candidates) {
            if (o instanceof Number) return ((Number) o).intValue();
            if (o != null) {
                try {
                    return Integer.parseInt(o.toString().trim());
                } catch (Exception ignored) {}
            }
        }
        return null;
    }

    private static int parseQty(String quantityStr) {
        if (!StringUtils.hasText(quantityStr)) return 1;
        try {
            return Integer.parseInt(quantityStr.trim());
        } catch (Exception e) {
            return 1;
        }
    }

    /** 传菜打印在事务提交后执行，避免打印/飞鹅异常导致传菜接口 HTTP 500。 */
    private void schedulePrint(int shopId, List<ServeLine> lines) {
        if (lines == null || lines.isEmpty() || shopId <= 0) {
            return;
        }
        if (!configService.isServePrintEnabled(shopId)) {
            return;
        }
        List<ServeLine> copy = new ArrayList<>(lines);
        for (ServeLine line : copy) {
            if (line == null || line.quantity <= 0) continue;
            String key = line.transitionVersion > 0
                    ? shopId + ":" + line.detailId + ":" + line.transitionVersion
                    : shopId + ":" + line.detailId + ":legacy:" + System.nanoTime();
            jdbc.update("INSERT IGNORE INTO t_kds_serve_print_job "
                            + "(job_key,shop_id,detail_id,quantity,status,next_attempt_at,created_at,updated_at) "
                            + "VALUES (?,?,?,?,'PENDING',NOW(),NOW(),NOW())",
                    key, shopId, line.detailId, line.quantity);
            scheduleProcessAfterCommit(key);
        }
    }

    private void scheduleProcessAfterCommit(String key) {
        if (TransactionSynchronizationManager.isActualTransactionActive()
                && TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    processJob(key);
                }
            });
            return;
        }
        processJob(key);
    }

    @Scheduled(fixedDelayString = "${kds.serve-print-retry-ms:5000}")
    public void retryPrintJobs() {
        jdbc.update("UPDATE t_kds_serve_print_job SET status='RETRY', next_attempt_at=NOW(), updated_at=NOW() "
                + "WHERE status='PROCESSING' AND updated_at < DATE_SUB(NOW(), INTERVAL 2 MINUTE)");
        List<String> keys = jdbc.queryForList("SELECT job_key FROM t_kds_serve_print_job "
                + "WHERE status IN ('PENDING','RETRY') AND next_attempt_at<=NOW() "
                + "ORDER BY id LIMIT 100", String.class);
        for (String key : keys) processJob(key);
    }

    private void processJob(String key) {
        int claimed = jdbc.update("UPDATE t_kds_serve_print_job SET status='PROCESSING', updated_at=NOW() "
                + "WHERE job_key=? AND status IN ('PENDING','RETRY') AND next_attempt_at<=NOW()", key);
        if (claimed != 1) return;
        try {
            Map<String, Object> job = jdbc.queryForMap("SELECT shop_id,detail_id,quantity FROM t_kds_serve_print_job WHERE job_key=?", key);
            int shopId = ((Number) job.get("shop_id")).intValue();
            int detailId = ((Number) job.get("detail_id")).intValue();
            int quantity = ((Number) job.get("quantity")).intValue();
            OrderDetail detail = orderDetailService.getById(detailId);
            if (detail == null || OrderDetailLineStatus.isRefunded(detail.getLine_status())) {
                markSkipped(key, "明细不存在或已退菜"); return;
            }
            if (detail.getMId() == null) {
                markSkipped(key, "明细缺少订单"); return;
            }
            Order order = orderService.getById(detail.getMId());
            if (order == null || !Integer.valueOf(shopId).equals(order.getShop_id())) {
                markSkipped(key, "订单不存在或门店不匹配"); return;
            }
            if (printDispatcherService != null) {
                List<com.lanf.printing.model.PrintDispatchResult> results = printDispatcherService.dispatch(
                        shopId, com.lanf.printing.model.PrintScenario.SERVE,
                        com.lanf.printing.model.PrintContext.ofServe(order, detail, quantity));
                if (results.isEmpty()) {
                    markSkipped(key, "未配置生效的传菜出票规则或已被禁用，跳过出票");
                    log.info("[kds] 传菜单跳过出票(未配置生效规则) shop_id={} detail_id={}", shopId, detail.getId());
                    return;
                }
                boolean success = results.stream().anyMatch(com.lanf.printing.model.PrintDispatchResult::isSuccess);
                if (success) {
                    jdbc.update("UPDATE t_kds_serve_print_job SET status='PRINTED', updated_at=NOW(), last_error=NULL WHERE job_key=?", key);
                    log.info("[kds] 传菜单已打印 shop_id={} detail_id={} table={} qty={}",
                            shopId, detail.getId(), tableLabel(order), quantity);
                } else {
                    String err = results.get(0).getError();
                    throw new RuntimeException(err != null ? err : "传菜单打印失败");
                }
            }
        } catch (Exception ex) {
            String error = ex.getMessage() != null ? ex.getMessage() : ex.getClass().getSimpleName();
            jdbc.update("UPDATE t_kds_serve_print_job SET status='RETRY', attempts=attempts+1, "
                            + "next_attempt_at=DATE_ADD(NOW(), INTERVAL LEAST(300, POW(2, LEAST(attempts,8))) SECOND), "
                            + "last_error=?, updated_at=NOW() WHERE job_key=?", error, key);
            log.warn("[kds] 传菜单打印失败 job_key={}: {}", key, error);
        }
    }

    private void markSkipped(String key, String reason) {
        jdbc.update("UPDATE t_kds_serve_print_job SET status='SKIPPED', last_error=?, updated_at=NOW() WHERE job_key=?", reason, key);
    }

    private static Map<Integer, Integer> mergeQuantities(List<ServeLine> lines) {
        Map<Integer, Integer> out = new LinkedHashMap<>();
        for (ServeLine line : lines) {
            if (line == null || line.quantity <= 0) {
                continue;
            }
            out.merge(line.detailId, line.quantity, Integer::sum);
        }
        return out;
    }

    private static boolean isDineIn(Order order) {
        return order != null && !PaymentDiningTypeUtil.isPackOrDeliveryType(order.getDineInOrTakeOut());
    }

    private static String tableLabel(Order order) {
        if (order == null) {
            return "未知";
        }
        if (StringUtils.hasText(order.getTable_number())) {
            return order.getTable_number().trim();
        }
        return StringUtils.hasText(order.getOrder_no()) ? order.getOrder_no() : "未知";
    }

    private static String modeLabel(Order order) {
        if (order == null || !StringUtils.hasText(order.getDineInOrTakeOut())) {
            return "传菜";
        }
        String t = order.getDineInOrTakeOut().trim();
        if (PaymentDiningTypeUtil.isWaimaiType(t)) {
            return "外卖传菜";
        }
        if ("打包".equals(t) || PaymentDiningTypeUtil.isTakeOutType(t)) {
            return "打包传菜";
        }
        return t;
    }

    private static String formatSpecInParens(String selectedSpicy) {
        if (!StringUtils.hasText(selectedSpicy)) {
            return "";
        }
        String t = selectedSpicy.trim();
        if (t.isEmpty() || "null".equalsIgnoreCase(t)) {
            return "";
        }
        List<String> values = new ArrayList<>();
        try {
            collectSpecValues(SPEC_MAPPER.readTree(t), values);
        } catch (Exception ignored) {
            values.add(t);
        }
        return values.isEmpty() ? "" : "(" + String.join(",", values) + ")";
    }

    private static void collectSpecValues(JsonNode node, List<String> values) {
        if (node == null || node.isNull()) {
            return;
        }
        if (node.isObject()) {
            Iterator<JsonNode> fields = node.elements();
            while (fields.hasNext()) {
                collectSpecValues(fields.next(), values);
            }
            return;
        }
        if (node.isArray()) {
            for (JsonNode item : node) {
                collectSpecValues(item, values);
            }
            return;
        }
        String value = node.asText().trim();
        if (StringUtils.hasText(value) && !"null".equalsIgnoreCase(value)) {
            values.add(value);
        }
    }

    private static String padLeft(String s, int width) {
        if (s == null) {
            s = "";
        }
        if (s.length() >= width) {
            return s;
        }
        StringBuilder sb = new StringBuilder();
        for (int i = s.length(); i < width; i++) {
            sb.append(' ');
        }
        return sb.append(s).toString();
    }
}

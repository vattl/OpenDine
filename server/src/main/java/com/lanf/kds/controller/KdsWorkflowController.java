package com.lanf.kds.controller;

import com.lanf.entity.R;
import com.lanf.kds.KdsWorkflow;
import com.lanf.kds.KdsWorkflowQueue;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.service.KdsConfigService;
import com.lanf.kds.service.KdsServePrintService;
import com.lanf.kds.service.KdsWorkflowService;
import com.lanf.kds.support.KdsAdvanceRequestContext;
import com.lanf.kds.util.KdsDeviceAuth;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * 统一工作流看板 REST：配菜 → 制作 → 传菜 → 已完成。
 * 业务实现见 {@link KdsWorkflowService}；验收矩阵见 {@code docs/kds_regression_matrix.md}。
 */
@RestController
@RequestMapping({"/kds/workflow", "/api/v1/kds"})
public class KdsWorkflowController {

    private static final Logger log = LoggerFactory.getLogger(KdsWorkflowController.class);

    @Autowired
    private KdsDeviceAuth deviceAuth;
    @Autowired
    private KdsWorkflowService workflowService;
    @Autowired
    private KdsServePrintService servePrintService;
    @Autowired(required = false)
    private KdsConfigService configService;
    @Autowired
    private HttpServletRequest request;

    @GetMapping("/board")
    public R board(@RequestParam(required = false) String queue,
                   @RequestParam(required = false) String view,
                   @RequestParam(required = false) String dining,
                   @RequestParam(required = false) String extra,
                   @RequestParam(required = false) String keyword,
                   @RequestParam(required = false) String sort,
                   @RequestParam(required = false) String merge_rules,
                   @RequestParam(required = false, name = "mergeRules") String mergeRulesCamel,
                   @RequestParam(required = false) String split_pack_takeout,
                   @RequestParam(required = false, name = "splitPackTakeout") String splitPackTakeoutCamel) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            String q = KdsWorkflowQueue.normalize(queue);
            boolean prepEnabled = configService != null ? configService.isPrepWorkflowEnabled(device.getShop_id(), device.getStation_id()) : true;
            if (!KdsWorkflow.canAccessQueue(device, q, prepEnabled)) {
                return R.error(403, "当前设备无权访问队列：" + q);
            }
            String mergeRaw = StringUtils.hasText(merge_rules) ? merge_rules : mergeRulesCamel;
            String splitRaw = StringUtils.hasText(split_pack_takeout) ? split_pack_takeout : splitPackTakeoutCamel;
            return R.ok(workflowService.buildBoard(device, queue, view, dining, extra, keyword, sort, mergeRaw, splitRaw));
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    @GetMapping({"/bootstrap", "/workflow/bootstrap"})
    public R bootstrap(@RequestParam(required = false) String queues,
                       @RequestParam(required = false) String view,
                       @RequestParam(required = false) String dining,
                       @RequestParam(required = false) String extra,
                       @RequestParam(required = false) String keyword,
                       @RequestParam(required = false) String sort,
                       @RequestParam(required = false, name = "merge_rules") String mergeRules,
                       @RequestParam(required = false, name = "mergeRules") String mergeRulesCamel,
                       @RequestParam(required = false, name = "split_pack_takeout") String splitPackTakeout,
                       @RequestParam(required = false, name = "splitPackTakeout") String splitPackTakeoutCamel) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            String mergeRaw = StringUtils.hasText(mergeRules) ? mergeRules : mergeRulesCamel;
            String splitRaw = StringUtils.hasText(splitPackTakeout) ? splitPackTakeout : splitPackTakeoutCamel;
            return R.ok(workflowService.buildBootstrap(device, queues, view, dining, extra, keyword, sort, mergeRaw, splitRaw));
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    @GetMapping("/archived-history")
    public R archivedHistory(@RequestParam(required = false, defaultValue = "50") Integer limit,
                             @RequestParam(required = false) String before,
                             @RequestParam(required = false, name = "detail_id") Integer detailId,
                             @RequestParam(required = false, name = "order_id") Integer orderId) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            return R.ok(workflowService.archivedHistory(device.getShop_id(), limit, before, detailId, orderId));
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    /** 设备级手动清空已归档工单（功能需求 F-SYNC-05）。 */
    @PostMapping("/archive/clear")
    public R archiveClear() {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            return R.ok(workflowService.archiveClear(device.getShop_id(), device.getDevice_code()));
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    @PostMapping("/advance")
    public R advance(@RequestBody Map<String, Object> body) {
        return doAdvance(body);
    }

    /** 与 {@link #advance} 相同，供 Flutter 订单视图划菜调用。 */
    @PostMapping("/advance-item")
    public R advanceItem(@RequestBody Map<String, Object> body) {
        return doAdvance(body);
    }

    private R doAdvance(Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            Integer detailId = asInt(body, "detail_id", "item_id", "detailId", "itemId");
            String fromQueue = KdsWorkflowQueue.normalize(text(body, "from_queue", "fromQueue"));
            Integer quantity = asInt(body, "quantity", "qty");
            Long rowVersion = asLong(body, "row_version", "rowVersion", "version");
            if (detailId == null || detailId <= 0) {
                return R.error("detail_id 不能为空");
            }
            if (!KdsWorkflow.canAccessQueue(device, fromQueue)) {
                return R.error(403, "当前设备无权推进队列：" + fromQueue);
            }
            List<Integer> detailIds = parseDetailIdList(body);
            int qty = quantity != null ? quantity : 1;
            KdsAdvanceRequestContext context = parseAdvanceContext(body);
            if (detailIds != null && detailIds.size() > 1) {
                return R.ok(workflowService.advanceFifo(device.getShop_id(), fromQueue, qty, detailIds, context));
            }
            return R.ok(workflowService.advanceDetail(device.getShop_id(), detailId, fromQueue, qty, rowVersion, context));
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (KdsWorkflowService.OptimisticLockException e) {
            return R.error(5001, e.getMessage());
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        } catch (Exception e) {
            log.error("[kds] workflow/advance failed", e);
            return R.error(e.getMessage() != null ? e.getMessage() : "传菜推进失败");
        }
    }

    @PostMapping("/advance-order")
    public R advanceOrder(@RequestBody Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            Integer orderId = asInt(body, "order_id", "orderId");
            String fromQueue = KdsWorkflowQueue.normalize(text(body, "from_queue", "fromQueue"));
            if (orderId == null || orderId <= 0) {
                return R.error("order_id 不能为空");
            }
            if (!KdsWorkflow.canAccessQueue(device, fromQueue)) {
                return R.error(403, "当前设备无权推进队列：" + fromQueue);
            }
            return R.ok(workflowService.advanceOrder(device.getShop_id(), orderId, fromQueue));
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    private static String text(Map<String, Object> body, String... keys) {
        if (body == null) {
            return null;
        }
        for (String k : keys) {
            Object v = body.get(k);
            if (v != null && StringUtils.hasText(v.toString())) {
                return v.toString().trim();
            }
        }
        return null;
    }

    private static Integer asInt(Map<String, Object> body, String... keys) {
        if (body == null) {
            return null;
        }
        for (String k : keys) {
            Object v = body.get(k);
            Integer parsed = parseInt(v);
            if (parsed != null) {
                return parsed;
            }
        }
        return null;
    }

    private static Long asLong(Map<String, Object> body, String... keys) {
        if (body == null) return null;
        for (String key : keys) {
            Object value = body.get(key);
            if (value == null) continue;
            try {
                return value instanceof Number ? ((Number) value).longValue() : Long.parseLong(value.toString().trim());
            } catch (NumberFormatException ignore) {
                // Try the next alias.
            }
        }
        return null;
    }

    private static KdsAdvanceRequestContext parseAdvanceContext(Map<String, Object> body) {
        return new KdsAdvanceRequestContext(
                asInt(body, "expected_order_id", "expectedOrderId"),
                text(body, "expected_table_number", "expectedTableNumber"),
                text(body, "expected_dish_name", "expectedDishName"));
    }

    @PostMapping("/lack")
    public R lack(@RequestBody Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            Integer detailId = asInt(body, "detail_id", "item_id", "detailId", "itemId");
            String fromQueue = KdsWorkflowQueue.normalize(text(body, "from_queue", "fromQueue"));
            Integer quantity = asInt(body, "quantity", "qty");
            String remark = text(body, "remark");
            if (detailId == null || detailId <= 0) {
                return R.error("detail_id 不能为空");
            }
            return R.ok(workflowService.reportLack(device.getShop_id(), detailId, fromQueue, quantity, remark));
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    @PostMapping("/revoke")
    public R revoke(@RequestBody Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            Integer detailId = asInt(body, "detail_id", "item_id", "detailId", "itemId");
            String fromQueue = KdsWorkflowQueue.normalize(text(body, "from_queue", "fromQueue"));
            Integer quantity = asInt(body, "quantity", "qty");
            if (detailId == null || detailId <= 0) {
                return R.error("detail_id 不能为空");
            }
            if (!KdsWorkflow.canAccessQueue(device, fromQueue)) {
                return R.error(403, "当前设备无权撤销队列：" + fromQueue);
            }
            int qty = quantity != null ? quantity : 1;
            return R.ok(workflowService.revokeDetail(device.getShop_id(), detailId, fromQueue, qty));
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    @PostMapping("/hold")
    public R hold(@RequestBody Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            Integer detailId = asInt(body, "detail_id", "item_id", "detailId", "itemId");
            if (detailId == null || detailId <= 0) {
                return R.error("detail_id 不能为空");
            }
            return R.ok(workflowService.holdDetail(device.getShop_id(), detailId));
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    @PostMapping("/release")
    public R release(@RequestBody Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            Integer detailId = asInt(body, "detail_id", "item_id", "detailId", "itemId");
            if (detailId == null || detailId <= 0) {
                return R.error("detail_id 不能为空");
            }
            return R.ok(workflowService.releaseDetail(device.getShop_id(), detailId));
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    @PostMapping("/refund")
    public R refund(@RequestBody Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            Integer detailId = asInt(body, "detail_id", "item_id", "detailId", "itemId");
            String fromQueue = KdsWorkflowQueue.normalize(text(body, "from_queue", "fromQueue"));
            Integer quantity = asInt(body, "quantity", "qty");
            String remark = text(body, "remark");
            if (detailId == null || detailId <= 0) {
                return R.error("detail_id 不能为空");
            }
            return R.ok(workflowService.refundDish(device.getShop_id(), detailId, fromQueue, quantity, remark));
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    /**
     * 传菜单手动打印/补打接口（供 KDS 客户端调用）
     */
    @PostMapping("/print-serve-ticket")
    public R printServeTicket(@RequestBody(required = false) Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            Integer detailId = asInt(body, "detail_id", "detailId", "item_id", "itemId");
            Integer orderId = asInt(body, "order_id", "orderId");
            Integer quantity = asInt(body, "quantity", "qty");
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> lines = body != null && body.get("lines") instanceof List
                    ? (List<Map<String, Object>>) body.get("lines") : null;
            Map<String, Object> data = servePrintService.printManual(device.getShop_id(), orderId, detailId, quantity, lines);
            return R.ok(data);
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        } catch (Exception e) {
            log.error("[kds] print-serve-ticket failed", e);
            return R.error(e.getMessage() != null ? e.getMessage() : "传菜单打印失败");
        }
    }

    @SuppressWarnings("unchecked")
    private static List<Integer> parseDetailIdList(Map<String, Object> body) {
        if (body == null) {
            return null;
        }
        Object raw = body.get("detail_ids");
        if (raw == null) {
            raw = body.get("detailIds");
        }
        if (!(raw instanceof List)) {
            return null;
        }
        List<Integer> out = new ArrayList<>();
        for (Object o : (List<?>) raw) {
            Integer id = parseInt(o);
            if (id != null && id > 0) {
                out.add(id);
            }
        }
        return out.isEmpty() ? null : out;
    }

    private static Integer parseInt(Object v) {
        if (v instanceof Number) {
            return ((Number) v).intValue();
        }
        if (v != null) {
            try {
                return Integer.parseInt(v.toString().trim());
            } catch (NumberFormatException ignore) {
                return null;
            }
        }
        return null;
    }
}

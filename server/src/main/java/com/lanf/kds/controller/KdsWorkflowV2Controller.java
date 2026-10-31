package com.lanf.kds.controller;

import com.lanf.entity.R;
import com.lanf.kds.KdsWorkflow;
import com.lanf.kds.KdsWorkflowQueue;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.service.KdsWorkflowV2Service;
import com.lanf.kds.service.KdsMetricsService;
import com.lanf.kds.service.KdsV2CommandLedger;
import com.lanf.kds.service.KdsV2CommandConflictException;
import com.lanf.kds.service.KdsV2RejectedCommandException;
import com.lanf.kds.util.KdsDeviceAuth;
import com.lanf.kds.service.KdsCommandResultService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import com.lanf.kds.service.KdsWorkflowService;
import javax.servlet.http.HttpServletResponse;
import java.util.Map;

/**
 * 统一工作流看板 V2 REST 控制器：
 * 实现与 kds_app (kds_v2_models.dart) 强类型规范完全同构的 API。
 */
@RestController
@RequestMapping("/kds/v2")
public class KdsWorkflowV2Controller {

    private static final Logger log = LoggerFactory.getLogger(KdsWorkflowV2Controller.class);

    @Autowired
    private KdsDeviceAuth deviceAuth;
    @Autowired
    private KdsWorkflowV2Service v2Service;
    @Autowired
    private KdsV2CommandLedger commandLedger;
    @Autowired
    private KdsSettingsController settingsController;
    @Autowired
    private HttpServletRequest request;
    @Autowired(required = false)
    private KdsMetricsService metricsService;

    /**
     * 全量冷启动引导
     * GET /kds/v2/bootstrap
     */
    @GetMapping("/bootstrap")
    public R bootstrap(HttpServletResponse response) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            if (metricsService != null) {
                metricsService.recordBootstrapRequest(device.getShop_id());
            }
            Map<String, Object> data = v2Service.buildBootstrap(device);
            return R.ok(data);
        } catch (IllegalStateException e) {
            if (response != null) response.setStatus(401);
            return R.error(401, e.getMessage());
        } catch (IllegalArgumentException e) {
            if (response != null) response.setStatus(400);
            return R.error(4000, e.getMessage());
        } catch (Exception e) {
            log.error("[kds/v2] bootstrap failed", e);
            if (response != null) response.setStatus(500);
            return R.error(e.getMessage() != null ? e.getMessage() : "bootstrap 失败");
        }
    }

    /**
     * 统一命令调度入口（划菜、加急、撤销、缺货、报缺退菜等）
     * POST /kds/v2/commands
     */
    @PostMapping("/commands")
    public R commands(@RequestBody Map<String, Object> body, HttpServletResponse response) {
        KdsDevice device;
        try {
            device = deviceAuth.requireDevice(request);
        } catch (IllegalStateException e) {
            if (response != null) response.setStatus(401);
            return R.error(401, e.getMessage());
        }
        long startMs = System.currentTimeMillis();
        String commandType = body != null && body.get("type") != null ? body.get("type").toString() : "unknown";
        int shopId = device != null ? device.getShop_id() : 0;
        if (isPosFinancialCommand(commandType)) {
            String message = "KDS 设备无权执行 POS 财务命令";
            persistStableRejection(device, body, 403, 4030, message);
            if (metricsService != null) {
                metricsService.recordCommandExecution(shopId, commandType, 403,
                        System.currentTimeMillis() - startMs);
            }
            if (response != null) response.setStatus(403);
            return R.error(4030, message);
        }
        String requiredQueue = requiredQueue(commandType, body);
        if (requiredQueue != null && !KdsWorkflow.canAccessQueue(device, requiredQueue)) {
            String message = "当前 KDS 设备无权操作队列：" + requiredQueue;
            persistStableRejection(device, body, 403, 4030, message);
            if (metricsService != null) {
                metricsService.recordCommandExecution(shopId, commandType, 403,
                        System.currentTimeMillis() - startMs);
            }
            if (response != null) response.setStatus(403);
            return R.error(4030, message);
        }
        try {
            Map<String, Object> data = v2Service.executeCommand(device, body);
            if (metricsService != null) {
                metricsService.recordCommandExecution(shopId, commandType, 200, System.currentTimeMillis() - startMs);
            }
            return R.ok(data);
        } catch (KdsV2RejectedCommandException e) {
            if (metricsService != null) {
                metricsService.recordCommandExecution(shopId, commandType, e.getHttpStatus(), System.currentTimeMillis() - startMs);
            }
            if (response != null) response.setStatus(e.getHttpStatus());
            return R.error(e.getBusinessCode(), e.getMessage())
                    .put("command", e.getResult());
        } catch (KdsV2CommandConflictException e) {
            if (metricsService != null) {
                metricsService.recordCommandExecution(shopId, commandType, 409, System.currentTimeMillis() - startMs);
            }
            if (response != null) response.setStatus(409);
            return R.error(4090, e.getMessage());
        } catch (KdsWorkflowService.OptimisticLockException e) {
            persistStableRejection(device, body, 409, 4090, e.getMessage());
            if (metricsService != null) {
                metricsService.recordCommandExecution(shopId, commandType, 409, System.currentTimeMillis() - startMs);
            }
            if (response != null) response.setStatus(409);
            return R.error(4090, e.getMessage());
        } catch (IllegalArgumentException e) {
            persistStableRejection(device, body, 400, 4000, e.getMessage());
            if (metricsService != null) {
                metricsService.recordCommandExecution(shopId, commandType, 400, System.currentTimeMillis() - startMs);
            }
            if (response != null) response.setStatus(400);
            return R.error(4000, e.getMessage());
        } catch (Exception e) {
            if (metricsService != null) {
                metricsService.recordCommandExecution(shopId, commandType, 500, System.currentTimeMillis() - startMs);
            }
            log.error("[kds/v2] commands failed", e);
            if (response != null) response.setStatus(500);
            return R.error(e.getMessage() != null ? e.getMessage() : "command 执行失败");
        }
    }

    @Autowired
    private KdsCommandResultService commandResultService;

    private static boolean isPosFinancialCommand(String commandType) {
        return "pos_add_dishes".equals(commandType) || "addDishes".equals(commandType)
                || "pos_refund_dish".equals(commandType) || "refundDish".equals(commandType);
    }

    @SuppressWarnings("unchecked")
    private static String requiredQueue(String commandType, Map<String, Object> body) {
        if ("complete_order".equals(commandType) || "archive_order".equals(commandType)
                || "archive_clear".equals(commandType)) {
            return KdsWorkflowQueue.READY_SERVE;
        }
        if (!("advance_item".equals(commandType) || "advance_order".equals(commandType)
                || "revoke_item".equals(commandType) || "lack_item".equals(commandType)
                || "refund_item".equals(commandType) || "hold_item".equals(commandType)
                || "release_item".equals(commandType))) {
            return null;
        }
        Map<String, Object> target = body != null && body.get("target") instanceof Map
                ? (Map<String, Object>) body.get("target") : null;
        Object rawQueue = target != null ? target.get("from_queue") : null;
        if (rawQueue == null && body != null) rawQueue = body.get("from_queue");
        return KdsWorkflowQueue.normalize(rawQueue != null ? rawQueue.toString() : null);
    }

    private void persistStableRejection(KdsDevice device, Map<String, Object> body,
                                        int httpStatus, int businessCode, String message) {
        if (commandResultService == null || device == null || body == null) return;
        Object rawCommandId = body.get("command_id");
        Object rawType = body.get("type");
        if (rawCommandId == null || rawCommandId.toString().trim().isEmpty()
                || rawType == null || rawType.toString().trim().isEmpty()) return;
        String actorId = device.getDevice_code() != null
                ? device.getDevice_code() : String.valueOf(device.getId());
        try {
            commandResultService.saveResultInNewTransaction(
                    device.getShop_id(), rawCommandId.toString().trim(), actorId,
                    "KDS", rawType.toString(), "2.0", body,
                    httpStatus, businessCode, message);
        } catch (Exception persistenceFailure) {
            // Preserve the original business response. The missing terminal row is
            // operationally visible and remains retryable instead of becoming false success.
            log.error("[kds/v2] failed to persist stable rejection command_id={}",
                    rawCommandId, persistenceFailure);
        }
    }

    /** Resolve an ambiguous command result without executing a second business mutation. */
    @GetMapping("/commands/{commandId}")
    public R commandResult(@PathVariable String commandId, HttpServletResponse response) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            return R.ok(v2Service.resolveCommand(device, commandId));
        } catch (IllegalStateException e) {
            if (response != null) response.setStatus(401);
            return R.error(401, e.getMessage());
        } catch (IllegalArgumentException e) {
            if (response != null) response.setStatus(400);
            return R.error(4000, e.getMessage());
        } catch (Exception e) {
            log.error("[kds/v2] command resolution failed command_id={}", commandId, e);
            if (response != null) response.setStatus(500);
            return R.error(e.getMessage() != null ? e.getMessage() : "command resolution 失败");
        }
    }

    /** Save KDS workflow configuration through the same cloud authority on LAN and cloud. */
    @PostMapping("/config")
    public R config(@RequestBody Map<String, Object> body, HttpServletResponse response) {
        try {
            deviceAuth.requireDevice(request);
            if (response != null) response.setStatus(403);
            return R.error(4030, "KDS 设备无权修改门店级配置，请使用管理端");
        } catch (IllegalStateException e) {
            if (response != null) response.setStatus(401);
            return R.error(401, e.getMessage());
        } catch (IllegalArgumentException e) {
            if (response != null) response.setStatus(400);
            return R.error(4000, e.getMessage());
        } catch (Exception e) {
            log.error("[kds/v2] config failed", e);
            if (response != null) response.setStatus(500);
            return R.error(e.getMessage() != null ? e.getMessage() : "config 保存失败");
        }
    }

    /**
     * 增量变更事件追赶
     * GET /kds/v2/changes?after_seq=xxx
     */
    @GetMapping("/changes")
    public R changes(@RequestParam(value = "after_seq", defaultValue = "0") long afterSeq, HttpServletResponse response) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            if (metricsService != null) {
                metricsService.recordChangesRequest(device.getShop_id());
            }
            Map<String, Object> data = v2Service.getChanges(device, afterSeq);
            return R.ok(data);
        } catch (IllegalStateException e) {
            if (response != null) response.setStatus(401);
            return R.error(401, e.getMessage());
        } catch (IllegalArgumentException e) {
            if (response != null) response.setStatus(400);
            return R.error(4000, e.getMessage());
        } catch (Exception e) {
            log.error("[kds/v2] changes failed", e);
            if (response != null) response.setStatus(500);
            return R.error(e.getMessage() != null ? e.getMessage() : "changes 失败");
        }
    }

    /**
     * 当日营业时段历史订单拉取（支持游标分页）
     * GET /kds/v2/business-day/orders?after_id=xxx&limit=xxx
     */
    @GetMapping("/business-day/orders")
    public R businessDayOrders(@RequestParam(value = "after_id", required = false) Integer afterId,
                               @RequestParam(value = "limit", defaultValue = "200") int limit,
                               HttpServletResponse response) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            if (metricsService != null) {
                metricsService.recordBusinessDayRequest(device.getShop_id());
            }
            Map<String, Object> data = v2Service.getBusinessDayOrders(device, afterId, limit);
            return R.ok(data);
        } catch (IllegalStateException e) {
            if (response != null) response.setStatus(401);
            return R.error(401, e.getMessage());
        } catch (IllegalArgumentException e) {
            if (response != null) response.setStatus(400);
            return R.error(4000, e.getMessage());
        } catch (Exception e) {
            log.error("[kds/v2] business-day/orders failed", e);
            if (response != null) response.setStatus(500);
            return R.error(e.getMessage() != null ? e.getMessage() : "business-day/orders 失败");
        }
    }

    /**
     * 商用度量指标摘要
     * GET /kds/v2/diagnostics/metrics
     */
    @GetMapping("/diagnostics/metrics")
    public R diagnosticsMetrics(HttpServletResponse response) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            Map<String, Object> data = metricsService != null
                    ? metricsService.getMetricsSnapshot()
                    : new java.util.HashMap<>();
            data.put("shop_id", device.getShop_id());
            data.put("device_code", device.getDevice_code());
            return R.ok(data);
        } catch (IllegalStateException e) {
            if (response != null) response.setStatus(401);
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            log.error("[kds/v2] diagnostics/metrics failed", e);
            if (response != null) response.setStatus(500);
            return R.error(e.getMessage() != null ? e.getMessage() : "metrics 获取失败");
        }
    }
}

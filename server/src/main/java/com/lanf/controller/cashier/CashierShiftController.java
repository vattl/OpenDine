package com.lanf.controller.cashier;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.CashMovement;
import com.lanf.entity.DrawerSession;
import com.lanf.entity.Payment;
import com.lanf.entity.PaymentLedger;
import com.lanf.entity.R;
import com.lanf.entity.Shift;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.DrawerSessionService;
import com.lanf.service.IAdminService;
import com.lanf.service.IPaymentService;
import com.lanf.service.IShiftService;
import com.lanf.service.IMemberRechargeService;
import com.lanf.service.MemberRechargeSummary;
import com.lanf.service.PaymentLedgerService;
import com.lanf.util.AdminNameResolver;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.util.*;

/**
 * 收银员交班与钱箱会话状态机（开班/交班/盲盘/差额审批/现金动作）
 */
@RestController
@RequestMapping("/cashier/shift")
public class CashierShiftController {

    @Autowired
    private IShiftService shiftService;
    @Autowired
    private IPaymentService paymentService;
    @Autowired(required = false)
    private DrawerSessionService drawerSessionService;
    @Autowired(required = false)
    private PaymentLedgerService paymentLedgerService;
    @Autowired(required = false)
    private IAdminService adminService;
    @Autowired(required = false)
    private IMemberRechargeService memberRechargeService;
    @Autowired
    private HttpServletRequest request;

    @PostMapping("/start")
    public R start(@RequestBody(required = false) Map<String, Object> body) {
        Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        if (adminId == null) {
            return R.error("未登录");
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null || shopId <= 0) {
            return R.error(4001, "缺少已授权的门店上下文");
        }

        BigDecimal startCash = BigDecimal.ZERO;
        if (body != null) {
            if (body.get("start_cash") != null) {
                startCash = new BigDecimal(body.get("start_cash").toString());
            } else if (body.get("opening_float") != null) {
                startCash = new BigDecimal(body.get("opening_float").toString());
            } else if (body.get("openingFloatFen") != null) {
                startCash = BigDecimal.valueOf(Long.parseLong(body.get("openingFloatFen").toString()), 2);
            }
        }
        int floatFen = (int) Math.round(startCash.doubleValue() * 100);

        String terminalId = text(body, "terminal_id", "terminalId");
        String drawerCode = text(body, "drawer_code", "drawerCode");
        String requestId = text(body, "idempotency_key", "request_id", "requestId");
        String businessDay = text(body, "business_day", "businessDay");

        if (drawerSessionService != null) {
            try {
                DrawerSession session = drawerSessionService.openSession(
                        shopId, terminalId, drawerCode, adminId, floatFen, businessDay, requestId
                );
                Shift current = shiftService.getOne(new QueryWrapper<Shift>()
                        .eq("drawer_session_id", session.getId())
                        .last("LIMIT 1"));
                Long shiftId = current != null ? current.getId() : session.getId();
                String opName = AdminNameResolver.resolveDisplayName(adminId, adminService);
                return R.ok()
                        .put("shiftId", shiftId)
                        .put("sessionId", session.getId())
                        .put("session_no", session.getSession_no())
                        .put("state", session.getState())
                        .put("business_day", session.getBusiness_day())
                        .put("operator_name", opName)
                        .put("opened_by_name", opName)
                        .put("trace_id", traceId())
                        .put("business_no", session.getSession_no())
                        .put("server_time", serverTime());
            } catch (IllegalStateException e) {
                return R.error(e.getMessage());
            }
        }

        // 兜底旧逻辑
        Shift shift = new Shift();
        shift.setAdmin_id(adminId);
        shift.setShop_id(shopId);
        shift.setStart_time(new Date());
        shift.setStart_cash(startCash);
        shift.setOrder_count(0);
        shift.setTotal_amount(BigDecimal.ZERO);
        shiftService.save(shift);
        String opName = AdminNameResolver.resolveDisplayName(adminId, adminService);
        return R.ok()
                .put("shiftId", shift.getId())
                .put("operator_name", opName)
                .put("opened_by_name", opName)
                .put("trace_id", traceId())
                .put("business_no", shift.getId())
                .put("server_time", serverTime());
    }

    @PostMapping("/handover")
    public R handover(@RequestBody Map<String, Object> body) {
        Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        if (adminId == null) {
            return R.error("未登录");
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null || shopId <= 0) {
            return R.error(4001, "缺少已授权的门店上下文");
        }

        if (body == null || (body.get("end_cash") == null && body.get("counted_cash") == null && body.get("countedCashFen") == null)) {
            return R.error("实盘现金金额不能为空");
        }

        BigDecimal endCash;
        if (body.get("countedCashFen") != null) {
            endCash = BigDecimal.valueOf(Long.parseLong(body.get("countedCashFen").toString()), 2);
        } else if (body.get("counted_cash") != null) {
            endCash = new BigDecimal(body.get("counted_cash").toString());
        } else {
            endCash = new BigDecimal(body.get("end_cash").toString());
        }
        int countedFen = (int) Math.round(endCash.doubleValue() * 100);

        String terminalId = text(body, "terminal_id", "terminalId");
        String varianceReasonCode = text(body, "variance_reason_code", "varianceReasonCode");
        String varianceNote = text(body, "variance_note", "varianceNote");
        Integer approverId = intVal(body, "approved_by", "approvedBy", "approver_id", "approverId");
        String closeRequestId = text(body, "idempotency_key", "close_request_id", "closeRequestId");

        Shift current = shiftService.getOne(new QueryWrapper<Shift>()
                .eq("admin_id", adminId).eq("shop_id", shopId)
                .isNull("end_time").orderByDesc("start_time").last("LIMIT 1"));

        Long drawerSessionId = null;
        if (current != null && current.getDrawer_session_id() != null) {
            drawerSessionId = current.getDrawer_session_id();
        } else if (drawerSessionService != null) {
            DrawerSession active = drawerSessionService.getActiveSession(shopId, terminalId, null);
            if (active != null) {
                drawerSessionId = active.getId();
            }
        }

        Map<String, Object> report = Collections.emptyMap();
        if (drawerSessionService != null && drawerSessionId != null) {
            try {
                drawerSessionService.closeSession(
                        shopId, drawerSessionId, adminId, countedFen,
                        varianceReasonCode, varianceNote, approverId, closeRequestId
                );
                report = drawerSessionService.getShiftSummaryReport(drawerSessionId);
            } catch (IllegalStateException e) {
                return R.error(e.getMessage());
            }
        }

        String opName = AdminNameResolver.resolveDisplayName(adminId, adminService);
        if (current != null) {
            Object[] stats = shiftStats(current);
            current.setOrder_count((Integer) stats[0]);
            current.setTotal_amount((BigDecimal) stats[1]);
            current.setEnd_time(new Date());
            current.setEnd_cash(endCash);
            current.setState("CLOSED");
            current.setAdmin_name(opName);
            shiftService.updateById(current);
            return R.ok()
                    .put("order_count", current.getOrder_count())
                    .put("total_amount", current.getTotal_amount())
                    .put("operator_name", opName)
                    .put("closed_by_name", opName)
                    .put("report", report)
                    .put("trace_id", traceId())
                    .put("business_no", drawerSessionId)
                    .put("server_time", serverTime());
        }

        return R.ok()
                .put("operator_name", opName)
                .put("closed_by_name", opName)
                .put("report", report)
                .put("trace_id", traceId())
                .put("business_no", drawerSessionId)
                .put("server_time", serverTime());
    }

    @GetMapping("/current")
    public R current(@RequestParam(required = false, defaultValue = "false") boolean previewExpected) {
        Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        if (adminId == null) {
            return R.error("未登录");
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null || shopId <= 0) {
            return R.error(4001, "缺少已授权的门店上下文");
        }

        Shift shift = shiftService.getOne(new QueryWrapper<Shift>()
                .eq("admin_id", adminId).eq("shop_id", shopId)
                .isNull("end_time").orderByDesc("start_time").last("LIMIT 1"));

        Map<String, Object> drawerSessionMap = null;
        if (drawerSessionService != null) {
            DrawerSession active = null;
            if (shift != null && shift.getDrawer_session_id() != null) {
                active = drawerSessionService.getById(shift.getDrawer_session_id());
            }
            if (active == null) {
                active = drawerSessionService.getActiveSession(shopId, null, null);
            }
            if (active != null) {
                drawerSessionMap = new LinkedHashMap<>();
                drawerSessionMap.put("id", active.getId());
                drawerSessionMap.put("session_no", active.getSession_no());
                drawerSessionMap.put("terminal_id", active.getTerminal_id());
                drawerSessionMap.put("drawer_code", active.getDrawer_code());
                drawerSessionMap.put("state", active.getState());
                drawerSessionMap.put("opened_at", active.getOpened_at());
                drawerSessionMap.put("opening_float_yuan", BigDecimal.valueOf(active.getOpening_float_fen() != null ? active.getOpening_float_fen() : 0, 2).doubleValue());
                drawerSessionMap.put("business_day", active.getBusiness_day());
                drawerSessionMap.put("opened_by", active.getOpened_by());
                String openedByName = AdminNameResolver.resolveDisplayName(active.getOpened_by(), adminService);
                drawerSessionMap.put("opened_by_name", openedByName);
                drawerSessionMap.put("operator_name", openedByName);

                // UI013 P0: legacy previewExpected is intentionally ignored. No query may reveal or
                // make expected cash / variance derivable before blind-count handover is submitted.
            }
        }

        if (shift != null) {
            Object[] stats = shiftStats(shift);
            shift.setOrder_count((Integer) stats[0]);
            shift.setTotal_amount((BigDecimal) stats[1]);
            shift.setAdmin_name(AdminNameResolver.resolveDisplayName(shift.getAdmin_id(), adminService));
        }

        MemberRechargeSummary rechargeSummary = shift != null && memberRechargeService != null
                ? memberRechargeService.summarizeSuccessfulByDrawerSession(shift.getDrawer_session_id())
                : MemberRechargeSummary.empty();
        if (rechargeSummary == null) rechargeSummary = MemberRechargeSummary.empty();
        return R.ok()
                .put("shift", shift)
                .put("drawer_session", drawerSessionMap)
                .put("member_recharge_summary", rechargeSummary.toMap());
    }

    @PostMapping("/cash-movement")
    public R cashMovement(@RequestBody Map<String, Object> body) {
        Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        if (adminId == null) {
            return R.error("未登录");
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null || shopId <= 0) {
            return R.error(4001, "缺少已授权的门店上下文");
        }
        if (drawerSessionService == null) {
            return R.error("钱箱服务未启用");
        }

        String movementType = text(body, "movement_type", "movementType");
        if (!StringUtils.hasText(movementType)) {
            return R.error("现金动作类型不能为空");
        }

        Double amountYuan = number(body, "amount", "amount_yuan", "amountYuan");
        int amountFen = amountYuan != null ? (int) Math.round(amountYuan * 100) : 0;
        if (body.get("amount_fen") != null) {
            amountFen = Integer.parseInt(body.get("amount_fen").toString());
        }

        Long drawerSessionId = longVal(body, "drawer_session_id", "drawerSessionId");
        if (drawerSessionId == null) {
            DrawerSession active = drawerSessionService.getActiveSession(shopId, null, null);
            if (active != null) {
                drawerSessionId = active.getId();
            }
        }
        if (drawerSessionId == null) {
            return R.error("当前无活动的钱箱会话");
        }

        String reasonCode = text(body, "reason_code", "reasonCode");
        String remark = text(body, "remark");
        Integer approverId = intVal(body, "approver_id", "approverId", "approved_by");
        String requestId = text(body, "idempotency_key", "request_id", "requestId");

        try {
            CashMovement movement = drawerSessionService.recordManualMovement(
                    shopId, drawerSessionId, movementType, amountFen,
                    reasonCode, remark, adminId, approverId, requestId
            );
            return R.ok()
                    .put("movement_no", movement.getMovement_no())
                    .put("movement_type", movement.getMovement_type())
                    .put("amount_yuan", BigDecimal.valueOf(movement.getAmount_fen(), 2).doubleValue())
                    .put("amount_fen", movement.getAmount_fen())
                    .put("current_balance_yuan", BigDecimal.valueOf(movement.getCurrent_balance_fen(), 2).doubleValue())
                    .put("trace_id", traceId())
                    .put("business_no", movement.getMovement_no())
                    .put("server_time", serverTime());
        } catch (com.lanf.common.ApiException e) {
            throw e;
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    @GetMapping("/report/{sessionId}")
    public R report(@PathVariable Long sessionId) {
        if (drawerSessionService == null) {
            return R.error("钱箱服务未启用");
        }
        Map<String, Object> summary = drawerSessionService.getShiftSummaryReport(sessionId);
        if (summary.isEmpty()) {
            return R.error("交班报告不存在");
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (!Objects.equals(shopId, summary.get("shop_id"))) {
            throw new com.lanf.common.ApiException(404, "SHIFT_NOT_FOUND", "交班报告不存在");
        }
        return R.ok().put("report", summary);
    }

    @GetMapping("/workbench")
    public R workbench(@RequestParam(name = "shop_id", required = false) Integer ignoredShopId) {
        requireDrawerService();
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        return R.ok(drawerSessionService.getWorkbench(shopId, adminId));
    }

    @GetMapping("/reports")
    public R reports(@RequestParam(name = "shop_id", required = false) Integer ignoredShopId,
                     @RequestParam(required = false) Long cursor,
                     @RequestParam(required = false) Integer limit) {
        requireDrawerService();
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        return R.ok(drawerSessionService.listShiftReports(shopId, cursor, limit));
    }

    @GetMapping("/{sessionId}/cash-events")
    public R cashEvents(@PathVariable Long sessionId,
                        @RequestParam(required = false) Long cursor,
                        @RequestParam(required = false) Integer limit) {
        requireDrawerService();
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        return R.ok(drawerSessionService.listCashEvents(shopId, sessionId, cursor, limit));
    }

    /**
     * 班次统计：优先统计不可变支付台账 t_payment_ledger；降级统计 t_payment。
     */
    private Object[] shiftStats(Shift shift) {
        if (paymentLedgerService != null && shift.getDrawer_session_id() != null) {
            List<PaymentLedger> ledgers = paymentLedgerService.list(new QueryWrapper<PaymentLedger>()
                    .eq("drawer_session_id", shift.getDrawer_session_id())
                    .eq("status", PaymentLedger.STATUS_SUCCEEDED));
            if (!ledgers.isEmpty()) {
                Set<String> orderNos = new HashSet<>();
                int totalFen = 0;
                for (PaymentLedger pl : ledgers) {
                    if (pl.getOrder_no() != null && PaymentLedger.ENTRY_TYPE_PAYMENT.equals(pl.getEntry_type())) {
                        orderNos.add(pl.getOrder_no());
                    }
                    totalFen += (pl.getAmount_fen() != null ? pl.getAmount_fen() : 0);
                }
                return new Object[]{orderNos.size(), BigDecimal.valueOf(totalFen, 2)};
            }
        }

        // 降级统计
        QueryWrapper<Payment> q = new QueryWrapper<Payment>()
                .eq("operator_id", shift.getAdmin_id())
                .eq(shift.getShop_id() != null, "shop_id", shift.getShop_id())
                .ge("pay_time", shift.getStart_time())
                .lt("pay_time", new Date());
        List<Payment> pays = paymentService.list(q);
        Set<String> orderNos = new HashSet<>();
        BigDecimal total = BigDecimal.ZERO;
        for (Payment p : pays) {
            if (p.getAmount() == null) {
                continue;
            }
            total = total.add(p.getAmount());
            if (p.getOrder_no() != null) {
                orderNos.add(p.getOrder_no());
            }
        }
        return new Object[]{orderNos.size(), total};
    }

    private static String text(Map<String, Object> body, String... keys) {
        if (body == null) return null;
        for (String key : keys) {
            Object value = body.get(key);
            if (value != null && StringUtils.hasText(value.toString())) return value.toString().trim();
        }
        return null;
    }

    private static Double number(Map<String, Object> body, String... keys) {
        String value = text(body, keys);
        if (value == null) return null;
        try {
            return Double.parseDouble(value);
        } catch (NumberFormatException ex) {
            return null;
        }
    }

    private static Integer intVal(Map<String, Object> body, String... keys) {
        String value = text(body, keys);
        if (value == null) return null;
        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException ex) {
            return null;
        }
    }

    private static Long longVal(Map<String, Object> body, String... keys) {
        String value = text(body, keys);
        if (value == null) return null;
        try {
            return Long.parseLong(value);
        } catch (NumberFormatException ex) {
            return null;
        }
    }

    private void requireDrawerService() {
        if (drawerSessionService == null) {
            throw new com.lanf.common.ApiException(503, "DRAWER_SERVICE_UNAVAILABLE", "钱箱服务未启用");
        }
    }

    private Object traceId() {
        return request.getAttribute(SysInterceptor.ATTR_TRACE_ID);
    }

    private static String serverTime() {
        return java.time.OffsetDateTime.now(java.time.ZoneOffset.ofHours(8)).toString();
    }
}

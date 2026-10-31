package com.lanf.controller.admin;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.DailyStat;
import com.lanf.entity.Order;
import com.lanf.entity.Payment;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.payment.support.PaymentChannelCatalog;
import com.lanf.receivable.service.ReceivableService;
import com.lanf.service.IDailyStatService;
import com.lanf.service.IOrderService;
import com.lanf.service.IPaymentService;
import com.lanf.service.IShopService;
import com.lanf.util.AdminShopRequest;
import com.lanf.util.OrderNetRevenue;
import com.lanf.util.ShopBusinessWindowResolver;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

/**
 * 日结与对账（收银系统扩展）
 *
 * <p>数据窗口口径：以 {@code t_shop.settle_time} 结算日为准
 * （未配置回退 16:00～次日 04:00，见 {@link ShopBusinessWindowResolver}），
 * 与看板"营业日营收（实时预览）"一致；未执行日结时 summary 实时汇总营业日窗口内的已结订单，
 * 不再返回全 0。
 */
@RestController
@RequestMapping("/admin/daily")
public class AdminDailyController {

    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(AdminDailyController.class);

    @Autowired
    private IDailyStatService dailyStatService;
    @Autowired
    private com.lanf.service.IDailyCloseService dailyCloseService;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private IPaymentService paymentService;
    @Autowired
    private IShopService shopService;
    @Autowired
    private com.lanf.service.ILedgerMigrationService ledgerMigrationService;
    @Autowired
    private com.lanf.mapper.PaymentLedgerMapper paymentLedgerMapper;
    @Autowired
    private HttpServletRequest request;

    /**
     * 日结页面单接口聚合：返回营业日权威时序、销售总额/扣除/退款 Summary、支付渠道 Channels、
     * 预检阻断项 Blockers、预检 Token 及已结快照信息，防止多接口调用产生参数名错位与数据不对称。
     */
    @GetMapping("/context")
    public R getDailyContext(@RequestParam(name = "stat_date", required = false) String statDate,
                             @RequestParam(name = "date", required = false) String date,
                             @RequestParam(required = false) Integer minutes) {
        String effectiveDate = (statDate != null && !statDate.trim().isEmpty()) ? statDate : date;
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        try {
            Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
            Map<String, Object> res = dailyCloseService.getDailyContext(shopId, adminId, effectiveDate, minutes);
            return R.ok(res);
        } catch (com.lanf.common.ApiException e) {
            throw e;
        } catch (Exception e) {
            log.error("获取日结聚合上下文失败 shopId={} date={}: {}", shopId, effectiveDate, e.getMessage(), e);
            throw new com.lanf.common.ApiException(500, "DAILY_CONTEXT_FAILED", "获取日结数据失败: " + e.getMessage());
        }
    }

    @GetMapping("/pre-check")
    public R precheck(@RequestParam(name = "stat_date", required = false) String stat_date,
                      @RequestParam(name = "date", required = false) String date,
                      @RequestParam(required = false) Integer minutes) {
        String effectiveDate = (stat_date != null && !stat_date.trim().isEmpty()) ? stat_date : date;
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        try {
            Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
            Map<String, Object> res = dailyCloseService.precheck(shopId, adminId, effectiveDate, minutes);
            return R.ok(res);
        } catch (com.lanf.common.ApiException e) {
            throw e;
        } catch (Exception e) {
            log.error("日结预检失败 shopId={} stat_date={}: {}", shopId, effectiveDate, e.getMessage(), e);
            throw new com.lanf.common.ApiException(500, "DAILY_PRECHECK_FAILED", "日结预检失败: " + e.getMessage());
        }
    }

    /**
     * 一键作废超过指定时长（默认 30 分钟）的未支付打包/外卖单
     */
    @PostMapping("/void-stale-takeout-orders")
    public R voidStaleTakeoutOrders(@RequestBody(required = false) Map<String, Object> body) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        try {
            Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
            String statDate = body != null && body.get("stat_date") != null ? String.valueOf(body.get("stat_date")) : null;
            Integer minutes = null;
            if (body != null && body.get("minutes") != null) {
                try {
                    minutes = Integer.parseInt(String.valueOf(body.get("minutes")));
                } catch (NumberFormatException ignored) {}
            }
            Map<String, Object> res = dailyCloseService.voidStalePackTakeoutOrders(shopId, adminId, statDate, minutes);
            return R.ok(res);
        } catch (com.lanf.common.ApiException e) {
            throw e;
        } catch (Exception e) {
            log.error("一键作废超时打包外卖单失败 shopId={}: {}", shopId, e.getMessage(), e);
            throw new com.lanf.common.ApiException(500, "VOID_STALE_TAKEOUT_FAILED", "一键作废超时打包外卖单失败: " + e.getMessage());
        }
    }

    @PostMapping("/settle")
    public R settle(@RequestBody(required = false) Map<String, Object> body) {
        String statDateStr = body != null && body.get("stat_date") != null
                ? String.valueOf(body.get("stat_date")) : null;
        String precheckToken = body != null && body.get("precheck_token") != null
                ? String.valueOf(body.get("precheck_token")) : null;
        String password = body != null && body.get("password") != null
                ? String.valueOf(body.get("password")) : null;
        boolean force = body != null && Boolean.TRUE.equals(body.get("force"));
        String idempotencyKey = body != null && body.get("idempotency_key") != null
                ? String.valueOf(body.get("idempotency_key")) : null;

        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        try {
            Map<String, Object> settleRes = dailyCloseService.settle(
                    shopId, adminId, statDateStr, precheckToken, password, force, idempotencyKey
            );
            com.lanf.entity.DailyCloseSnapshot snapshot = (com.lanf.entity.DailyCloseSnapshot) settleRes.get("snapshot");
            return R.ok()
                    .put("dailyStat", settleRes.get("dailyStat"))
                    .put("snapshot", settleRes.get("snapshot"))
                    .put("idempotent", settleRes.get("idempotent"))
                    .put("message", settleRes.get("message"))
                    .put("trace_id", request.getAttribute(SysInterceptor.ATTR_TRACE_ID))
                    .put("business_no", snapshot != null ? snapshot.getSnapshot_no() : null)
                    .put("server_time", java.time.OffsetDateTime.now(java.time.ZoneOffset.ofHours(8)).toString());
        } catch (com.lanf.common.ApiException e) {
            throw e;
        } catch (Exception e) {
            log.error("日结关账失败 shopId={} statDate={}: {}", shopId, statDateStr, e.getMessage(), e);
            throw new com.lanf.common.ApiException(500, "DAILY_CLOSE_FAILED", "日结关账失败: " + e.getMessage());
        }
    }

    @GetMapping("/z-report")
    public R zReport(@RequestParam(required = false) String stat_date) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        try {
            Map<String, Object> res = dailyCloseService.generateZReport(shopId, stat_date);
            return R.ok().put("zReport", res);
        } catch (com.lanf.common.ApiException e) {
            throw e;
        } catch (Exception e) {
            throw new com.lanf.common.ApiException(500, "Z_REPORT_FAILED", "获取Z报表失败");
        }
    }

    @GetMapping("/z-reports")
    public R zReports(@RequestParam(name = "shop_id", required = false) Integer ignoredShopId,
                      @RequestParam(name = "date_from", required = false) String dateFrom,
                      @RequestParam(name = "date_to", required = false) String dateTo,
                      @RequestParam(required = false) Long cursor,
                      @RequestParam(required = false) Integer limit) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null) {
            shopId = ignoredShopId;
        }
        try {
            return R.ok(dailyCloseService.listZReports(shopId, dateFrom, dateTo, cursor, limit));
        } catch (com.lanf.common.ApiException e) {
            throw e;
        } catch (Exception e) {
            log.error("获取历史Z报表失败 shopId={} dateFrom={} dateTo={}", shopId, dateFrom, dateTo, e);
            throw new com.lanf.common.ApiException(500, "Z_REPORTS_FAILED", "获取历史Z报表失败: " + e.getMessage());
        }
    }

    @PostMapping("/adjustments")
    public R addAdjustment(@RequestBody Map<String, Object> body) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        if (body == null || body.get("snapshot_id") == null || body.get("amount") == null) {
            return R.error("缺少必填参数 snapshot_id 或 amount");
        }
        Long snapshotId = Long.valueOf(String.valueOf(body.get("snapshot_id")));
        double amountYuan = Double.parseDouble(String.valueOf(body.get("amount")));
        int amountFen = (int) Math.round(amountYuan * 100);
        String type = body.get("type") != null ? String.valueOf(body.get("type")) : null;
        Long orderId = body.get("order_id") != null ? Long.valueOf(String.valueOf(body.get("order_id"))) : null;
        Long ledgerId = body.get("ledger_id") != null ? Long.valueOf(String.valueOf(body.get("ledger_id"))) : null;
        String reason = body.get("reason") != null ? String.valueOf(body.get("reason")) : "日结后调整";
        Integer approvedBy = body.get("approved_by") != null ? Integer.valueOf(String.valueOf(body.get("approved_by"))) : null;

        try {
            com.lanf.entity.DailyAdjustment adj = dailyCloseService.recordAdjustment(
                    shopId, adminId, snapshotId, type, amountFen, orderId, ledgerId, reason, approvedBy
            );
            return R.ok().put("adjustment", adj);
        } catch (com.lanf.common.ApiException e) {
            return R.error(e.getHttpStatus(), e.getMessage());
        } catch (Exception e) {
            return R.error("记录调整失败：" + e.getMessage());
        }
    }

    @GetMapping("/adjustments")
    public R getAdjustments(@RequestParam(required = false) String stat_date) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        try {
            Map<String, Object> res = dailyCloseService.getAdjustments(shopId, stat_date);
            return R.ok(res);
        } catch (Exception e) {
            return R.error("获取日结调整记录失败：" + e.getMessage());
        }
    }

    @PostMapping("/reopen")
    public R reopen(@RequestBody Map<String, Object> body) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        Integer adminId = (Integer) request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        String statDate = body != null && body.get("stat_date") != null ? String.valueOf(body.get("stat_date")) : null;
        String password = body != null && body.get("password") != null ? String.valueOf(body.get("password")) : null;
        String reason = body != null && body.get("reason") != null ? String.valueOf(body.get("reason")) : null;

        try {
            Map<String, Object> res = dailyCloseService.reopen(shopId, adminId, statDate, password, reason);
            return R.ok(res);
        } catch (com.lanf.common.ApiException e) {
            throw e;
        } catch (Exception e) {
            throw new com.lanf.common.ApiException(500, "DAILY_REOPEN_FAILED", "重开日结失败：" + e.getMessage());
        }
    }

    @GetMapping("/summary")
    public R summary(@RequestParam(name = "stat_date", required = false) String stat_date,
                     @RequestParam(name = "date", required = false) String date) {
        String effectiveDate = (stat_date != null && !stat_date.trim().isEmpty()) ? stat_date : date;
        LocalDate settlementDay;
        try {
            settlementDay = resolveSettlementDay(effectiveDate);
        } catch (Exception e) {
            return R.error("日期格式错误");
        }
        Date d = java.sql.Date.valueOf(settlementDay);
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        QueryWrapper<DailyStat> q = new QueryWrapper<DailyStat>()
                .eq("stat_date", d).eq(shopId != null, "shop_id", shopId);
        DailyStat one = dailyStatService.getOne(q);
        // 连锁升级前日结为全库一条且 shop_id 为 NULL；当前端按门店查时兼容回落到未分门店汇总
        if (one == null && shopId != null) {
            one = dailyStatService.getOne(new QueryWrapper<DailyStat>().eq("stat_date", d).isNull("shop_id"));
        }
        if (one == null) {
            // 未日结：实时汇总营业日窗口内已结订单（与看板营业日营收同口径），结算时间为空
            Date[] win = settlementWindow(effectiveDate, settlementDay);
            List<Order> orders = orderService.list(businessDayOrderQuery(win, shopId));
            double total = orders.stream().mapToDouble(OrderNetRevenue::netRevenueYuan).sum();
            double discount = orders.stream().mapToDouble(o ->
                    o.getDiscount_amount() != null ? o.getDiscount_amount() : 0).sum();
            double refund = orders.stream().mapToDouble(o ->
                    o.getRefund_amount() != null ? o.getRefund_amount() : 0).sum();
            Map<String, Object> live = new LinkedHashMap<>();
            live.put("total_amount", total);
            live.put("discount_amount", discount);
            live.put("refund_amount", refund);
            live.put("material_cost", 0d);
            live.put("settled_at", null);
            live.put("settled", false);
            return R.ok().put("summary", live).put("income", total).put("deduction", discount);
        }
        return R.ok().put("summary", one).put("income", one.getTotal_amount()).put("deduction", one.getDiscount_amount());
    }

    @GetMapping("/income")
    public R income(@RequestParam(name = "stat_date", required = false) String stat_date,
                    @RequestParam(name = "date", required = false) String date) {
        String effectiveDate = (stat_date != null && !stat_date.trim().isEmpty()) ? stat_date : date;
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        LocalDate settlementDay;
        try {
            settlementDay = resolveSettlementDay(effectiveDate);
        } catch (Exception e) {
            return R.error("日期格式错误，应为 yyyy-MM-dd");
        }
        Date[] win = settlementWindow(effectiveDate, settlementDay);
        QueryWrapper<Order> oq = new QueryWrapper<Order>()
                .eq("transac_status", "success")
                .ge("order_time", win[0]).lt("order_time", win[1]);
        if (shopId != null) {
            oq.eq("shop_id", shopId);
        }
        List<Order> list = orderService.list(oq);
        Map<String, Double> byChannel = new LinkedHashMap<>();
        for (Order o : list) {
            String ch = PaymentChannelCatalog.reportingLabel(
                    PaymentChannelCatalog.reportingCode(o.getPayment_method(), o.getPayment_method()));
            byChannel.put(ch, byChannel.getOrDefault(ch, 0.0) + OrderNetRevenue.netRevenueYuan(o));
        }
        return R.ok().put("list", byChannel);
    }

    @GetMapping("/byChannel")
    public R byChannel(@RequestParam(name = "stat_date", required = false) String stat_date,
                       @RequestParam(name = "date", required = false) String date) {
        String effectiveDate = (stat_date != null && !stat_date.trim().isEmpty()) ? stat_date : date;
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        LocalDate settlementDay;
        try {
            settlementDay = resolveSettlementDay(effectiveDate);
        } catch (Exception e) {
            return R.error("日期格式错误，应为 yyyy-MM-dd");
        }
        Date[] win = settlementWindow(effectiveDate, settlementDay);

        String readSource = ledgerMigrationService.getReadSource(shopId);
        if (com.lanf.service.ILedgerMigrationService.READ_SOURCE_PAYMENT_LEDGER.equals(readSource)) {
            // POS-SDC-503: 弃用旧 t_payment 孤立表读取，统一切换至不可变支付台账 t_payment_ledger
            QueryWrapper<com.lanf.entity.PaymentLedger> lq = new QueryWrapper<com.lanf.entity.PaymentLedger>()
                    .eq("status", com.lanf.entity.PaymentLedger.STATUS_SUCCEEDED)
                    .ge("occurred_at", win[0]).lt("occurred_at", win[1]);
            if (shopId != null && shopId > 0) {
                lq.eq("shop_id", shopId);
            }
            List<com.lanf.entity.PaymentLedger> ledgers = paymentLedgerMapper.selectList(lq);
            Map<String, String> paymentMethods = loadPaymentMethods(ledgers, shopId);
            Map<String, BigDecimal> sum = new LinkedHashMap<>();
            for (com.lanf.entity.PaymentLedger l : ledgers) {
                String ch = PaymentChannelCatalog.reportingLabel(
                        PaymentChannelCatalog.reportingCode(
                                l.getChannel(), paymentMethods.get(l.getOrder_no())));
                BigDecimal amt = BigDecimal.valueOf(l.getAmount_fen()).divide(BigDecimal.valueOf(100), 2, java.math.RoundingMode.HALF_UP);
                sum.put(ch, sum.getOrDefault(ch, BigDecimal.ZERO).add(amt));
            }
            attachReceivableChannelIfAny(sum, win, shopId);
        return R.ok().put("channels", sum);
        }

        // 仅在显式配置 LEGACY_ORDER 时保留回退兼容
        QueryWrapper<Payment> q = new QueryWrapper<Payment>()
                .ge("pay_time", win[0]).lt("pay_time", win[1]);
        if (shopId != null) {
            q.eq("shop_id", shopId);
        }
        List<Payment> list = paymentService.list(q);
        Map<String, BigDecimal> sum = new LinkedHashMap<>();
        for (Payment payment : list) {
            String channel = PaymentChannelCatalog.reportingLabel(
                    PaymentChannelCatalog.reportingCode(
                            payment.getPayment_method(), payment.getPayment_method()));
            sum.put(channel, sum.getOrDefault(channel, BigDecimal.ZERO).add(payment.getAmount()));
        }
        attachReceivableChannelIfAny(sum, win, shopId);
        return R.ok().put("channels", sum);
    }

    private Map<String, String> loadPaymentMethods(
            List<com.lanf.entity.PaymentLedger> ledgers, Integer shopId) {
        Map<String, String> methods = new HashMap<>();
        Set<String> orderNos = ledgers.stream()
                .map(com.lanf.entity.PaymentLedger::getOrder_no)
                .filter(Objects::nonNull)
                .collect(Collectors.toCollection(LinkedHashSet::new));
        if (orderNos.isEmpty()) return methods;
        QueryWrapper<Order> query = new QueryWrapper<Order>().in("order_no", orderNos);
        if (shopId != null && shopId > 0) query.eq("shop_id", shopId);
        List<Order> orders = orderService.list(query);
        if (orders == null) return methods;
        for (Order order : orders) {
            if (order != null && order.getOrder_no() != null) {
                methods.put(order.getOrder_no(), order.getPayment_method());
            }
        }
        return methods;
    }

    @GetMapping("/grossProfit")
    public R grossProfit(@RequestParam(name = "stat_date", required = false) String stat_date,
                         @RequestParam(name = "date", required = false) String date) {
        String effectiveDate = (stat_date != null && !stat_date.trim().isEmpty()) ? stat_date : date;
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        LocalDate settlementDay;
        try {
            settlementDay = resolveSettlementDay(effectiveDate);
        } catch (Exception e) {
            return R.error("日期格式错误，应为 yyyy-MM-dd");
        }
        Date[] win = settlementWindow(effectiveDate, settlementDay);
        QueryWrapper<Order> q = new QueryWrapper<Order>().eq("transac_status", "success")
                .ge("order_time", win[0]).lt("order_time", win[1]);
        if (shopId != null) {
            q.eq("shop_id", shopId);
        }
        List<Order> list = orderService.list(q);
        double revenue = list.stream().mapToDouble(OrderNetRevenue::netRevenueYuan).sum();
        Date statDate = java.sql.Date.valueOf(settlementDay);
        QueryWrapper<DailyStat> dsq = new QueryWrapper<DailyStat>().eq("stat_date", statDate).eq(shopId != null, "shop_id", shopId);
        DailyStat ds = dailyStatService.getOne(dsq);
        if (ds == null && shopId != null) {
            ds = dailyStatService.getOne(new QueryWrapper<DailyStat>().eq("stat_date", statDate).isNull("shop_id"));
        }
        BigDecimal materialCost = ds != null ? ds.getMaterial_cost() : null;
        double cost = materialCost != null ? materialCost.doubleValue() : 0;
        return R.ok().put("revenue", revenue).put("materialCost", cost).put("grossProfit", revenue - cost);
    }

    /** 未指定日期时使用当前活动营业班次；指定日期按历史结算日查询。 */
    private LocalDate resolveSettlementDay(String date) {
        return resolveSettlementDay(resolveDailyShop(), date, LocalDateTime.now());
    }

    static LocalDate resolveSettlementDay(Shop shop, String date, LocalDateTime now) {
        if (date == null || date.trim().isEmpty()) {
            return currentSettlementDay(shop, now);
        }
        String s = date.trim();
        if (s.length() >= 10 && s.charAt(4) == '-' && s.charAt(7) == '-') {
            s = s.substring(0, 10);
        }
        return LocalDate.parse(s);
    }

    static LocalDate currentSettlementDay(Shop shop, LocalDateTime now) {
        return ShopBusinessWindowResolver.operationalBusinessDay(shop, now);
    }

    /** 实时/已结算统计窗口：未指定日期使用当前活动班次 24h 窗口；指定日期使用该结算日的 24h 窗口 [D-1, D)。 */
    private Date[] settlementWindow(String date, LocalDate settlementDay) {
        Shop shop = resolveDailyShop();
        if (date == null || date.trim().isEmpty()) {
            return ShopBusinessWindowResolver.operationalWindow(shop);
        }
        return ShopBusinessWindowResolver.settlementWindowFor(shop, settlementDay);
    }

    /**
     * 结算日订单查询条件（与看板 /admin/report/dashboard 与财务实收口径一致）：
     * transac_status=success、merchantId=1、财务入账时间落在营业窗口、
     * order_receiving IN (rec_order, off_order) 或 NULL。
     */
    private QueryWrapper<Order> businessDayOrderQuery(Date[] win, Integer shopId) {
        QueryWrapper<Order> q = new QueryWrapper<Order>()
                .eq("transac_status", "success")
                .eq("merchantId", 1)
                .and(w -> w.ge("pay_time", win[0]).lt("pay_time", win[1])
                        .or(ow -> ow.isNull("pay_time").ge("order_time", win[0]).lt("order_time", win[1])))
                .and(qw -> qw.in("order_receiving", "rec_order", "off_order")
                        .or().isNull("order_receiving"));
        if (shopId != null) {
            q.eq("shop_id", shopId);
        }
        return q;
    }

    /** 当前日结作用门店：X-Shop-Id 解析的门店；HQ（无门店）取 id 最小门店；读取失败返回 null（回退默认时段）。 */
    private Shop resolveDailyShop() {
        try {
            Integer shopId = AdminShopRequest.getResolvedShopId(request);
            if (shopId != null) {
                Shop s = shopService.getById(shopId);
                if (s != null) {
                    return s;
                }
            }
            QueryWrapper<Shop> sq = new QueryWrapper<Shop>().orderByAsc("id").last("limit 1");
            return shopService.getOne(sq, false);
        } catch (Exception e) {
            return null;
        }
    }

    private void attachReceivableChannelIfAny(Map<String, BigDecimal> sum, Date[] win, Integer shopId) {
        if (orderService == null) return;
        QueryWrapper<Order> creditQ = businessDayOrderQuery(win, shopId)
                .eq("payment_method", ReceivableService.PAYMENT_METHOD_RECEIVABLE);
        List<Order> creditOrders = orderService.list(creditQ);
        if (creditOrders != null && !creditOrders.isEmpty()) {
            double creditTotal = creditOrders.stream().mapToDouble(OrderNetRevenue::netRevenueYuan).sum();
            if (creditTotal > 0) {
                sum.put(PaymentChannelCatalog.NAME_RECEIVABLE,
                        BigDecimal.valueOf(creditTotal).setScale(2, java.math.RoundingMode.HALF_UP));
            }
        }
    }
}

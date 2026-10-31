package com.lanf.controller.admin;

import com.lanf.dto.DishSalesDTO;
import com.lanf.payment.support.PaymentChannelCatalog;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.controller.admin.AdminOrderController;
import com.lanf.entity.*;
import com.lanf.report.service.ReportOrderAggregate;
import com.lanf.receivable.model.ReceivableWindowSummary;
import com.lanf.receivable.service.ReceivableService;
import com.lanf.service.*;
import com.lanf.util.AdminShopRequest;
import com.lanf.util.OrderNetRevenue;
import com.lanf.util.ShopBusinessWindowResolver;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeParseException;
import java.util.*;

/**
 * 数据报表（收银系统扩展，部分复用 AdminOrderController 统计）
 */
@RestController
@RequestMapping("/admin/report")
public class AdminReportController {

    private static final Logger log = LoggerFactory.getLogger(AdminReportController.class);

    @Autowired
    private IOrderService orderService;
    @Autowired
    private IUserService userService;
    @Autowired
    private AdminOrderController adminOrderController;
    @Autowired
    private IStockInService stockInService;
    @Autowired
    private IStockOutService stockOutService;
    @Autowired
    private IMaterialService materialService;
    @Autowired
    private HttpServletRequest httpServletRequest;
    @Autowired
    private IMemberRechargeService memberRechargeService;
    @Autowired
    private AdminMemberController adminMemberController;
    @Autowired
    private StockPrepForecastService stockPrepForecastService;
    @Autowired
    private StockPrepForecastValidationService stockPrepForecastValidationService;
    @Autowired
    private IShopService shopService;
    @Autowired
    private ReportOrderAggregate reportOrderAggregate;
    @Autowired(required = false)
    private IDailyCloseService dailyCloseService;
    @Autowired(required = false)
    private ReceivableService receivableService;
    @Autowired(required = false)
    private IAnalyticsService analyticsService;
    @Autowired(required = false)
    private com.lanf.security.AdminShopScopeGuard adminShopScopeGuard;
    @Autowired(required = false)
    private com.lanf.service.IShopMemberWalletService shopMemberWalletService;

    /**
     * 未来若干天菜品份数备货预测；{@code persist=true} 时落库并返回 {@code runId}。
     * 法定节假日/调休补班以 {@code holidays/cn-public-holidays.json} 为准（可配置路径）。
     * 门店范围与 {@link #applyShopScope} 一致（依赖请求解析出的 X-Shop-Id）。
     * 另见 {@link #stockPrepForecastLatest()}、{@link #stockPrepForecastByRunId(Long)}。
     */
    @GetMapping("/stockPrepForecast")
    public R stockPrepForecast(
            @RequestParam(required = false) Integer historyDays,
            @RequestParam(required = false) Integer forecastDays,
            @RequestParam(defaultValue = "false") boolean persist) {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        Map<String, Object> payload = stockPrepForecastService.buildForecast(shopId, historyDays, forecastDays, persist);
        return R.ok().put("forecast", payload);
    }

    @GetMapping("/stockPrepForecast/latest")
    public R stockPrepForecastLatest() {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        Map<String, Object> payload = stockPrepForecastService.getLatestSavedForecast(shopId);
        if (payload == null) {
            return R.error("暂无落库记录");
        }
        return R.ok().put("forecast", payload);
    }

    @GetMapping("/stockPrepForecast/run/{runId}")
    public R stockPrepForecastByRunId(@PathVariable Long runId) {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        try {
            Map<String, Object> payload = stockPrepForecastService.getSavedForecastByRunId(runId, shopId);
            if (payload == null) {
                return R.error("记录不存在");
            }
            return R.ok().put("forecast", payload);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }

    /**
     * 将预测日与订单实际、日结 t_daily_stat 对账并写回预测表（仅处理已过去的自然日）。
     */
    @PostMapping("/stockPrepForecast/run/{runId}/validate")
    public R stockPrepForecastValidate(
            @PathVariable Long runId,
            @RequestParam(defaultValue = "false") boolean force) {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        try {
            Map<String, Object> result = stockPrepForecastValidationService.validateRun(runId, shopId, force);
            return R.ok().put("result", result);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }

    /**
     * 导出单批次 ML 训练样本（扁平行：日特征 + 菜品预测 + label_actual_quantity 等）。
     */
    @GetMapping("/stockPrepForecast/trainingRows")
    public R stockPrepForecastTrainingRows(@RequestParam Long runId) {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        try {
            Map<String, Object> data = stockPrepForecastValidationService.exportTrainingRows(runId, shopId);
            return R.ok().put("data", data);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }

    @GetMapping("/daily")
    public R daily(@RequestParam(required = false) String date,
                   @RequestParam(required = false) String startDate,
                   @RequestParam(required = false) String startTime,
                   @RequestParam(required = false) String start,
                   @RequestParam(required = false, defaultValue = "false") boolean detail) {
        String candidate = firstNonEmpty(date, startDate, startTime, start);
        LocalDate day;
        Shop shop = resolveReportShop();
        if (candidate == null || candidate.trim().isEmpty()) {
            day = ShopBusinessWindowResolver.completedSettlementDay(shop, LocalDateTime.now());
        } else {
            day = ShopBusinessWindowResolver.parseReportDate(candidate);
        }
        if (detail) {
            return buildComprehensiveDailyReport(shop, day);
        }
        return aggregateBusinessReport(day, day, day.toString());
    }

    public R daily(String date) {
        return daily(date, null, null, null, false);
    }

    @GetMapping("/weekly")
    public R weekly(@RequestParam(required = false) String startDate,
                    @RequestParam(required = false) String endDate,
                    @RequestParam(required = false) String startTime,
                    @RequestParam(required = false) String endTime,
                    @RequestParam(required = false) String start,
                    @RequestParam(required = false) String end) {
        String startCandidate = firstNonEmpty(startDate, startTime, start);
        String endCandidate = firstNonEmpty(endDate, endTime, end);
        LocalDate startDay;
        LocalDate endDay;
        if (startCandidate == null || startCandidate.trim().isEmpty() || endCandidate == null || endCandidate.trim().isEmpty()) {
            String[] def = defaultWeekRange();
            startDay = LocalDate.parse(def[0]);
            endDay = LocalDate.parse(def[1]);
        } else {
            startDay = ShopBusinessWindowResolver.parseReportDate(startCandidate);
            endDay = ShopBusinessWindowResolver.parseReportDate(endCandidate);
        }
        return aggregateBusinessReport(startDay, endDay, startDay + "~" + endDay);
    }

    public R weekly(String startDate, String endDate) {
        return weekly(startDate, endDate, null, null, null, null);
    }

    @GetMapping("/monthly")
    public R monthly(@RequestParam Integer year, @RequestParam Integer month) {
        LocalDate start = LocalDate.of(year, month, 1);
        LocalDate end = start.withDayOfMonth(start.lengthOfMonth());
        return aggregateBusinessReport(start, end, String.format("%04d-%02d", year, month));
    }

    /**
     * 复用现有报表接口的内部聚合入口。显式日期均为营业日起始日期，窗口由各门店
     * {@code settle_time} 解析；总部无单店上下文时逐店按各自窗口聚合后求和。
     */
    private R aggregateBusinessReport(LocalDate startDay, LocalDate endDay, String label) {
        if (endDay.isBefore(startDay)) {
            return R.error(400, "结束营业日不能早于开始营业日");
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        List<Shop> shops;
        if (shopId != null) {
            Shop shop = shopService.getById(shopId);
            if (shop == null) {
                return R.error(400, "门店不存在或无权访问");
            }
            shops = Collections.singletonList(shop);
        } else {
            shops = shopService.list();
            if (shops == null || shops.isEmpty()) {
                return R.error(400, "暂无可统计门店");
            }
        }

        long orderCount = 0L;
        BigDecimal totalAmount = BigDecimal.ZERO;
        BigDecimal grossRevenue = BigDecimal.ZERO;
        BigDecimal totalDiscount = BigDecimal.ZERO;
        BigDecimal totalRefund = BigDecimal.ZERO;
        long receivableChargedFen = 0L;
        long receivableCollectedFen = 0L;
        long receivableWriteoffFen = 0L;
        long receivableReversedFen = 0L;
        long receivableOutstandingFen = 0L;
        long receivableCutoffLedgerId = 0L;
        long totalCollectionsFen = 0L;
        boolean singleBusinessDay = startDay.equals(endDay);
        for (Shop shop : shops) {
            String[] window = ShopBusinessWindowResolver.settlementWindowRangeText(shop, startDay, endDay);
            List<String> row = reportOrderAggregate.row(shop.getId(), label, window[0], window[1]);
            orderCount += Long.parseLong(row.get(1));
            grossRevenue = grossRevenue.add(new BigDecimal(row.get(2)));
            totalAmount = totalAmount.add(new BigDecimal(row.get(3)));
            totalDiscount = totalDiscount.add(new BigDecimal(row.get(4)));
            totalRefund = totalRefund.add(new BigDecimal(row.get(6)));
            if (singleBusinessDay) {
                Map<String, Object> closeReport = null;
                if (dailyCloseService != null) {
                    try {
                        closeReport = dailyCloseService.generateZReport(shop.getId(), startDay.toString());
                    } catch (RuntimeException ignored) {
                    }
                }
                Date[] dates = ShopBusinessWindowResolver.settlementWindowFor(shop, startDay);
                Map<String, Object> receivable = receivableSummaryForReport(closeReport, shop.getId(), dates);
                receivableChargedFen += mapLong(receivable, "chargedFen");
                receivableCollectedFen += mapLong(receivable, "collectedFen");
                receivableWriteoffFen += mapLong(receivable, "writeoffFen");
                receivableReversedFen += mapLong(receivable, "reversedFen");
                receivableOutstandingFen += mapLong(receivable, "outstandingFen");
                receivableCutoffLedgerId = Math.max(receivableCutoffLedgerId,
                        mapLong(receivable, "cutoffLedgerId"));
                if (closeReport != null && closeReport.get("total_collections_fen") instanceof Number) {
                    totalCollectionsFen += ((Number) closeReport.get("total_collections_fen")).longValue();
                } else {
                    totalCollectionsFen += new BigDecimal(row.get(3)).movePointRight(2).longValue()
                            - mapLong(receivable, "chargedFen")
                            + mapLong(receivable, "reversedFen")
                            + mapLong(receivable, "collectedFen");
                }
            }
        }

        Map<String, Object> report = new LinkedHashMap<>();
        report.put("totalAmount", totalAmount.doubleValue());
        report.put("orderCount", orderCount);
        report.put("grossRevenue", grossRevenue.doubleValue());
        report.put("netRevenue", totalAmount.doubleValue());
        report.put("totalDiscount", totalDiscount.doubleValue());
        report.put("totalRefund", totalRefund.doubleValue());
        if (singleBusinessDay) {
            Map<String, Object> receivable = new LinkedHashMap<>();
            receivable.put("chargedFen", receivableChargedFen);
            receivable.put("collectedFen", receivableCollectedFen);
            receivable.put("writeoffFen", receivableWriteoffFen);
            receivable.put("reversedFen", receivableReversedFen);
            receivable.put("outstandingFen", receivableOutstandingFen);
            receivable.put("cutoffLedgerId", receivableCutoffLedgerId);
            report.put("receivableSummary", receivable);
            report.put("totalCollectionsFen", totalCollectionsFen);
            report.put("totalCollections", round2Money(totalCollectionsFen / 100.0d));
        }
        return R.ok().put("report", report);
    }

    /**
     * 构建商业级 8 维度全量日结营业报告。
     */
    private R buildComprehensiveDailyReport(Shop shop, LocalDate day) {
        if (shop == null) {
            shop = resolveReportShop();
            if (shop == null) {
                shop = new Shop();
                shop.setId(1);
                shop.setSettle_time("04:00");
                shop.setName("收银门店");
            }
        }
        Integer shopId = shop.getId();
        String businessDay = day.toString();
        String[] win = ShopBusinessWindowResolver.settlementWindowRangeText(shop, day, day);
        Date[] winDates = ShopBusinessWindowResolver.settlementWindowFor(shop, day);

        // 1. Z-Report / X-Report 快照与对账数据（优先调用 dailyCloseService）
        Map<String, Object> zReport = null;
        if (dailyCloseService != null) {
            try {
                zReport = dailyCloseService.generateZReport(shopId, businessDay);
            } catch (Exception ignored) {
            }
        }

        boolean isClosed = zReport != null && Boolean.TRUE.equals(zReport.get("is_closed"));
        String reportType = isClosed ? "Z_REPORT" : "X_REPORT";
        String snapshotNo = zReport != null && zReport.get("snapshot_no") != null
                ? String.valueOf(zReport.get("snapshot_no")) : "X-PREVIEW-" + businessDay;
        String operatorName = zReport != null && zReport.get("operator_name") != null
                ? String.valueOf(zReport.get("operator_name")) : "系统实时汇总";
        Date closedAt = zReport != null && zReport.get("closed_at") instanceof Date
                ? (Date) zReport.get("closed_at") : null;

        // 2. 查订单明细
        QueryWrapper<Order> orderQ = new QueryWrapper<Order>()
                .eq("transac_status", "success")
                .eq("merchantId", "1")
                .and(w -> w.ge("pay_time", winDates[0]).lt("pay_time", winDates[1])
                        .or(ow -> ow.isNull("pay_time").ge("order_time", winDates[0]).lt("order_time", winDates[1])))
                .and(qw -> qw.in("order_receiving", "rec_order", "off_order").or().isNull("order_receiving"));
        if (shopId != null) {
            orderQ.eq("shop_id", shopId);
        }
        List<Order> orders = orderService != null ? orderService.list(orderQ) : Collections.emptyList();
        if (orders == null) {
            orders = Collections.emptyList();
        }

        // 营收核心指标
        double netRevenue = orders.stream().mapToDouble(OrderNetRevenue::netRevenueYuan).sum();
        double discountAmount = orders.stream().mapToDouble(o -> o.getDiscount_amount() != null ? o.getDiscount_amount() : 0d).sum();
        double refundAmount = orders.stream().mapToDouble(o -> o.getRefund_amount() != null ? o.getRefund_amount() : 0d).sum();
        double grossRevenue = orders.stream().mapToDouble(o -> (o.getSett_amount() != null ? o.getSett_amount() : 0d) + (o.getService_fee() != null ? o.getService_fee() : 0d)).sum();
        if (grossRevenue == 0d && (!orders.isEmpty() || netRevenue > 0)) {
            grossRevenue = netRevenue + discountAmount;
        }

        long orderCount = orders.size();
        long dinerCount = orders.stream().mapToLong(o -> {
            if (o.getNumber_of_diners() == null) return 0L;
            try {
                return Long.parseLong(o.getNumber_of_diners().trim());
            } catch (Exception e) {
                return 0L;
            }
        }).sum();
        if (dinerCount == 0L && orderCount > 0) {
            dinerCount = orderCount;
        }
        double avgOrderAmount = orderCount > 0 ? round2Money(netRevenue / orderCount) : 0d;
        double avgDinerAmount = dinerCount > 0 ? round2Money(netRevenue / dinerCount) : 0d;

        // 翻台率 (以 analyticsMapper 或堂食订单估算)
        double tableTurnoverRate = 0d;
        try {
            if (analyticsService != null) {
                Map<String, Object> bizOverview = analyticsService.businessOverview(win[0], win[1], shopId);
                if (bizOverview != null) {
                    Map<String, Object> bizDerived = (Map<String, Object>) bizOverview.get("business_day");
                    if (bizDerived != null && bizDerived.get("derived") instanceof Map) {
                        Map<String, Object> derived = (Map<String, Object>) bizDerived.get("derived");
                        tableTurnoverRate = mapDouble(derived, "table_turnover_per_table_per_day");
                    }
                }
            }
        } catch (Exception ignored) {}

        // 3. 支付渠道实收明细
        List<Map<String, Object>> paymentChannels = new ArrayList<>();
        if (zReport != null && zReport.get("channels") instanceof List) {
            List<?> chList = (List<?>) zReport.get("channels");
            for (Object obj : chList) {
                if (obj instanceof Map) {
                    Map<?, ?> m = (Map<?, ?>) obj;
                    Object codeValue = m.get("code") != null ? m.get("code") : m.get("channel_code");
                    Object nameValue = m.get("label") != null ? m.get("label") : m.get("channel_name");
                    String code = codeValue != null ? String.valueOf(codeValue) : "other";
                    String name = nameValue != null ? String.valueOf(nameValue)
                            : PaymentChannelCatalog.reportingLabel(code);
                    long netFen = mapLong((Map<String, Object>) m, "net_amount_fen");
                    int successCount = (int) mapLong((Map<String, Object>) m, "success_count");
                    int refundCount = (int) mapLong((Map<String, Object>) m, "refund_count");
                    double amt = round2Money(netFen / 100.0);
                    double pct = netRevenue > 0 ? round2Money((amt / netRevenue) * 100.0) : 0d;
                    Map<String, Object> chRow = new LinkedHashMap<>();
                    chRow.put("channelCode", code);
                    chRow.put("channelLabel", name);
                    chRow.put("amount", amt);
                    chRow.put("orderCount", successCount);
                    chRow.put("refundCount", refundCount);
                    chRow.put("percentage", Math.max(0d, pct));
                    paymentChannels.add(chRow);
                }
            }
        } else {
            Map<String, Double> chanSums = new LinkedHashMap<>();
            Map<String, Integer> chanCounts = new LinkedHashMap<>();
            for (Order o : orders) {
                if (ReceivableService.PAYMENT_METHOD_RECEIVABLE.equals(o.getPayment_method())) {
                    continue;
                }
                String ch = PaymentChannelCatalog.reportingCode(o.getPayment_method(), o.getPayment_method());
                String label = PaymentChannelCatalog.reportingLabel(ch);
                chanSums.put(label, chanSums.getOrDefault(label, 0d) + OrderNetRevenue.netRevenueYuan(o));
                chanCounts.put(label, chanCounts.getOrDefault(label, 0) + 1);
            }
            chanSums.forEach((label, amt) -> {
                Map<String, Object> chRow = new LinkedHashMap<>();
                chRow.put("channelCode", label);
                chRow.put("channelLabel", label);
                chRow.put("amount", round2Money(amt));
                chRow.put("orderCount", chanCounts.getOrDefault(label, 0));
                chRow.put("refundCount", 0);
                chRow.put("percentage", netRevenue > 0 ? round2Money((amt / netRevenue) * 100.0) : 0d);
                paymentChannels.add(chRow);
            });
        }

        // 4. 现金与钱箱对账
        Map<String, Object> cashDrawer = new LinkedHashMap<>();
        if (zReport != null && zReport.get("drawer_summary") instanceof Map) {
            Map<?, ?> ds = (Map<?, ?>) zReport.get("drawer_summary");
            double opening = mapLong((Map<String, Object>) ds, "opening_float_fen") / 100.0;
            double counted = mapLong((Map<String, Object>) ds, "counted_cash_fen") / 100.0;
            double variance = mapLong((Map<String, Object>) ds, "total_variance_fen") / 100.0;
            long sessionCount = mapLong((Map<String, Object>) ds, "sessions_count");

            double cashIn = 0d;
            for (Map<String, Object> ch : paymentChannels) {
                if ("cash".equalsIgnoreCase(String.valueOf(ch.get("channelCode"))) || "现金".equals(ch.get("channelLabel"))) {
                    cashIn = mapDouble(ch, "amount");
                }
            }
            double theoretical = opening + cashIn;
            cashDrawer.put("openingFloat", round2Money(opening));
            cashDrawer.put("cashIn", round2Money(cashIn));
            cashDrawer.put("cashRefund", 0d);
            cashDrawer.put("cashOut", 0d);
            cashDrawer.put("theoreticalCash", round2Money(theoretical));
            cashDrawer.put("countedCash", round2Money(counted));
            cashDrawer.put("variance", round2Money(variance));
            cashDrawer.put("sessionCount", sessionCount);
        } else {
            cashDrawer.put("openingFloat", 0d);
            cashDrawer.put("cashIn", 0d);
            cashDrawer.put("cashRefund", 0d);
            cashDrawer.put("cashOut", 0d);
            cashDrawer.put("theoreticalCash", 0d);
            cashDrawer.put("countedCash", 0d);
            cashDrawer.put("variance", 0d);
            cashDrawer.put("sessionCount", 0);
        }

        // 5. 就餐方式与订单类型分布
        List<Map<String, Object>> orderTypes = new ArrayList<>();
        long dineInCount = 0L;
        double dineInAmount = 0d;
        long takeoutCount = 0L;
        double takeoutAmount = 0d;
        long packCount = 0L;
        double packAmount = 0d;

        for (Order o : orders) {
            String dt = o.getDineInOrTakeOut() != null ? o.getDineInOrTakeOut().trim() : "堂食";
            double amt = OrderNetRevenue.netRevenueYuan(o);
            if (dt.contains("外卖")) {
                takeoutCount++;
                takeoutAmount += amt;
            } else if (dt.contains("自提") || dt.contains("打包")) {
                packCount++;
                packAmount += amt;
            } else {
                dineInCount++;
                dineInAmount += amt;
            }
        }

        orderTypes.add(buildOrderTypeRow("dine_in", "堂食就餐", dineInCount, dineInAmount, netRevenue));
        orderTypes.add(buildOrderTypeRow("takeout", "外卖配送", takeoutCount, takeoutAmount, netRevenue));
        orderTypes.add(buildOrderTypeRow("pack", "自提打包", packCount, packAmount, netRevenue));

        // 6. 会员储值与运营
        Map<String, Object> memberMap = new LinkedHashMap<>();
        BigDecimal rechargeTotalBd = BigDecimal.ZERO;
        BigDecimal rechargePrincipalBd = BigDecimal.ZERO;
        BigDecimal rechargeGiftBd = BigDecimal.ZERO;
        long rechargeCount = 0L;

        if (memberRechargeService != null) {
            QueryWrapper<MemberRecharge> mrq = new QueryWrapper<MemberRecharge>()
                    .eq("status", "success")
                    .ge("pay_time", winDates[0]).lt("pay_time", winDates[1]);
            if (shopId != null) {
                mrq.eq("shop_id", shopId);
            }
            List<MemberRecharge> recharges = memberRechargeService.list(mrq);
            if (recharges != null) {
                rechargeCount = recharges.size();
                for (MemberRecharge r : recharges) {
                    if (r.getTotal_amount() != null) rechargeTotalBd = rechargeTotalBd.add(r.getTotal_amount());
                    if (r.getRecharge_amount() != null) rechargePrincipalBd = rechargePrincipalBd.add(r.getRecharge_amount());
                    if (r.getGift_amount() != null) rechargeGiftBd = rechargeGiftBd.add(r.getGift_amount());
                }
            }
        }

        double memberConsumption = 0d;
        for (Order o : orders) {
            if (o.getPay_amount_balance() != null) {
                memberConsumption += o.getPay_amount_balance().doubleValue();
            } else if (o.getPayment_method() != null && o.getPayment_method().contains("余额")) {
                memberConsumption += OrderNetRevenue.netRevenueYuan(o);
            }
        }

        long newMembers = countShopNewMembers(shopId, winDates[0], winDates[1]);

        memberMap.put("rechargeTotal", round2Money(rechargeTotalBd.doubleValue()));
        memberMap.put("rechargePrincipal", round2Money(rechargePrincipalBd.doubleValue()));
        memberMap.put("rechargeGift", round2Money(rechargeGiftBd.doubleValue()));
        memberMap.put("rechargeCount", rechargeCount);
        memberMap.put("memberConsumption", round2Money(memberConsumption));
        memberMap.put("newMembers", newMembers);

        // 7. 异常与风控审计
        Map<String, Object> exceptions = new LinkedHashMap<>();
        long refundOrderCount = orders.stream().filter(o -> o.getRefund_amount() != null && o.getRefund_amount() > 0).count();
        exceptions.put("uncheckoutCount", 0L);
        exceptions.put("uncheckoutAmount", 0d);
        exceptions.put("refundCount", refundOrderCount);
        exceptions.put("refundAmount", round2Money(refundAmount));
        exceptions.put("discountAmount", round2Money(discountAmount));
        exceptions.put("freeDishesCount", 0L);
        exceptions.put("freeDishesAmount", 0d);

        // 8. 菜品热销榜 TOP 10
        List<Map<String, Object>> topDishes = new ArrayList<>();
        try {
            Map<String, Object> dishParams = new HashMap<>();
            dishParams.put("startTime", win[0]);
            dishParams.put("endTime", win[1]);
            if (shopId != null) {
                dishParams.put("shopId", shopId);
                dishParams.put("shop_id", shopId);
            }
            List<DishSalesDTO> dishSales = orderService != null ? orderService.statisticsDishSales(dishParams) : Collections.emptyList();
            if (dishSales != null) {
                dishSales.sort((a, b) -> Long.compare(b.getTotal_quantity() != null ? b.getTotal_quantity() : 0L,
                        a.getTotal_quantity() != null ? a.getTotal_quantity() : 0L));
                int rank = 1;
                for (DishSalesDTO ds : dishSales) {
                    if (rank > 10) break;
                    Map<String, Object> dRow = new LinkedHashMap<>();
                    dRow.put("rank", rank++);
                    dRow.put("dishName", ds.getDish_name());
                    dRow.put("quantity", ds.getTotal_quantity() != null ? ds.getTotal_quantity() : 0L);
                    double dSales = 0d;
                    try {
                        dSales = Double.parseDouble(ds.getTotal_sales());
                    } catch (Exception ignored) {}
                    dRow.put("amount", round2Money(dSales));
                    dRow.put("percentage", netRevenue > 0 ? round2Money((dSales / netRevenue) * 100.0) : 0d);
                    topDishes.add(dRow);
                }
            }
        } catch (Exception ignored) {}

        // 组装 metadata
        Map<String, Object> metadata = new LinkedHashMap<>();
        metadata.put("shopId", shopId);
        metadata.put("shopName", shop.getName() != null ? shop.getName() : "连锁收银门店");
        metadata.put("businessDay", businessDay);
        metadata.put("windowStart", win[0]);
        metadata.put("windowEnd", win[1]);
        metadata.put("generatedAt", LocalDateTime.now().toString());
        metadata.put("isSettled", isClosed);
        metadata.put("reportType", reportType);
        metadata.put("operatorName", operatorName);
        metadata.put("snapshotNo", snapshotNo);
        metadata.put("closedAt", closedAt != null ? closedAt.toString() : null);

        // 组装 summary
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("grossRevenue", round2Money(grossRevenue));
        summary.put("totalDiscount", round2Money(discountAmount));
        summary.put("netRevenue", round2Money(netRevenue));
        summary.put("totalRefund", round2Money(refundAmount));
        summary.put("orderCount", orderCount);
        summary.put("dinerCount", dinerCount);
        summary.put("avgOrderAmount", avgOrderAmount);
        summary.put("avgDinerAmount", avgDinerAmount);
        summary.put("tableTurnoverRate", tableTurnoverRate);

        Map<String, Object> receivableSummary = receivableSummaryForReport(zReport, shopId, winDates);
        long totalCollectionsFen;
        if (zReport != null && zReport.get("total_collections_fen") instanceof Number) {
            totalCollectionsFen = ((Number) zReport.get("total_collections_fen")).longValue();
        } else {
            long paymentCollectionsFen = Math.round(paymentChannels.stream()
                    .mapToDouble(row -> mapDouble(row, "amount")).sum() * 100.0d);
            totalCollectionsFen = paymentCollectionsFen
                    + mapLong(receivableSummary, "collectedFen")
                    + rechargePrincipalBd.movePointRight(2).longValue();
        }
        summary.put("totalCollections", round2Money(totalCollectionsFen / 100.0d));

        // 组装全量 report
        Map<String, Object> report = new LinkedHashMap<>();
        // 兼容顶层字段
        report.put("totalAmount", round2Money(netRevenue));
        report.put("orderCount", orderCount);
        report.put("grossRevenue", round2Money(grossRevenue));
        report.put("netRevenue", round2Money(netRevenue));
        report.put("totalDiscount", round2Money(discountAmount));
        report.put("totalRefund", round2Money(refundAmount));
        report.put("receivableSummary", receivableSummary);
        report.put("totalCollectionsFen", totalCollectionsFen);
        report.put("totalCollections", round2Money(totalCollectionsFen / 100.0d));

        // 8 个模块
        report.put("metadata", metadata);
        report.put("summary", summary);
        report.put("paymentChannels", paymentChannels);
        report.put("cashDrawer", cashDrawer);
        report.put("orderTypes", orderTypes);
        report.put("member", memberMap);
        report.put("exceptions", exceptions);
        report.put("topDishes", topDishes);
        if (zReport != null && zReport.get("printable_text") != null) {
            report.put("printableText", zReport.get("printable_text"));
        }

        return R.ok().put("report", report);
    }

    private Map<String, Object> receivableSummaryForReport(Map<String, Object> zReport,
                                                            Integer shopId,
                                                            Date[] window) {
        Map<String, Object> source = null;
        if (zReport != null && zReport.get("receivable_summary") instanceof Map) {
            @SuppressWarnings("unchecked")
            Map<String, Object> value = (Map<String, Object>) zReport.get("receivable_summary");
            source = value;
        } else if (receivableService != null && shopId != null) {
            ReceivableWindowSummary value = receivableService.summarizeWindow("1", shopId, window[0], window[1]);
            if (value != null) source = value.toMap();
        }
        if (source == null) source = ReceivableWindowSummary.empty().toMap();

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("chargedFen", mapLong(source, "charged_fen"));
        result.put("collectedFen", mapLong(source, "collected_fen"));
        result.put("writeoffFen", mapLong(source, "writeoff_fen"));
        result.put("reversedFen", mapLong(source, "reversed_fen"));
        result.put("outstandingFen", mapLong(source, "outstanding_fen"));
        result.put("cutoffLedgerId", mapLong(source, "cutoff_ledger_id"));
        return result;
    }

    /**
     * 统计指定门店在营业窗口内的新增有效会员数。
     * 多门店隔离防线：
     * 1. 会员必须绑定手机号（phone IS NOT NULL AND TRIM(phone) != ''）；
     * 2. 会员注册时间在营业窗口内（[startTime, endTime)）；
     * 3. 门店上下文过滤：当 shopId != null 时，会员必须在当前门店产生过订单（t_order）、充值（t_member_recharge）或拥有分店钱包（t_shop_member_wallet），彻底杜绝跨店混入；
     * 4. 若 shopId == null（全平台总部聚合），保留全局统计。
     */
    private long countShopNewMembers(Integer shopId, Date startTime, Date endTime) {
        if (userService == null) {
            return 0L;
        }
        try {
            QueryWrapper<User> uq = new QueryWrapper<User>()
                    .isNotNull("phone").ne("TRIM(phone)", "")
                    .ge("time", startTime).lt("time", endTime);
            if (shopId != null) {
                String shopOrderCond = (shopId == 1)
                        ? "(shop_id = 1 OR shop_id IS NULL)"
                        : "shop_id = " + shopId;
                String shopRechargeCond = (shopId == 1)
                        ? "(shop_id = 1 OR shop_id IS NULL)"
                        : "shop_id = " + shopId;
                String shopWalletCond = "shop_id = " + shopId;
                uq.and(w -> w
                        .inSql("openid", "SELECT openid FROM t_order WHERE " + shopOrderCond + " AND openid IS NOT NULL AND TRIM(openid) <> ''")
                        .or().inSql("openid", "SELECT pay_openid FROM t_order WHERE " + shopOrderCond + " AND pay_openid IS NOT NULL AND TRIM(pay_openid) <> ''")
                        .or().inSql("id", "SELECT user_id FROM t_member_recharge WHERE " + shopRechargeCond + " AND user_id IS NOT NULL")
                        .or().inSql("openid", "SELECT openid FROM t_member_recharge WHERE " + shopRechargeCond + " AND openid IS NOT NULL AND TRIM(openid) <> ''")
                        .or().inSql("id", "SELECT user_id FROM t_shop_member_wallet WHERE " + shopWalletCond + " AND user_id IS NOT NULL")
                );
            }
            return userService.count(uq);
        } catch (Exception e) {
            log.warn("统计门店新增会员异常: shopId={} start={} end={}", shopId, startTime, endTime, e);
            return 0L;
        }
    }

    private static Map<String, Object> buildOrderTypeRow(String type, String label, long count, double amount, double totalNet) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("type", type);
        m.put("label", label);
        m.put("orderCount", count);
        m.put("amount", round2Money(amount));
        m.put("percentage", totalNet > 0 ? round2Money((amount / totalNet) * 100.0) : 0d);
        return m;
    }

    private static double mapDouble(Map<String, Object> m, String key) {
        if (m == null || key == null) return 0d;
        Object o = m.get(key);
        if (o instanceof Number) return ((Number) o).doubleValue();
        if (o != null) {
            try { return Double.parseDouble(o.toString()); } catch (Exception ignored) {}
        }
        return 0d;
    }

    @GetMapping("/dishRanking")
    public R dishRanking(@RequestParam(required = false) String startDate,
                        @RequestParam(required = false) String endDate,
                        @RequestParam(required = false) String startTime,
                        @RequestParam(required = false) String endTime,
                        @RequestParam(required = false) String start,
                        @RequestParam(required = false) String end,
                        @RequestParam(required = false) String sort) {
        String startCandidate = firstNonEmpty(startDate, startTime, start);
        String endCandidate = firstNonEmpty(endDate, endTime, end);
        Shop shop = resolveReportShop();
        String[] win = ShopBusinessWindowResolver.resolveReportWindowText(shop, startCandidate, endCandidate);
        return adminOrderController.statisticsDishSales(win[0], win[1], null);
    }

    public R dishRanking(String startDate, String endDate, String sort) {
        return dishRanking(startDate, endDate, null, null, null, null, sort);
    }

    @GetMapping("/cashierPerformance")
    public R cashierPerformance(@RequestParam(required = false) String startDate,
                                @RequestParam(required = false) String endDate,
                                @RequestParam(required = false) String startTime,
                                @RequestParam(required = false) String endTime,
                                @RequestParam(required = false) String start,
                                @RequestParam(required = false) String end) {
        String startCandidate = firstNonEmpty(startDate, startTime, start);
        String endCandidate = firstNonEmpty(endDate, endTime, end);
        Date[] win = businessWindowRange(startCandidate, endCandidate);
        QueryWrapper<Order> cq = new QueryWrapper<Order>().eq("transac_status", "success")
                .eq("merchantId", "1")
                .ge("pay_time", win[0]).lt("pay_time", win[1]);
        applyShopScope(cq);
        List<Order> list = orderService.list(cq);
        double total = list.stream().mapToDouble(OrderNetRevenue::netRevenueYuan).sum();
        double refund = list.stream().mapToDouble(o -> o.getRefund_amount() != null ? o.getRefund_amount() : 0).sum();
        double discount = list.stream().mapToDouble(o -> o.getDiscount_amount() != null ? o.getDiscount_amount() : 0).sum();
        Map<String, Object> item = new HashMap<>();
        item.put("order_count", list.size());
        item.put("total_amount", total);
        item.put("refund_amount", refund);
        item.put("discount_amount", discount);
        List<Map<String, Object>> result = new ArrayList<>();
        result.add(item);
        return R.ok().put("list", result);
    }

    public R cashierPerformance(String startDate, String endDate) {
        return cashierPerformance(startDate, endDate, null, null, null, null);
    }

    @GetMapping("/shopProfit")
    public R shopProfit(@RequestParam(required = false) String startDate,
                        @RequestParam(required = false) String endDate,
                        @RequestParam(required = false) String startTime,
                        @RequestParam(required = false) String endTime,
                        @RequestParam(required = false) String start,
                        @RequestParam(required = false) String end) {
        String startCandidate = firstNonEmpty(startDate, startTime, start);
        String endCandidate = firstNonEmpty(endDate, endTime, end);
        Date[] win = businessWindowRange(startCandidate, endCandidate);
        QueryWrapper<Order> sq = new QueryWrapper<Order>().eq("transac_status", "success")
                .ge("pay_time", win[0]).lt("pay_time", win[1]);
        applyShopScope(sq);
        List<Order> list = orderService.list(sq);
        double total = list.stream().mapToDouble(OrderNetRevenue::netRevenueYuan).sum();
        Map<String, Object> item = new HashMap<>();
        item.put("total_amount", total);
        List<Map<String, Object>> result = new ArrayList<>();
        result.add(item);
        return R.ok().put("list", result);
    }

    public R shopProfit(String startDate, String endDate) {
        return shopProfit(startDate, endDate, null, null, null, null);
    }

    @GetMapping("/compare")
    public R compare(@RequestParam String type,
                    @RequestParam(required = false) String date,
                    @RequestParam(required = false) String startDate,
                    @RequestParam(required = false) String start) {
        double current = 0;
        double previous = 0;
        String dayCandidate = firstNonEmpty(date, startDate, start);
        if (dayCandidate == null || dayCandidate.trim().isEmpty()) {
            return R.error("date 不能为空");
        }
        try {
            LocalDate anchor = ShopBusinessWindowResolver.parseReportDate(dayCandidate);
            String day = anchor.toString();
            if ("yearOnYear".equals(type)) {
                Date[] cw = businessWindowRange(day, day);
                QueryWrapper<Order> q = new QueryWrapper<Order>().eq("transac_status", "success")
                        .ge("pay_time", cw[0]).lt("pay_time", cw[1]);
                applyShopScope(q);
                current = sumCompareDayNet(orderService.list(q));
                String prevDay = anchor.minusYears(1).toString();
                Date[] pw = businessWindowRange(prevDay, prevDay);
                QueryWrapper<Order> pq = new QueryWrapper<Order>().eq("transac_status", "success")
                        .ge("pay_time", pw[0]).lt("pay_time", pw[1]);
                applyShopScope(pq);
                previous = sumCompareDayNet(orderService.list(pq));
            } else if ("monthOnMonth".equals(type)) {
                Date[] cw = businessWindowRange(day, day);
                QueryWrapper<Order> q = new QueryWrapper<Order>().eq("transac_status", "success")
                        .ge("pay_time", cw[0]).lt("pay_time", cw[1]);
                applyShopScope(q);
                current = sumCompareDayNet(orderService.list(q));
                String prevDay = anchor.minusMonths(1).toString();
                Date[] pw = businessWindowRange(prevDay, prevDay);
                QueryWrapper<Order> pq = new QueryWrapper<Order>().eq("transac_status", "success")
                        .ge("pay_time", pw[0]).lt("pay_time", pw[1]);
                applyShopScope(pq);
                previous = sumCompareDayNet(orderService.list(pq));
            } else {
                Date[] cw = businessWindowRange(day, day);
                QueryWrapper<Order> q = new QueryWrapper<Order>().eq("transac_status", "success")
                        .ge("pay_time", cw[0]).lt("pay_time", cw[1]);
                applyShopScope(q);
                current = sumCompareDayNet(orderService.list(q));
            }
        } catch (Exception e) {
            return R.error(400, "date 格式须为 yyyy-MM-dd");
        }
        double rate = previous != 0 ? (current - previous) / previous * 100 : 0;
        return R.ok().put("current", current).put("previous", previous).put("rate", rate);
    }

    public R compare(String type, String date) {
        return compare(type, date, null, null);
    }

    /** 与 /compare 口径一致：sett + service_fee - discount（不含退款等其它项，与改前逻辑相同） */
    private static double sumCompareDayNet(List<Order> list) {
        return list.stream().mapToDouble(o -> (o.getSett_amount() != null ? o.getSett_amount() : 0)
                + (o.getService_fee() != null ? o.getService_fee() : 0)
                - (o.getDiscount_amount() != null ? o.getDiscount_amount() : 0)).sum();
    }

    /**
     * 周复购率：本周购买≥2次的用户 ÷ 本周所有购买用户（均指已支付订单）。
     * 统计窗口由前端传入 startDate/endDate（支持纯日期与自定义时间）。
     */
    @GetMapping("/repurchase/weekly")
    public R weeklyRepurchaseRate(@RequestParam(required = false) String startDate,
                                  @RequestParam(required = false) String endDate,
                                  @RequestParam(required = false) String startTime,
                                  @RequestParam(required = false) String endTime,
                                  @RequestParam(required = false) String start,
                                  @RequestParam(required = false) String end) {
        String startCandidate = firstNonEmpty(startDate, startTime, start);
        String endCandidate = firstNonEmpty(endDate, endTime, end);
        Shop shop = resolveReportShop();
        String[] win = ShopBusinessWindowResolver.resolveReportWindowText(shop, startCandidate, endCandidate);
        QueryWrapper<Order> rq = new QueryWrapper<Order>()
                .eq("transac_status", "success")
                .ge("order_time", win[0])
                .lt("order_time", win[1]);
        applyShopScope(rq);
        List<Order> list = orderService.list(rq);

        Map<String, Integer> cnt = new HashMap<>();
        for (Order o : list) {
            if (o.getOpenid() == null || o.getOpenid().trim().isEmpty()) continue;
            cnt.merge(o.getOpenid().trim(), 1, Integer::sum);
        }
        long buyers = cnt.size();
        long repurchased = cnt.values().stream().filter(n -> n != null && n >= 2).count();
        double rate = buyers == 0 ? 0d : (double) repurchased / (double) buyers;

        Map<String, Object> report = new HashMap<>();
        report.put("startDate", win[0]);
        report.put("endDate", win[1]);
        report.put("buyers", buyers);
        report.put("repurchasedBuyers", repurchased);
        report.put("repurchaseRate", Math.round(rate * 10000) / 10000.0); // 4位小数
        return R.ok().put("report", report);
    }

    /**
     * 月复购率：本月购买≥2次的用户 ÷ 本月所有购买用户（均指已支付订单）。
     * 统计窗口由前端传入 year/month（自然月）。
     */
    @GetMapping("/repurchase/monthly")
    public R monthlyRepurchaseRate(@RequestParam Integer year, @RequestParam Integer month) {
        String start = String.format("%04d-%02d-01", year, month);
        String nextMonth = LocalDate.parse(start).plusMonths(1).toString();
        QueryWrapper<Order> mq = new QueryWrapper<Order>()
                .eq("transac_status", "success")
                .ge("order_time", start + " 00:00:00")
                .lt("order_time", nextMonth + " 00:00:00");
        applyShopScope(mq);
        List<Order> list = orderService.list(mq);

        Map<String, Integer> cnt = new HashMap<>();
        for (Order o : list) {
            if (o.getOpenid() == null || o.getOpenid().trim().isEmpty()) continue;
            cnt.merge(o.getOpenid().trim(), 1, Integer::sum);
        }
        long buyers = cnt.size();
        long repurchased = cnt.values().stream().filter(n -> n != null && n >= 2).count();
        double rate = buyers == 0 ? 0d : (double) repurchased / (double) buyers;

        Map<String, Object> report = new HashMap<>();
        report.put("year", year);
        report.put("month", month);
        report.put("buyers", buyers);
        report.put("repurchasedBuyers", repurchased);
        report.put("repurchaseRate", Math.round(rate * 10000) / 10000.0);
        return R.ok().put("report", report);
    }

    /**
     * 新客复购率：首次购买后，30天内再次购买的用户 ÷ 当期新增用户数。
     *
     * 当期新增用户数：首次购买时间（order_time）落在营业日窗口内的用户数（仅 success）。
     * 分子：上述新增用户中，存在另一笔 success 订单 order_time > 首购时间 且 <= 首购时间+windowDays。
     */
    @GetMapping("/repurchase/newCustomer")
    public R newCustomerRepurchaseRate(@RequestParam(required = false) String startDate,
                                       @RequestParam(required = false) String endDate,
                                       @RequestParam(required = false) String startTime,
                                       @RequestParam(required = false) String endTime,
                                       @RequestParam(required = false) String start,
                                       @RequestParam(required = false) String end,
                                       @RequestParam(required = false, defaultValue = "30") Integer windowDays) {
        int wd = (windowDays == null || windowDays <= 0) ? 30 : windowDays;
        String startCandidate = firstNonEmpty(startDate, startTime, start);
        String endCandidate = firstNonEmpty(endDate, endTime, end);
        Shop shop = resolveReportShop();
        String[] win = ShopBusinessWindowResolver.resolveReportWindowText(shop, startCandidate, endCandidate);
        Date[] winDates = ShopBusinessWindowResolver.resolveReportWindow(shop, startCandidate, endCandidate);
        Date periodStart = winDates[0];
        Date periodEnd = winDates[1];

        // 先取当期内的所有已支付订单，用于筛出“新增用户（首购发生在当期）”
        QueryWrapper<Order> nq = new QueryWrapper<Order>()
                .eq("transac_status", "success")
                .ge("order_time", win[0])
                .lt("order_time", win[1]);
        applyShopScope(nq);
        List<Order> inPeriod = orderService.list(nq);

        // 计算这些用户的首购时间（需与全历史对齐，因此要查“这些用户”的历史最早 order_time）
        Set<String> candidateOpenids = new HashSet<>();
        for (Order o : inPeriod) {
            if (o.getOpenid() != null && !o.getOpenid().trim().isEmpty()) {
                candidateOpenids.add(o.getOpenid().trim());
            }
        }
        if (candidateOpenids.isEmpty()) {
            Map<String, Object> report = new HashMap<>();
            report.put("startDate", win[0]);
            report.put("endDate", win[1]);
            report.put("windowDays", wd);
            report.put("newBuyers", 0);
            report.put("repurchasedNewBuyers", 0);
            report.put("repurchaseRate", 0d);
            return R.ok().put("report", report);
        }

        // 取候选用户的全量已支付订单（仅必要字段），用于算首购与 30 天内复购
        QueryWrapper<Order> aq = new QueryWrapper<Order>()
                .eq("transac_status", "success")
                .in("openid", candidateOpenids)
                .orderByAsc("order_time");
        applyShopScope(aq);
        List<Order> allOfCandidates = orderService.list(aq);

        Map<String, Date> firstOrderTime = new HashMap<>();
        for (Order o : allOfCandidates) {
            String oid = o.getOpenid();
            Date pt = o.getOrder_time();
            if (oid == null || oid.trim().isEmpty() || pt == null) continue;
            String k = oid.trim();
            if (!firstOrderTime.containsKey(k)) {
                firstOrderTime.put(k, pt);
            }
        }

        // 当期新增：首购发生在当期营业日窗口内 [periodStart, periodEnd)
        Set<String> newBuyers = new HashSet<>();
        for (Map.Entry<String, Date> e : firstOrderTime.entrySet()) {
            Date ft = e.getValue();
            if (ft != null && !ft.before(periodStart) && ft.before(periodEnd)) {
                newBuyers.add(e.getKey());
            }
        }

        // 分子：在首购后 windowDays 内再次购买
        long repurchasedNew = 0;
        if (!newBuyers.isEmpty()) {
            Map<String, List<Date>> orderTimes = new HashMap<>();
            for (Order o : allOfCandidates) {
                String oid = o.getOpenid();
                Date pt = o.getOrder_time();
                if (oid == null || oid.trim().isEmpty() || pt == null) continue;
                String k = oid.trim();
                if (!newBuyers.contains(k)) continue;
                orderTimes.computeIfAbsent(k, x -> new ArrayList<>()).add(pt);
            }
            for (String oid : newBuyers) {
                Date ft = firstOrderTime.get(oid);
                if (ft == null) continue;
                Calendar c = Calendar.getInstance();
                c.setTime(ft);
                c.add(Calendar.DAY_OF_MONTH, wd);
                Date deadline = c.getTime();
                List<Date> pts = orderTimes.getOrDefault(oid, Collections.emptyList());
                boolean ok = false;
                for (Date pt : pts) {
                    if (pt == null) continue;
                    if (pt.after(ft) && !pt.after(deadline)) {
                        ok = true;
                        break;
                    }
                }
                if (ok) repurchasedNew++;
            }
        }

        long newBuyerCount = newBuyers.size();
        double rate = newBuyerCount == 0 ? 0d : (double) repurchasedNew / (double) newBuyerCount;
        Map<String, Object> report = new HashMap<>();
        report.put("startDate", win[0]);
        report.put("endDate", win[1]);
        report.put("windowDays", wd);
        report.put("newBuyers", newBuyerCount);
        report.put("repurchasedNewBuyers", repurchasedNew);
        report.put("repurchaseRate", Math.round(rate * 10000) / 10000.0);
        return R.ok().put("report", report);
    }

    public R weeklyRepurchaseRate(String startDate, String endDate) {
        return weeklyRepurchaseRate(startDate, endDate, null, null, null, null);
    }

    public R newCustomerRepurchaseRate(String startDate, String endDate, Integer windowDays) {
        return newCustomerRepurchaseRate(startDate, endDate, null, null, null, null, windowDays);
    }

    /**
     * 运营看板汇总接口（不替换原接口，仅新增聚合返回）。
     * 汇总：复购率、注册人数、当天营业收入（实付净额）、渠道实收（pay_amount_*）、退款与优惠合计、未支付金额、订单数。
     */
    @GetMapping("/dashboard")
    public R dashboard(@RequestParam(required = false) Integer shopId,
                       @RequestParam(required = false, name = "shop_id") Integer shopIdUnderline,
                       @RequestParam(required = false) String weekStartDate,
                       @RequestParam(required = false) String weekEndDate,
                       @RequestParam(required = false) Integer year,
                       @RequestParam(required = false) Integer month,
                       @RequestParam(required = false) String newCustomerStartDate,
                       @RequestParam(required = false) String newCustomerEndDate,
                       @RequestParam(required = false, defaultValue = "30") Integer windowDays,
                       @RequestParam(required = false) String registerStartDate,
                       @RequestParam(required = false) String registerEndDate) {

        // 1) 周复购率默认窗口：本周（周一～周日）
        Map<String, Object> weekly = Collections.emptyMap();
        try {
            String[] weekRange = defaultWeekRange();
            String wStart = (weekStartDate != null && !weekStartDate.trim().isEmpty()) ? weekStartDate.trim() : weekRange[0];
            String wEnd = (weekEndDate != null && !weekEndDate.trim().isEmpty()) ? weekEndDate.trim() : weekRange[1];
            weekly = extractReport(weeklyRepurchaseRate(wStart, wEnd));
        } catch (Exception ignored) {
        }

        // 2) 月复购率默认窗口：本月
        Map<String, Object> monthly = Collections.emptyMap();
        try {
            Calendar now = Calendar.getInstance();
            int y = (year != null && year > 0) ? year : now.get(Calendar.YEAR);
            int m = (month != null && month >= 1 && month <= 12) ? month : (now.get(Calendar.MONTH) + 1);
            monthly = extractReport(monthlyRepurchaseRate(y, m));
        } catch (Exception ignored) {
        }

        // 3) 新客复购率默认窗口：本月 1 日～今日
        Map<String, Object> newCustomer = Collections.emptyMap();
        try {
            Calendar now = Calendar.getInstance();
            String defNewStart = String.format("%04d-%02d-01", now.get(Calendar.YEAR), now.get(Calendar.MONTH) + 1);
            String defNewEnd = String.format("%04d-%02d-%02d", now.get(Calendar.YEAR), now.get(Calendar.MONTH) + 1, now.get(Calendar.DAY_OF_MONTH));
            String ncStart = (newCustomerStartDate != null && !newCustomerStartDate.trim().isEmpty()) ? newCustomerStartDate.trim() : defNewStart;
            String ncEnd = (newCustomerEndDate != null && !newCustomerEndDate.trim().isEmpty()) ? newCustomerEndDate.trim() : defNewEnd;
            newCustomer = extractReport(newCustomerRepurchaseRate(ncStart, ncEnd, windowDays));
        } catch (Exception ignored) {
        }

        // 4) 注册人数：统一复用 UserMapper 统计口径（近7天 / 本月 / 上月）
        int sevenDaysRegisterCount = 0;
        int thisMonthRegisterCount = 0;
        int lastMonthRegisterCount = 0;
        try {
            List<User> sevenDaysUsers = userService.getSevenDaysUser();
            if (sevenDaysUsers != null) {
                sevenDaysRegisterCount = sevenDaysUsers.size();
            }
            List<User> thisMonthUsers = userService.getThisMonthUser();
            if (thisMonthUsers != null) {
                thisMonthRegisterCount = thisMonthUsers.size();
            }
            List<User> lastMonthUsers = userService.getLastMonthUser();
            if (lastMonthUsers != null) {
                lastMonthRegisterCount = lastMonthUsers.size();
            }
        } catch (Exception ignored) {
        }
        Map<String, Object> register = new HashMap<>();
        register.put("sevenDaysRegisterCount", sevenDaysRegisterCount);
        register.put("thisMonthRegisterCount", thisMonthRegisterCount);
        register.put("lastMonthRegisterCount", lastMonthRegisterCount);

        // 5) 今日简报（实时数据）：使用当前活动营业班次 24 小时实时窗口
        Integer resolvedShopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        Integer dashShopId = resolvedShopId != null ? resolvedShopId : (shopId != null ? shopId : shopIdUnderline);
        Shop dashboardShop = resolveReportShop(dashShopId);
        if (dashboardShop == null) {
            dashboardShop = new Shop();
            dashboardShop.setSettle_time("04:00");
        } else if (dashboardShop.getSettle_time() == null || dashboardShop.getSettle_time().trim().isEmpty()) {
            dashboardShop.setSettle_time("04:00");
        }
        LocalDate dashboardOperationalDay = dashboardSettlementDay(dashboardShop, LocalDateTime.now());
        Date[] biz = ShopBusinessWindowResolver.operationalWindowFor(dashboardShop, dashboardOperationalDay);
        Date bizStart = biz[0];
        Date bizEnd = biz[1];

        // 当天订单数：按下单时间 order_time（与 /admin/order/todayCount 一致）
        String dashboardOperationalDate = dashboardOperationalDay.toString();
        long todayOrderCount = orderService.getTodayOrderCount(dashShopId, dashboardOperationalDate);

        Map<String, Object> dayPaid = orderService.aggregateOperationalDayPaidOrderMetrics(
                dashShopId, dashboardOperationalDate);
        if (dayPaid == null) {
            dayPaid = Collections.emptyMap();
        }
        double todayRevenue = round2Money(mapNumber(dayPaid, "business_revenue_net"));
        double totalRefundAmount = round2Money(mapNumber(dayPaid, "total_refund_amount"));
        double totalDiscountAmount = round2Money(mapNumber(dayPaid, "total_discount_amount"));
        long todayPaidOrderCount = mapLong(dayPaid, "paid_order_count");

        List<Map<String, Object>> revenueByPayChannel = new ArrayList<>();
        revenueByPayChannel.add(channelLine("wechat", "微信支付", mapNumber(dayPaid, "pay_channel_wechat")));
        revenueByPayChannel.add(channelLine("wechat_qr", "微信收款码", mapNumber(dayPaid, "pay_channel_wechat_qr")));
        revenueByPayChannel.add(channelLine("alipay", "支付宝", mapNumber(dayPaid, "pay_channel_alipay")));
        revenueByPayChannel.add(channelLine("alipay_qr", "支付宝收款码", mapNumber(dayPaid, "pay_channel_alipay_qr")));
        revenueByPayChannel.add(channelLine("balance", "余额支付", mapNumber(dayPaid, "pay_channel_balance")));
        revenueByPayChannel.add(channelLine("cash", "现金", mapNumber(dayPaid, "pay_channel_cash")));
        revenueByPayChannel.add(channelLine("gift", "赠送金支付", mapNumber(dayPaid, "pay_channel_gift")));

        // 当天未支付金额：仅 unsettled 且 merchantId="1"，按 order_time 落在营业日窗口内（与 todayUnsettledAmount 一致）
        QueryWrapper<Order> uq = new QueryWrapper<Order>()
                .eq("merchantId", "1")
                .eq("transac_status", "unsettled")
                .ge("order_time", bizStart)
                .lt("order_time", bizEnd);
        if (dashShopId != null) {
            uq.eq("shop_id", dashShopId);
        }
        List<Order> unsettled = orderService.list(uq);
        double todayUnpaidAmount = 0d;
        if (unsettled != null) {
            for (Order o : unsettled) {
                todayUnpaidAmount += OrderNetRevenue.netRevenueYuan(o);
            }
        }
        todayUnpaidAmount = Math.round(todayUnpaidAmount * 100) / 100.0;

        Map<String, Object> bizSummary = new HashMap<>();
        bizSummary.put("startTime", bizStart);
        bizSummary.put("endTime", bizEnd);
        bizSummary.put("businessDayDate", dashboardOperationalDay.toString());
        bizSummary.put("settlementDate", dashboardOperationalDay.toString());
        // 营业收入（实付净额）：sett_amount - discount_amount + service_fee - refund_amount - pay_amount_gift
        bizSummary.put("todayRevenue", todayRevenue);
        bizSummary.put("businessRevenueNet", todayRevenue);
        bizSummary.put("totalRefundAmount", totalRefundAmount);
        bizSummary.put("totalDiscountAmount", totalDiscountAmount);
        bizSummary.put("revenueByPayChannel", revenueByPayChannel);
        bizSummary.put("todayPaidOrderCount", todayPaidOrderCount);
        bizSummary.put("todayUnpaidAmount", todayUnpaidAmount);
        // 待支付订单数：与 todayUnpaidAmount 同一查询口径（unsettled 且 merchantId="1"，营业日窗口内）。
        bizSummary.put("todayUnpaidOrderCount", unsettled != null ? (long) unsettled.size() : 0L);
        bizSummary.put("todayOrderCount", todayOrderCount);

        // 会员充值（成功）：与营业日窗口、门店上下文一致（pay_time 落在 [bizStart,bizEnd]；有门店时仅 shop_id 等于该店，不含 shop_id 为 null 的后台直充）
        QueryWrapper<MemberRecharge> rq = new QueryWrapper<MemberRecharge>()
                .eq("status", "success")
                .ge("pay_time", bizStart)
                .lt("pay_time", bizEnd);
        if (dashShopId != null) {
            rq.eq("shop_id", dashShopId);
        }
        List<MemberRecharge> rechargeRows = memberRechargeService.list(rq);
        BigDecimal rechargeTotalBd = BigDecimal.ZERO;
        BigDecimal rechargePrincipalBd = BigDecimal.ZERO;
        BigDecimal rechargeGiftBd = BigDecimal.ZERO;
        if (rechargeRows != null) {
            for (MemberRecharge mr : rechargeRows) {
                if (mr == null) {
                    continue;
                }
                if (mr.getTotal_amount() != null) {
                    rechargeTotalBd = rechargeTotalBd.add(mr.getTotal_amount());
                }
                if (mr.getRecharge_amount() != null) {
                    rechargePrincipalBd = rechargePrincipalBd.add(mr.getRecharge_amount());
                }
                if (mr.getGift_amount() != null) {
                    rechargeGiftBd = rechargeGiftBd.add(mr.getGift_amount());
                }
            }
        }
        bizSummary.put("todayMemberRechargeAmount", round2Money(rechargePrincipalBd.doubleValue()));
        bizSummary.put("todayMemberRechargeTotal", round2Money(rechargeTotalBd.doubleValue()));
        bizSummary.put("todayMemberRechargePrincipal", round2Money(rechargePrincipalBd.doubleValue()));
        bizSummary.put("todayMemberRechargeGift", round2Money(rechargeGiftBd.doubleValue()));
        bizSummary.put("todayMemberRechargeSuccessCount", rechargeRows != null ? (long) rechargeRows.size() : 0L);

        Map<String, Object> data = new HashMap<>();
        data.put("weeklyRepurchase", weekly);
        data.put("monthlyRepurchase", monthly);
        data.put("newCustomerRepurchase", newCustomer);
        data.put("register", register);
        data.put("businessDay", bizSummary);
        return R.ok().put("data", data);
    }

    /**
     * 运营端充值流水列表：参数与 {@link AdminMemberController#rechargeList} 完全一致；
     * 不按 phone/openid/userId 筛选时即全量（在门店上下文下按 shop_id 过滤，或传 allShops=true 看全连锁）。
     */
    @GetMapping("/recharge/list")
    public R reportRechargeList(
            @RequestParam(required = false) String phone,
            @RequestParam(required = false) String openid,
            @RequestParam(required = false) Integer userId,
            @RequestParam(required = false) String orderNo,
            @RequestParam(required = false) String transactionId,
            @RequestParam(required = false) String channel,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) Integer shopId,
            @RequestParam(required = false) Boolean allShops,
            @RequestParam(required = false) String payTimeStart,
            @RequestParam(required = false) String payTimeEnd,
            @RequestParam(required = false) String createdStart,
            @RequestParam(required = false) String createdEnd,
            @RequestParam(required = false) BigDecimal minRechargeAmount,
            @RequestParam(required = false) BigDecimal maxRechargeAmount,
            @RequestParam(required = false) BigDecimal minTotalAmount,
            @RequestParam(required = false) BigDecimal maxTotalAmount,
            @RequestParam(required = false, defaultValue = "created_at") String sortField,
            @RequestParam(required = false, defaultValue = "desc") String sortOrder,
            @RequestParam(required = false, defaultValue = "1") Integer page,
            @RequestParam(required = false, defaultValue = "20") Integer pageSize) {
        return adminMemberController.rechargeList(phone, openid, userId, orderNo, transactionId, channel, status,
                shopId, allShops, payTimeStart, payTimeEnd, createdStart, createdEnd,
                minRechargeAmount, maxRechargeAmount, minTotalAmount, maxTotalAmount,
                sortField, sortOrder, page, pageSize);
    }

    private static double round2Money(double v) {
        return Math.round(v * 100) / 100.0;
    }

    private static double mapNumber(Map<String, Object> m, String key) {
        if (m == null || key == null) {
            return 0d;
        }
        Object o = m.get(key);
        if (o == null) {
            return 0d;
        }
        if (o instanceof Number) {
            return ((Number) o).doubleValue();
        }
        return 0d;
    }

    private static long mapLong(Map<String, Object> m, String key) {
        if (m == null || key == null) {
            return 0L;
        }
        Object o = m.get(key);
        if (o instanceof Number) {
            return ((Number) o).longValue();
        }
        return 0L;
    }

    private static Map<String, Object> channelLine(String code, String label, double amount) {
        Map<String, Object> line = new LinkedHashMap<>();
        line.put("channelCode", code);
        line.put("channelLabel", label);
        line.put("amount", round2Money(amount));
        return line;
    }

    private static Map<String, Object> extractReport(R r) {
        if (r == null) return new HashMap<>();
        Object report = r.get("report");
        if (report instanceof Map) return (Map<String, Object>) report;
        return new HashMap<>();
    }

    /** 返回 [startDate,endDate]，格式 yyyy-MM-dd，默认本周（周一～周日） */
    private static String[] defaultWeekRange() {
        Calendar cal = Calendar.getInstance();
        cal.setFirstDayOfWeek(Calendar.MONDAY);
        cal.set(Calendar.DAY_OF_WEEK, Calendar.MONDAY);
        String start = String.format("%04d-%02d-%02d", cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH));
        cal.add(Calendar.DAY_OF_MONTH, 6);
        String end = String.format("%04d-%02d-%02d", cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH));
        return new String[]{start, end};
    }

    /** 当前报表作用门店：优先入参 shopId，其次 X-Shop-Id 解析的门店；HQ（无门店）取 id 最小门店；读取失败返回 null（回退默认时段）。 */
    private Shop resolveReportShop() {
        return resolveReportShop(null);
    }

    private Shop resolveReportShop(Integer targetShopId) {
        try {
            Integer shopId = targetShopId != null ? targetShopId : AdminShopRequest.getResolvedShopId(httpServletRequest);
            if (shopId != null) {
                Shop s = shopService.getById(shopId);
                if (s != null) {
                    return s;
                }
            }
            QueryWrapper<Shop> q = new QueryWrapper<Shop>().orderByAsc("id").last("limit 1");
            return shopService.getOne(q, false);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * 报表时间范围 [startDate, endDate]（支持纯日期 yyyy-MM-dd 或带时分秒自定义时间），
     * 纯日期自动按门店 settle_time 补全为 [startDate settle_time, endDate+1 settle_time)；
     * 自定义时间精确保留时分秒。
     */
    private Date[] businessWindowRange(String startDate, String endDate) {
        Shop shop = resolveReportShop();
        return ShopBusinessWindowResolver.resolveReportWindow(shop, startDate, endDate);
    }

    private static String firstNonEmpty(String... values) {
        if (values == null) {
            return null;
        }
        for (String v : values) {
            if (v != null && !v.trim().isEmpty()) {
                return v.trim();
            }
        }
        return null;
    }

    /** 今日简报的营业起始日（实时数据）：当前活动营业班次。 */
    static LocalDate dashboardSettlementDay(Shop shop, LocalDateTime now) {
        return ShopBusinessWindowResolver.operationalBusinessDay(shop, now);
    }

    private static Date parseDateStart(String yyyyMMdd) {
        Calendar cal = Calendar.getInstance();
        String[] parts = yyyyMMdd.split("-");
        cal.set(Integer.parseInt(parts[0]), Integer.parseInt(parts[1]) - 1, Integer.parseInt(parts[2]), 0, 0, 0);
        cal.set(Calendar.MILLISECOND, 0);
        return cal.getTime();
    }

    private static Date parseDateEnd(String yyyyMMdd) {
        Calendar cal = Calendar.getInstance();
        String[] parts = yyyyMMdd.split("-");
        cal.set(Integer.parseInt(parts[0]), Integer.parseInt(parts[1]) - 1, Integer.parseInt(parts[2]), 23, 59, 59);
        cal.set(Calendar.MILLISECOND, 999);
        return cal.getTime();
    }

    @GetMapping("/inventory")
    public R inventory(@RequestParam(required = false) String type, @RequestParam(required = false) String date) {
        List<Material> materials = materialService.list();
        Map<String, Object> summary = new HashMap<>();
        summary.put("materialCount", materials.size());
        return R.ok().put("list", materials).put("summary", summary);
    }

    /** 连锁：订单统计仅看当前请求解析出的门店（X-Shop-Id / X-Shop-Code），忽略 URL 上自行拼接的 shop_id，防串店。 */
    private void applyShopScope(QueryWrapper<Order> q) {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (sid != null) {
            q.eq("shop_id", sid);
        }
    }

    /**
     * 跨店会员储值消费清算报表：
     * 汇总各门店之间的储值互通流入（应收）与流出（应付），并计算净额。
     * shopId 可选，为空时若处于门店上下文则默认当前门店，总部视角可查看全店或指定店。
     */
    @GetMapping("/member/cross-shop-clearing")
    public R getCrossShopClearingReport(
            @RequestParam(required = false) Integer shopId,
            @RequestParam(required = false) String startDate,
            @RequestParam(required = false) String endDate) {
        int[] target = new int[1];
        if (adminShopScopeGuard != null) {
            R scopeError = adminShopScopeGuard.resolveTargetShopId(shopId, target);
            if (scopeError != null) return scopeError;
        } else {
            Integer ctx = AdminShopRequest.getResolvedShopId(httpServletRequest);
            target[0] = shopId != null ? shopId : (ctx != null ? ctx : 0);
        }
        int targetShopId = target[0];
        if (shopMemberWalletService == null) {
            return R.ok().put("data", Collections.emptyMap());
        }
        Map<String, Object> report = shopMemberWalletService.getCrossShopClearingReport(
                targetShopId > 0 ? targetShopId : null, startDate, endDate);
        return R.ok().put("data", report);
    }
}

package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.entity.*;
import com.lanf.mapper.*;
import com.lanf.payment.support.PaymentChannelCatalog;
import com.lanf.security.JwtTokenService;
import com.lanf.service.*;
import com.lanf.util.AdminNameResolver;
import com.lanf.util.AdminPasswordUtil;
import com.lanf.util.OrderNetRevenue;
import com.lanf.util.ShopBusinessWindowResolver;
import com.lanf.receivable.model.ReceivableWindowSummary;
import com.lanf.receivable.service.ReceivableService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.annotation.Isolation;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.ExpiredJwtException;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;

/**
 * 营业日关账与商业 Z 报表核心服务实现 (POS-SDC-301 ~ POS-SDC-304)
 */
@Service
public class DailyCloseServiceImpl extends ServiceImpl<DailyCloseSnapshotMapper, DailyCloseSnapshot>
        implements IDailyCloseService {

    private static final Logger log = LoggerFactory.getLogger(DailyCloseServiceImpl.class);
    private static final DateTimeFormatter TIME_FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static final String PRECHECK_SUBJECT = "daily-precheck";
    private static final long PRECHECK_TTL_MILLIS = 5 * 60 * 1000L;
    private static final ZoneOffset BUSINESS_OFFSET = ZoneOffset.ofHours(8);

    @Autowired
    private DailyCloseSnapshotMapper snapshotMapper;
    @Autowired
    private DailyAdjustmentMapper adjustmentMapper;
    @Autowired
    private IDailyStatService dailyStatService;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private IPaymentService paymentService;
    @Autowired
    private IShopService shopService;
    @Autowired
    private DrawerSessionMapper drawerSessionMapper;
    @Autowired
    private CashMovementMapper cashMovementMapper;
    @Autowired
    private PaymentLedgerMapper paymentLedgerMapper;
    @Autowired
    private IAdminService adminService;
    @Autowired
    private ObjectMapper objectMapper;
    @Autowired
    private JwtTokenService jwtTokenService;
    @Autowired
    private com.lanf.payment.service.OrderLedgerConsistencyService orderLedgerConsistencyService;
    @Autowired
    private IMemberRechargeService memberRechargeService;
    @Autowired(required = false)
    private ReceivableService receivableService;
    @Autowired(required = false)
    private com.lanf.service.IDishShopStockService dishShopStockService;
    @Autowired(required = false)
    private com.lanf.service.IOrderDetailService orderDetailService;
    @Autowired(required = false)
    private com.lanf.kds.service.KdsOrderHook kdsOrderHook;
    @Autowired(required = false)
    private com.lanf.service.ITakeoutDeliveryService takeoutDeliveryService;
    @Autowired(required = false)
    private com.lanf.payment.service.CashierCollectionIntentService collectionIntentService;
    @Autowired(required = false)
    private com.lanf.security.SecurityAuditService securityAuditService;
    @Autowired(required = false)
    private javax.servlet.http.HttpServletRequest httpServletRequest;

    private java.time.Clock clock = java.time.Clock.system(java.time.ZoneId.of("Asia/Shanghai"));

    public void setClock(java.time.Clock clock) {
        this.clock = clock;
    }

    private LocalDateTime currentDateTime() {
        return clock != null ? LocalDateTime.now(clock) : LocalDateTime.now(java.time.ZoneId.of("Asia/Shanghai"));
    }

    @Override
    public Map<String, Object> precheck(Integer shopId, Integer adminId, String statDate) {
        return precheck(shopId, adminId, statDate, 30);
    }

    @Override
    public Map<String, Object> precheck(Integer shopId, Integer adminId, String statDate, Integer staleMinutesThreshold) {
        int thresholdMinutes = (staleMinutesThreshold != null && staleMinutesThreshold > 0) ? staleMinutesThreshold : 30;
        Shop shop = resolveShop(shopId);
        CloseSequenceContext sequence = resolveCloseSequence(shop);
        LocalDate settlementDay = resolveCloseSettlementDay(shop, statDate, sequence);
        String businessDay = settlementDay.toString();
        Date[] win = settlementWindow(shop, businessDay, settlementDay);

        List<Map<String, Object>> blockers = new ArrayList<>();
        List<Map<String, Object>> warnings = new ArrayList<>();

        // 0. 检查是否处于门店营业时段内，禁止在营业时段进行日结
        LocalDateTime now = currentDateTime();
        if (ShopBusinessWindowResolver.isWithinBusinessHours(shop, now)) {
            Map<String, Object> b = new LinkedHashMap<>();
            b.put("code", "IN_BUSINESS_HOURS");
            String openStr = shop.getOpen_time() != null && !shop.getOpen_time().trim().isEmpty() ? shop.getOpen_time().trim() : "--";
            String closeStr = shop.getClose_time() != null && !shop.getClose_time().trim().isEmpty() ? shop.getClose_time().trim() : "--";
            b.put("message", String.format("当前处于门店营业时段（%s ~ %s），禁止进行日结关账，请在打烊后再执行日结", openStr, closeStr));
            b.put("open_time", openStr);
            b.put("close_time", closeStr);
            b.put("count", 1);
            blockers.add(b);
        }

        // 1. 检查是否存在活动钱箱会话 (OPEN 或 CLOSING)
        QueryWrapper<DrawerSession> openDrawerQ = new QueryWrapper<DrawerSession>()
                .eq("shop_id", shop.getId())
                .eq("business_day", businessDay)
                .in("state", DrawerSession.STATE_OPEN, DrawerSession.STATE_CLOSING);
        List<DrawerSession> openDrawers = drawerSessionMapper.selectList(openDrawerQ);
        if (!openDrawers.isEmpty()) {
            Map<String, Object> b = new LinkedHashMap<>();
            b.put("code", "OPEN_DRAWER_SESSIONS");
            b.put("message", "当前门店仍有 " + openDrawers.size() + " 个钱箱处于开班或交班中状态，必须先完成交班关箱");
            b.put("count", openDrawers.size());
            List<Map<String, Object>> details = new ArrayList<>();
            for (DrawerSession ds : openDrawers) {
                Map<String, Object> d = new LinkedHashMap<>();
                d.put("sessionId", ds.getId());
                d.put("terminalId", ds.getTerminal_id());
                d.put("drawerCode", ds.getDrawer_code());
                d.put("openedBy", ds.getOpened_by());
                d.put("openedAt", ds.getOpened_at());
                details.add(d);
            }
            b.put("details", details);
            blockers.add(b);
        }

        // 2. 检查是否有未完成就餐或未结账订单 (transac_status = 'unsettled')
        QueryWrapper<Order> openOrderQ = new QueryWrapper<Order>()
                .eq("shop_id", shop.getId())
                .eq("merchantId", "1")
                .eq("transac_status", "unsettled")
                .ge("order_time", win[0]).lt("order_time", win[1]);
        int openOrderCount = orderService.count(openOrderQ);
        List<Order> openOrders = openOrderCount > 0 ? orderService.list(openOrderQ) : Collections.emptyList();

        // 识别超过指定分钟数未支付的打包/外卖单
        long nowMillis = System.currentTimeMillis();
        long staleCutoffMillis = nowMillis - (thresholdMinutes * 60 * 1000L);
        List<Map<String, Object>> stalePackTakeoutOrders = new ArrayList<>();
        BigDecimal stalePackTakeoutAmount = BigDecimal.ZERO;

        if (openOrders != null) {
            for (Order o : openOrders) {
                if (com.lanf.payment.support.PaymentDiningTypeUtil.isPackOrDeliveryType(o.getDineInOrTakeOut())) {
                    Date orderTime = o.getOrder_time();
                    if (orderTime != null && orderTime.getTime() <= staleCutoffMillis) {
                        double sett = o.getSett_amount() != null ? o.getSett_amount() : 0.0;
                        double fee = o.getService_fee() != null ? o.getService_fee() : 0.0;
                        double disc = o.getDiscount_amount() != null ? o.getDiscount_amount() : 0.0;
                        double payable = Math.max(0.0, sett + fee - disc);
                        stalePackTakeoutAmount = stalePackTakeoutAmount.add(BigDecimal.valueOf(payable));

                        long ageMinutes = Math.max(0L, (nowMillis - orderTime.getTime()) / (60 * 1000L));
                        Map<String, Object> item = new LinkedHashMap<>();
                        item.put("id", o.getId());
                        item.put("order_no", o.getOrder_no());
                        item.put("order_time", orderTime);
                        item.put("sett_amount", o.getSett_amount());
                        item.put("payable_amount", Math.round(payable * 100.0) / 100.0);
                        item.put("dineInOrTakeOut", o.getDineInOrTakeOut());
                        item.put("age_minutes", ageMinutes);
                        stalePackTakeoutOrders.add(item);
                    }
                }
            }
        }

        Map<String, Object> voidablePackTakeoutSummary = new LinkedHashMap<>();
        voidablePackTakeoutSummary.put("count", stalePackTakeoutOrders.size());
        voidablePackTakeoutSummary.put("amount", stalePackTakeoutAmount.setScale(2, java.math.RoundingMode.HALF_UP).doubleValue());
        voidablePackTakeoutSummary.put("threshold_minutes", thresholdMinutes);
        voidablePackTakeoutSummary.put("can_one_click_void", !stalePackTakeoutOrders.isEmpty());
        voidablePackTakeoutSummary.put("orders", stalePackTakeoutOrders);

        if (openOrderCount > 0) {
            Map<String, Object> b = new LinkedHashMap<>();
            b.put("code", "OPEN_ORDERS");
            StringBuilder msg = new StringBuilder();
            msg.append("当前营业日仍有 ").append(openOrderCount).append(" 笔未完成或未结账订单，请结账或撤单");
            if (!stalePackTakeoutOrders.isEmpty()) {
                msg.append("（其中含 ").append(stalePackTakeoutOrders.size())
                   .append(" 笔超过 ").append(thresholdMinutes).append(" 分钟未支付的打包/外卖单，可一键全部作废）");
            }
            b.put("message", msg.toString());
            b.put("count", openOrderCount);
            b.put("voidable_pack_takeout", voidablePackTakeoutSummary);
            blockers.add(b);
        }

        // 3. 检查是否有 PENDING 状态的待确认支付/退款流水 (t_payment_ledger)
        QueryWrapper<PaymentLedger> pendingLedgerQ = new QueryWrapper<PaymentLedger>()
                .eq("shop_id", shop.getId())
                .eq("status", "PENDING")
                .ge("occurred_at", win[0]).lt("occurred_at", win[1]);
        Integer pendingCount = paymentLedgerMapper.selectCount(pendingLedgerQ);
        if (pendingCount != null && pendingCount > 0) {
            Map<String, Object> b = new LinkedHashMap<>();
            b.put("code", "PENDING_PAYMENTS");
            b.put("message", "当前营业日存在 " + pendingCount + " 笔待确认第三方交易流水，请等待回调或手动核实");
            b.put("count", pendingCount);
            blockers.add(b);
        }

        // 4. 检查是否有长短款超 50 元但未审批的已关闭钱箱
        QueryWrapper<DrawerSession> unapprovedQ = new QueryWrapper<DrawerSession>()
                .eq("shop_id", shop.getId())
                .eq("business_day", businessDay)
                .eq("state", DrawerSession.STATE_CLOSED)
                .isNull("approved_by")
                .and(w -> w.gt("variance_fen", 5000).or().lt("variance_fen", -5000));
        List<DrawerSession> unapprovedSessions = drawerSessionMapper.selectList(unapprovedQ);
        if (!unapprovedSessions.isEmpty()) {
            Map<String, Object> b = new LinkedHashMap<>();
            b.put("code", "UNAPPROVED_CASH_VARIANCES");
            b.put("message", "当前营业日存在 " + unapprovedSessions.size() + " 笔差额超过 50 元的长短款未获店长审批");
            b.put("count", unapprovedSessions.size());
            blockers.add(b);
        }

        // 5. 警告项：微小长短款或零销售
        QueryWrapper<DrawerSession> minorVarQ = new QueryWrapper<DrawerSession>()
                .eq("shop_id", shop.getId())
                .eq("business_day", businessDay)
                .eq("state", DrawerSession.STATE_CLOSED)
                .ne("variance_fen", 0)
                .le("variance_fen", 5000)
                .ge("variance_fen", -5000);
        Integer minorVarCount = drawerSessionMapper.selectCount(minorVarQ);
        if (minorVarCount != null && minorVarCount > 0) {
            Map<String, Object> w = new LinkedHashMap<>();
            w.put("code", "MINOR_CASH_VARIANCE");
            w.put("message", "当前营业日存在 " + minorVarCount + " 笔 50 元以内的长短款微小差异");
            w.put("count", minorVarCount);
            warnings.add(w);
        }

        // 6. 检查是否已结账
        DailyCloseSnapshot existed = snapshotMapper.selectOne(
                new QueryWrapper<DailyCloseSnapshot>()
                        .eq("shop_id", shop.getId())
                        .eq("business_day", businessDay)
                        .eq("state", DailyCloseSnapshot.STATE_CLOSED)
        );
        if (existed != null) {
            Map<String, Object> b = new LinkedHashMap<>();
            b.put("code", "DAILY_ALREADY_SETTLED");
            b.put("message", "当前营业日已完成日结");
            b.put("count", 1);
            blockers.add(b);
        }

        // 7. 权威支付流水与订单渠道投影不一致时禁止日结，避免把差异固化到快照。
        List<Order> settledOrders = successfulOrders(shop.getId(), win);
        List<com.lanf.payment.service.OrderLedgerConsistencyService.Issue> consistencyIssues =
                orderLedgerConsistencyService.audit(settledOrders);
        if (!consistencyIssues.isEmpty()) {
            Map<String, Object> b = new LinkedHashMap<>();
            b.put("code", "ORDER_LEDGER_MISMATCH");
            b.put("message", "当前营业日存在 " + consistencyIssues.size() + " 笔订单与权威资金流水不一致，必须先完成财务核对");
            b.put("count", consistencyIssues.size());
            Map<String, Integer> reasonSummary = new LinkedHashMap<>();
            consistencyIssues.forEach(issue -> issue.getReasonCodes()
                    .forEach(code -> reasonSummary.merge(code, 1, Integer::sum)));
            b.put("reason_summary", reasonSummary);
            b.put("details", consistencyIssues.stream().limit(50)
                    .map(com.lanf.payment.service.OrderLedgerConsistencyService.Issue::toMap)
                    .collect(Collectors.toList()));
            blockers.add(b);
        }

        // 8. 计算预览数据
        Map<String, Object> preview = calculateWindowSummary(shop, win, businessDay);

        Map<String, Long> watermarks = windowWatermarks(shop.getId(), win);
        boolean canSettle = blockers.isEmpty();
        String precheckToken = null;
        String precheckExpiresAt = null;
        if (canSettle) {
            Map<String, Object> claims = new LinkedHashMap<>();
            claims.put("shop_id", shop.getId());
            claims.put("business_day", businessDay);
            claims.put("admin_id", adminId != null ? adminId : 0);
            claims.putAll(watermarks);
            precheckToken = jwtTokenService.createToken(
                    UUID.randomUUID().toString(), PRECHECK_SUBJECT, PRECHECK_TTL_MILLIS, claims);
            precheckExpiresAt = OffsetDateTime.now(BUSINESS_OFFSET)
                    .plusNanos(PRECHECK_TTL_MILLIS * 1_000_000L)
                    .format(DateTimeFormatter.ISO_OFFSET_DATE_TIME);
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("can_settle", canSettle);
        result.put("is_already_settled", existed != null);
        result.put("stat_date", businessDay);
        result.put("current_business_day", sequence.currentBusinessDay.toString());
        result.put("next_close_business_day", sequence.nextCloseBusinessDay.toString());
        result.put("pending_day_count", sequence.pendingDayCount);
        result.put("has_previous_unclosed_day",
                sequence.pendingDayCount > 0 && sequence.nextCloseBusinessDay.isBefore(sequence.currentBusinessDay));
        result.put("window_start", win[0]);
        result.put("window_end", win[1]);
        result.put("blockers", blockers);
        result.put("warnings", warnings);
        result.put("voidable_stale_pack_takeout", voidablePackTakeoutSummary);
        result.put("precheck_token", precheckToken);
        result.put("precheck_expires_at", precheckExpiresAt);
        result.put("watermarks", watermarks);
        result.put("preview", preview);
        if (existed != null) {
            result.put("existing_snapshot_no", existed.getSnapshot_no());
            result.put("closed_at", existed.getClosed_at());
        }
        return result;
    }

    @Override
    public Map<String, Object> getDailyContext(Integer shopId, Integer adminId, String statDate, Integer staleMinutesThreshold) {
        int thresholdMinutes = (staleMinutesThreshold != null && staleMinutesThreshold > 0) ? staleMinutesThreshold : 30;
        Shop shop = resolveShop(shopId);
        CloseSequenceContext sequence = resolveCloseSequence(shop);
        LocalDate settlementDay = resolveCloseSettlementDay(shop, statDate, sequence);
        String businessDay = settlementDay.toString();
        Date[] win = settlementWindow(shop, businessDay, settlementDay);

        DailyCloseSnapshot existed = snapshotMapper.selectOne(
                new QueryWrapper<DailyCloseSnapshot>()
                        .eq("shop_id", shop.getId())
                        .eq("business_day", businessDay)
                        .eq("state", DailyCloseSnapshot.STATE_CLOSED)
        );

        Map<String, Object> precheckData = precheck(shopId, adminId, businessDay, thresholdMinutes);
        Map<String, Object> result = new LinkedHashMap<>(precheckData);

        boolean isClosed = existed != null;
        result.put("stat_date", businessDay);
        result.put("is_already_settled", isClosed);
        result.put("settled", isClosed);

        Map<String, Object> summary = new LinkedHashMap<>();
        Map<String, Double> channelsMap = new LinkedHashMap<>();
        List<Map<String, Object>> channelDetails = new ArrayList<>();

        if (isClosed) {
            // 已日结：以不可变快照为权威，杜绝历史修改导致的数据漂移
            double netSales = existed.getNet_sales_fen() != null ? existed.getNet_sales_fen() / 100.0 : 0.0;
            double grossSales = existed.getTotal_sales_fen() != null ? existed.getTotal_sales_fen() / 100.0 : 0.0;
            double discountAmount = existed.getDiscount_amount_fen() != null ? existed.getDiscount_amount_fen() / 100.0 : 0.0;
            double refundAmount = existed.getRefund_amount_fen() != null ? existed.getRefund_amount_fen() / 100.0 : 0.0;
            double variance = existed.getTotal_cash_variance_fen() != null ? existed.getTotal_cash_variance_fen() / 100.0 : 0.0;

            summary.put("total_amount", netSales);
            summary.put("gross_sales", grossSales);
            summary.put("discount_amount", discountAmount);
            summary.put("refund_amount", refundAmount);
            summary.put("net_sales", netSales);
            summary.put("order_count", existed.getOrder_count() != null ? existed.getOrder_count() : 0);
            summary.put("drawer_session_count", existed.getDrawer_session_count() != null ? existed.getDrawer_session_count() : 0);
            summary.put("total_cash_variance", variance);
            summary.put("total_collections_fen", existed.getTotal_collections_fen() != null ? existed.getTotal_collections_fen() : 0L);
            summary.put("gross_sales_fen", existed.getTotal_sales_fen() != null ? existed.getTotal_sales_fen() : 0L);
            summary.put("discount_amount_fen", existed.getDiscount_amount_fen() != null ? existed.getDiscount_amount_fen() : 0L);
            summary.put("refund_amount_fen", existed.getRefund_amount_fen() != null ? existed.getRefund_amount_fen() : 0L);
            summary.put("net_sales_fen", existed.getNet_sales_fen() != null ? existed.getNet_sales_fen() : 0L);
            summary.put("cash_variance_fen", existed.getTotal_cash_variance_fen() != null ? existed.getTotal_cash_variance_fen() : 0);
            summary.put("settled", true);
            summary.put("settled_at", existed.getClosed_at());

            // 补充原料成本
            DailyStat ds = dailyStatService.getOne(new QueryWrapper<DailyStat>()
                    .eq("stat_date", java.sql.Date.valueOf(settlementDay))
                    .eq("shop_id", shop.getId()));
            if (ds != null && ds.getMaterial_cost() != null) {
                summary.put("material_cost", ds.getMaterial_cost().doubleValue());
            } else {
                summary.put("material_cost", 0.0);
            }

            // 解析不可变渠道快照 JSON
            if (existed.getChannel_breakdown_json() != null && !existed.getChannel_breakdown_json().trim().isEmpty()) {
                try {
                    List<Map<String, Object>> parsed = objectMapper.readValue(
                            existed.getChannel_breakdown_json(),
                            new com.fasterxml.jackson.core.type.TypeReference<List<Map<String, Object>>>() {}
                    );
                    if (parsed != null) {
                        for (Map<String, Object> row : parsed) {
                            String name = resolveChannelDisplayName(row);
                            row.putIfAbsent("name", name);
                            row.putIfAbsent("label", name);
                            if (row.get("channel") == null && row.get("code") != null) {
                                row.put("channel", row.get("code"));
                            }
                            if (row.get("code") == null && row.get("channel") != null) {
                                row.put("code", row.get("channel"));
                            }
                            channelDetails.add(row);
                            Number netFen = (Number) row.get("net_amount_fen");
                            double netYuan = netFen != null ? netFen.doubleValue() / 100.0 : 0.0;
                            if (name != null) {
                                channelsMap.put(name, netYuan);
                            }
                        }
                    }
                } catch (Exception e) {
                    log.warn("解析已结渠道快照 JSON 失败: {}", e.getMessage());
                }
            }

            // 兼容补充：如果快照 JSON 中未包含挂账渠道明细但存在挂账金额，自动补充挂账渠道
            boolean hasReceivableChannel = channelDetails.stream().anyMatch(r ->
                    PaymentChannelCatalog.RECEIVABLE.equals(r.get("code"))
                            || PaymentChannelCatalog.NAME_RECEIVABLE.equals(r.get("name"))
                            || PaymentChannelCatalog.NAME_RECEIVABLE.equals(r.get("label")));
            if (!hasReceivableChannel && existed.getReceivable_charged_fen() != null && existed.getReceivable_charged_fen() > 0) {
                long chargedFen = existed.getReceivable_charged_fen();
                Map<String, Object> creditRow = newChannelRow(PaymentChannelCatalog.RECEIVABLE);
                creditRow.put("net_amount_fen", chargedFen);
                channelDetails.add(creditRow);
                channelsMap.put(PaymentChannelCatalog.NAME_RECEIVABLE, chargedFen / 100.0);
            }

            // 调整记录
            List<DailyAdjustment> adjustments = adjustmentMapper.selectList(
                    new QueryWrapper<DailyAdjustment>()
                            .eq("snapshot_id", existed.getId())
                            .orderByAsc("id")
            );
            result.put("adjustments", adjustments);
            result.put("settled_at", existed.getClosed_at());
            result.put("closed_at", existed.getClosed_at());
            result.put("existing_snapshot_no", existed.getSnapshot_no());
        } else {
            // 未日结：以 precheck 计算出的同一时间窗口 preview 为准
            Map<String, Object> preview = (Map<String, Object>) precheckData.get("preview");
            if (preview != null) {
                summary.putAll(preview);
                summary.put("settled", false);
                summary.put("settled_at", null);

                Object rawChannels = preview.get("channels");
                if (rawChannels instanceof List) {
                    List<Map<String, Object>> rows = (List<Map<String, Object>>) rawChannels;
                    for (Map<String, Object> row : rows) {
                        String name = resolveChannelDisplayName(row);
                        row.putIfAbsent("name", name);
                        row.putIfAbsent("label", name);
                        if (row.get("channel") == null && row.get("code") != null) {
                            row.put("channel", row.get("code"));
                        }
                        if (row.get("code") == null && row.get("channel") != null) {
                            row.put("code", row.get("channel"));
                        }
                        channelDetails.add(row);
                        Number netFen = (Number) row.get("net_amount_fen");
                        double netYuan = netFen != null ? netFen.doubleValue() / 100.0 : 0.0;
                        if (name != null) {
                            channelsMap.put(name, netYuan);
                        }
                    }
                }
            }
            result.put("adjustments", Collections.emptyList());
        }

        channelsMap.remove(null);

        // 统一顶层结构，满足前后端所有消费点
        result.put("summary", summary);
        result.put("income", summary.get("total_amount"));
        result.put("deduction", summary.get("discount_amount"));
        result.put("channels", channelsMap);
        result.put("channel_details", channelDetails);

        // 重开判定（仅最新已结营业日可重开）
        boolean canReopen = false;
        if (isClosed) {
            List<DailyCloseSnapshot> snapshots = snapshotMapper.selectList(
                    new QueryWrapper<DailyCloseSnapshot>()
                            .eq("shop_id", shop.getId())
                            .orderByAsc("business_day"));
            LocalDate latestSnapshotDay = latestSnapshotDay(snapshots);
            canReopen = latestSnapshotDay != null && !settlementDay.isBefore(latestSnapshotDay);
        }
        result.put("can_reopen", canReopen);

        return result;
    }

    @Override
    @Transactional(rollbackFor = Exception.class, isolation = Isolation.SERIALIZABLE)
    public Map<String, Object> settle(
            Integer shopId,
            Integer adminId,
            String statDate,
            String precheckToken,
            String password,
            boolean force,
            String idempotencyKey
    ) {
        Shop shop = resolveShop(shopId);
        CloseSequenceContext sequence = resolveCloseSequence(shop);
        LocalDate settlementDay = resolveCloseSettlementDay(shop, statDate, sequence);
        String businessDay = settlementDay.toString();
        Date[] win = settlementWindow(shop, businessDay, settlementDay);
        String normalizedIdempotencyKey = normalizeIdempotencyKey(idempotencyKey);

        // 1. 防重复日结 & 幂等返回：如果当前营业日已存在 CLOSED 快照，直接幂等返回
        DailyCloseSnapshot existed = snapshotMapper.selectOne(
                new QueryWrapper<DailyCloseSnapshot>()
                        .eq("shop_id", shop.getId())
                        .eq("business_day", businessDay)
                        .eq("state", DailyCloseSnapshot.STATE_CLOSED)
        );
        if (existed != null) {
            if (normalizedIdempotencyKey != null
                    && !normalizedIdempotencyKey.equals(existed.getSettle_idempotency_key())) {
                throw new ApiException(409, "DAILY_ALREADY_SETTLED", "该营业日已完成日结", existed.getSnapshot_no());
            }
            DailyStat ds = dailyStatService.getOne(
                    new QueryWrapper<DailyStat>()
                            .eq("stat_date", java.sql.Date.valueOf(settlementDay))
                            .eq("shop_id", shop.getId())
            );
            existed.setOperator_name(AdminNameResolver.resolveDisplayName(existed.getOperator_id(), adminService));
            existed.setReviewer_name(AdminNameResolver.resolveDisplayName(existed.getReviewer_id(), adminService));
            existed.setReopened_by_name(AdminNameResolver.resolveDisplayName(existed.getReopened_by(), adminService));
            if (ds != null) {
                ds.setOperator_name(AdminNameResolver.resolveDisplayName(ds.getOperator_id(), adminService));
            }
            Map<String, Object> resp = new LinkedHashMap<>();
            log.info("daily close idempotency hit shop={} businessDay={} idempotencyKey={} snapshot={}",
                    shop.getId(), businessDay, normalizedIdempotencyKey, existed.getSnapshot_no());
            resp.put("snapshot", existed);
            resp.put("dailyStat", ds);
            resp.put("idempotent", true);
            resp.put("message", "该营业日已完成日结关账，已幂等返回既有快照");
            return resp;
        }

        // 营业时段硬性阻断：禁止在营业时段进行日结
        LocalDateTime now = currentDateTime();
        if (ShopBusinessWindowResolver.isWithinBusinessHours(shop, now)) {
            String openStr = shop.getOpen_time() != null && !shop.getOpen_time().trim().isEmpty() ? shop.getOpen_time().trim() : "--";
            String closeStr = shop.getClose_time() != null && !shop.getClose_time().trim().isEmpty() ? shop.getClose_time().trim() : "--";
            throw new ApiException(400, "DAILY_CLOSE_BLOCKED",
                    String.format("当前处于门店营业时段（%s ~ %s），禁止进行日结关账，请在打烊后再执行日结", openStr, closeStr));
        }

        validatePrecheckToken(precheckToken, shop.getId(), adminId, businessDay, win);

        // 2. 二次身份验证（若传入了密码则必须校验）
        if (password != null && !password.trim().isEmpty() && adminId != null) {
            Admin admin = adminService.getById(adminId);
            if (admin != null && !AdminPasswordUtil.matches(password, admin.getPassword())) {
                throw new ApiException(400, "AUTH_FAILED", "管理员二次密码验证失败，禁止关账");
            }
        }

        // 3. 执行日结预检，阻断项存在时严格拒绝
        Map<String, Object> precheckRes = precheck(shop.getId(), adminId, businessDay);
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> blockers = (List<Map<String, Object>>) precheckRes.get("blockers");
        if (blockers != null && !blockers.isEmpty()) {
            String firstMsg = String.valueOf(blockers.get(0).get("message"));
            throw new ApiException(400, "DAILY_CLOSE_BLOCKED", "日结预检未通过：" + firstMsg);
        }

        // 4. 获取当前窗口内所有已结订单与销售合计
        QueryWrapper<Order> orderQ = new QueryWrapper<Order>()
                .eq("shop_id", shop.getId())
                .eq("transac_status", "success")
                .eq("merchantId", "1")
                .and(w -> w.ge("pay_time", win[0]).lt("pay_time", win[1])
                        .or(ow -> ow.isNull("pay_time").ge("order_time", win[0]).lt("order_time", win[1])))
                .and(qw -> qw.in("order_receiving", "rec_order", "off_order").or().isNull("order_receiving"));
        List<Order> orders = orderService.list(orderQ);

        double totalAmountYuan = orders.stream().mapToDouble(OrderNetRevenue::netRevenueYuan).sum();
        double discountAmountYuan = orders.stream().mapToDouble(o ->
                o.getDiscount_amount() != null ? o.getDiscount_amount() : 0).sum();
        double refundAmountYuan = orders.stream().mapToDouble(o ->
                o.getRefund_amount() != null ? o.getRefund_amount() : 0).sum();

        long totalSalesFen = Math.round((totalAmountYuan + discountAmountYuan) * 100);
        long discountAmountFen = Math.round(discountAmountYuan * 100);
        long refundAmountFen = Math.round(refundAmountYuan * 100);
        long netSalesFen = Math.round(totalAmountYuan * 100);
        MemberRechargeSummary rechargeSummary = rechargeSummary(shop.getId(), win);
        ReceivableWindowSummary receivableSummary = receivableSummary(shop.getId(), win);

        // 5. 渠道实收明细
        QueryWrapper<Payment> paymentQ = new QueryWrapper<Payment>()
                .eq("shop_id", shop.getId())
                .ge("pay_time", win[0]).lt("pay_time", win[1]);
        List<Payment> payments = paymentService.list(paymentQ);
        Map<String, BigDecimal> channelSums = payments.stream().collect(
                Collectors.groupingBy(Payment::getPayment_method,
                        Collectors.reducing(BigDecimal.ZERO, Payment::getAmount, BigDecimal::add))
        );
        Map<String, Object> channelBreakdown = new LinkedHashMap<>();
        channelSums.forEach((k, v) -> channelBreakdown.put(k, v.doubleValue()));
        List<PaymentLedger> settledLedgers = paymentLedgerMapper.selectList(new QueryWrapper<PaymentLedger>()
                .eq("shop_id", shop.getId())
                .eq("status", PaymentLedger.STATUS_SUCCEEDED)
                .ge("occurred_at", win[0]).lt("occurred_at", win[1])
                .orderByAsc("id"));
        long paymentCollectionsFen = settledLedgers.stream()
                .map(PaymentLedger::getAmount_fen).filter(Objects::nonNull)
                .mapToLong(Integer::longValue).sum();
        Map<String, String> paymentMethodByOrderNo = paymentMethodByOrderNo(orders);
        Map<String, Map<String, Object>> structuredChannels = new LinkedHashMap<>();
        for (PaymentLedger ledger : settledLedgers) {
            String code = PaymentChannelCatalog.reportingCode(
                    ledger.getChannel(), paymentMethodByOrderNo.get(ledger.getOrder_no()));
            Map<String, Object> row = structuredChannels.computeIfAbsent(code, ignored -> newChannelRow(code));
            if (PaymentLedger.ENTRY_TYPE_REFUND.equals(ledger.getEntry_type())
                    || PaymentLedger.ENTRY_TYPE_REVERSAL.equals(ledger.getEntry_type())) {
                row.put("refund_count", ((Integer) row.get("refund_count")) + 1);
            } else {
                row.put("success_count", ((Integer) row.get("success_count")) + 1);
            }
            long amountFen = ledger.getAmount_fen() != null ? ledger.getAmount_fen() : 0L;
            row.put("net_amount_fen", ((Long) row.get("net_amount_fen")) + amountFen);
        }
        // 迁移期兼容：门店尚无不可变账本记录时才回退旧支付表。
        if (structuredChannels.isEmpty()) {
            for (Payment payment : payments) {
                String code = PaymentChannelCatalog.reportingCode(
                        payment.getPayment_method(), payment.getPayment_method());
                Map<String, Object> row = structuredChannels.computeIfAbsent(code, ignored -> newChannelRow(code));
                row.put("success_count", ((Integer) row.get("success_count")) + 1);
                long amountFen = payment.getAmount() != null ? payment.getAmount().movePointRight(2).longValue() : 0L;
                row.put("net_amount_fen", ((Long) row.get("net_amount_fen")) + amountFen);
            }
        }

        long creditOrderCount = orders.stream()
                .filter(DailyCloseServiceImpl::isReceivableOrder)
                .count();
        if (creditOrderCount > 0) {
            long creditNetFen = Math.round(orders.stream()
                    .filter(DailyCloseServiceImpl::isReceivableOrder)
                    .mapToDouble(OrderNetRevenue::netRevenueYuan).sum() * 100);
            String code = PaymentChannelCatalog.RECEIVABLE;
            Map<String, Object> row = structuredChannels.computeIfAbsent(code, ignored -> newChannelRow(code));
            row.put("success_count", ((Integer) row.get("success_count")) + (int) creditOrderCount);
            row.put("net_amount_fen", ((Long) row.get("net_amount_fen")) + creditNetFen);
            channelBreakdown.put(PaymentChannelCatalog.NAME_RECEIVABLE, creditNetFen / 100.0);
        }

        // 6. 钱箱会话与长短款累计
        QueryWrapper<DrawerSession> sessionQ = new QueryWrapper<DrawerSession>()
                .eq("shop_id", shop.getId())
                .eq("business_day", businessDay);
        List<DrawerSession> sessions = drawerSessionMapper.selectList(sessionQ);
        int totalVarianceFen = 0;
        int totalOpeningFloatFen = 0;
        int totalCountedCashFen = 0;
        List<Map<String, Object>> drawerSessions = new ArrayList<>();
        for (DrawerSession s : sessions) {
            if (s.getVariance_fen() != null) totalVarianceFen += s.getVariance_fen();
            if (s.getOpening_float_fen() != null) totalOpeningFloatFen += s.getOpening_float_fen();
            if (s.getCounted_cash_fen() != null) totalCountedCashFen += s.getCounted_cash_fen();
            Map<String, Object> sessionRow = new LinkedHashMap<>();
            sessionRow.put("session_id", s.getId());
            sessionRow.put("terminal_id", s.getTerminal_id());
            sessionRow.put("drawer_code", s.getDrawer_code());
            sessionRow.put("operator_id", s.getOpened_by());
            Admin sessionAdmin = s.getOpened_by() != null ? adminService.getById(s.getOpened_by()) : null;
            sessionRow.put("operator_name", AdminNameResolver.resolveDisplayName(sessionAdmin));
            sessionRow.put("expected_cash_fen", s.getExpected_cash_fen());
            sessionRow.put("counted_cash_fen", s.getCounted_cash_fen());
            sessionRow.put("variance_fen", s.getVariance_fen());
            drawerSessions.add(sessionRow);
        }

        Map<String, Object> drawerSummary = new LinkedHashMap<>();
        drawerSummary.put("sessions_count", sessions.size());
        drawerSummary.put("opening_float_fen", totalOpeningFloatFen);
        drawerSummary.put("counted_cash_fen", totalCountedCashFen);
        drawerSummary.put("total_variance_fen", totalVarianceFen);
        drawerSummary.put("sessions", drawerSessions);

        // 7. 账本截止水位
        QueryWrapper<PaymentLedger> ledgerMaxQ = new QueryWrapper<PaymentLedger>()
                .eq("shop_id", shop.getId())
                .orderByDesc("id").last("limit 1");
        PaymentLedger maxLedger = paymentLedgerMapper.selectOne(ledgerMaxQ);
        Long cutoffLedgerId = maxLedger != null ? maxLedger.getId() : 0L;

        QueryWrapper<CashMovement> moveMaxQ = new QueryWrapper<CashMovement>()
                .eq("shop_id", shop.getId())
                .orderByDesc("id").last("limit 1");
        CashMovement maxMove = cashMovementMapper.selectOne(moveMaxQ);
        Long cutoffMoveId = maxMove != null ? maxMove.getId() : 0L;

        Map<String, Long> closeWatermarks = windowWatermarks(shop.getId(), win);
        Long cutoffOrderId = closeWatermarks.get("order_id");
        Long cutoffRechargeId = closeWatermarks.get("member_recharge_id");
        Long cutoffReceivableLedgerId = closeWatermarks.get("receivable_ledger_id");
        cutoffLedgerId = closeWatermarks.get("payment_ledger_id");
        cutoffMoveId = closeWatermarks.get("cash_event_id");

        // 8. 生成快照编号与 SHA-256 数据防篡改哈希
        DailyCloseSnapshot reopenedSnapshot = sequence.snapshotByDay.get(settlementDay);
        boolean isReclose = reopenedSnapshot != null
                && DailyCloseSnapshot.STATE_REOPENED.equals(reopenedSnapshot.getState());
        String snapshotNo = isReclose && reopenedSnapshot.getSnapshot_no() != null
                ? reopenedSnapshot.getSnapshot_no()
                : "DSN" + businessDay.replace("-", "") + String.format("%04d", shop.getId())
                + (System.currentTimeMillis() % 10000);
        String channelJson = toJson(new ArrayList<>(structuredChannels.values()));
        String drawerJson = toJson(drawerSummary);

        long totalCollectionsFen = paymentCollectionsFen + receivableSummary.getCollectedFen()
                + rechargeSummary.getPrincipalFen();
        String canonicalData = String.format("%s|%d|%s|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d",
                snapshotNo, shop.getId(), businessDay, totalSalesFen, netSalesFen, orders.size(), cutoffLedgerId,
                cutoffRechargeId, rechargeSummary.getPrincipalFen(), rechargeSummary.getGiftFen(),
                rechargeSummary.getSuccessCount(), cutoffReceivableLedgerId, receivableSummary.getChargedFen(),
                receivableSummary.getCollectedFen(), receivableSummary.getReversedFen(), totalCollectionsFen);
        String snapshotHash = sha256Hex(canonicalData);

        DailyCloseSnapshot snapshot = DailyCloseSnapshot.builder()
                .id(isReclose ? reopenedSnapshot.getId() : null)
                .snapshot_no(snapshotNo)
                .shop_id(shop.getId())
                .business_day(businessDay)
                .window_start(win[0])
                .window_end(win[1])
                .state(DailyCloseSnapshot.STATE_CLOSED)
                .cutoff_ledger_id(cutoffLedgerId)
                .cutoff_movement_id(cutoffMoveId)
                .cutoff_order_id(cutoffOrderId)
                .cutoff_recharge_id(cutoffRechargeId)
                .cutoff_receivable_ledger_id(cutoffReceivableLedgerId)
                .total_sales_fen(totalSalesFen)
                .discount_amount_fen(discountAmountFen)
                .refund_amount_fen(refundAmountFen)
                .net_sales_fen(netSalesFen)
                .order_count(orders.size())
                .drawer_session_count(sessions.size())
                .total_cash_variance_fen(totalVarianceFen)
                .member_recharge_fen(rechargeSummary.getPrincipalFen())
                .member_recharge_gift_fen(rechargeSummary.getGiftFen())
                .member_recharge_count((int) rechargeSummary.getSuccessCount())
                .receivable_charged_fen(receivableSummary.getChargedFen())
                .receivable_collected_fen(receivableSummary.getCollectedFen())
                .receivable_writeoff_fen(receivableSummary.getWriteoffFen())
                .receivable_reversed_fen(receivableSummary.getReversedFen())
                .receivable_outstanding_fen(receivableSummary.getOutstandingFen())
                .total_collections_fen(totalCollectionsFen)
                .channel_breakdown_json(channelJson)
                .drawer_summary_json(drawerJson)
                .snapshot_hash(snapshotHash)
                .settle_idempotency_key(normalizedIdempotencyKey)
                .operator_id(adminId != null ? adminId : 1)
                .reviewer_id(adminId)
                .reopened_at(isReclose ? reopenedSnapshot.getReopened_at() : null)
                .reopened_by(isReclose ? reopenedSnapshot.getReopened_by() : null)
                .reopen_reason(isReclose ? reopenedSnapshot.getReopen_reason() : null)
                .closed_at(new Date())
                .created_at(isReclose ? reopenedSnapshot.getCreated_at() : null)
                .build();
        if (isReclose) {
            snapshotMapper.updateById(snapshot);
        } else {
            snapshotMapper.insert(snapshot);
        }

        // 9. 原子同步更新或插入 t_daily_stat（保持历史日结接口和仪表盘 100% 兼容）
        Date statDateVal = java.sql.Date.valueOf(settlementDay);
        QueryWrapper<DailyStat> dsq = new QueryWrapper<DailyStat>()
                .eq("stat_date", statDateVal)
                .eq("shop_id", shop.getId());
        DailyStat dailyStat = dailyStatService.getOne(dsq);
        if (dailyStat == null) {
            dailyStat = new DailyStat();
            dailyStat.setStat_date(statDateVal);
            dailyStat.setShop_id(shop.getId());
        }
        dailyStat.setTotal_amount(BigDecimal.valueOf(totalAmountYuan));
        dailyStat.setDiscount_amount(BigDecimal.valueOf(discountAmountYuan));
        dailyStat.setRefund_amount(BigDecimal.valueOf(refundAmountYuan));
        dailyStat.setSettled_at(new Date());
        dailyStat.setOperator_id(adminId);
        dailyStat.setSnapshot_id(snapshot.getId());
        dailyStatService.saveOrUpdate(dailyStat);

        snapshot.setOperator_name(AdminNameResolver.resolveDisplayName(snapshot.getOperator_id(), adminService));
        snapshot.setReviewer_name(AdminNameResolver.resolveDisplayName(snapshot.getReviewer_id(), adminService));
        dailyStat.setOperator_name(AdminNameResolver.resolveDisplayName(dailyStat.getOperator_id(), adminService));

        Map<String, Object> resp = new LinkedHashMap<>();
        resp.put("snapshot", snapshot);
        resp.put("dailyStat", dailyStat);
        resp.put("idempotent", false);
        resp.put("message", "日结关账成功");
        return resp;
    }

    @Override
    public Map<String, Object> generateZReport(Integer shopId, String statDate) {
        Shop shop = resolveShop(shopId);
        LocalDate settlementDay;
        if (statDate == null || statDate.trim().isEmpty()) {
            settlementDay = resolveCloseSequence(shop).nextCloseBusinessDay;
        } else {
            settlementDay = resolveSettlementDay(shop, statDate);
        }
        String businessDay = settlementDay.toString();
        Date[] win = settlementWindow(shop, businessDay, settlementDay);

        DailyCloseSnapshot snapshot = snapshotMapper.selectOne(
                new QueryWrapper<DailyCloseSnapshot>()
                        .eq("shop_id", shop.getId())
                        .eq("business_day", businessDay)
                        .eq("state", DailyCloseSnapshot.STATE_CLOSED)
        );

        List<DailyAdjustment> adjustments = new ArrayList<>();
        if (snapshot != null) {
            adjustments = adjustmentMapper.selectList(
                    new QueryWrapper<DailyAdjustment>()
                            .eq("snapshot_id", snapshot.getId())
                            .orderByAsc("id")
            );
        }

        Map<String, Object> report = new LinkedHashMap<>();
        boolean isClosed = snapshot != null;
        report.put("report_type", isClosed ? "Z_REPORT" : "X_REPORT");
        report.put("is_closed", isClosed);
        report.put("shop_id", shop.getId());
        report.put("shop_name", shop.getName() != null ? shop.getName() : "连锁收银门店");
        report.put("business_day", businessDay);
        report.put("window_start", win[0]);
        report.put("window_end", win[1]);

        if (isClosed) {
            report.put("snapshot_no", snapshot.getSnapshot_no());
            report.put("closed_at", snapshot.getClosed_at());
            report.put("operator_id", snapshot.getOperator_id());
            report.put("operator_name", AdminNameResolver.resolveDisplayName(snapshot.getOperator_id(), adminService));
            report.put("reviewer_id", snapshot.getReviewer_id());
            report.put("reviewer_name", AdminNameResolver.resolveDisplayName(snapshot.getReviewer_id(), adminService));
            report.put("reopened_by", snapshot.getReopened_by());
            report.put("reopened_by_name", AdminNameResolver.resolveDisplayName(snapshot.getReopened_by(), adminService));
            report.put("snapshot_hash", snapshot.getSnapshot_hash());

            double totalSales = snapshot.getTotal_sales_fen() / 100.0;
            double discount = snapshot.getDiscount_amount_fen() / 100.0;
            double refund = snapshot.getRefund_amount_fen() / 100.0;
            double netSales = snapshot.getNet_sales_fen() / 100.0;

            Map<String, Object> sales = new LinkedHashMap<>();
            sales.put("total_sales", totalSales);
            sales.put("discount_amount", discount);
            sales.put("refund_amount", refund);
            sales.put("net_sales", netSales);
            sales.put("order_count", snapshot.getOrder_count());
            sales.put("gross_sales_fen", snapshot.getTotal_sales_fen());
            sales.put("discount_amount_fen", snapshot.getDiscount_amount_fen());
            sales.put("refund_amount_fen", snapshot.getRefund_amount_fen());
            sales.put("net_sales_fen", snapshot.getNet_sales_fen());
            report.put("sales_summary", sales);
            MemberRechargeSummary rechargeSummary = new MemberRechargeSummary(
                    snapshot.getMember_recharge_count() != null ? snapshot.getMember_recharge_count() : 0,
                    valueOrZero(snapshot.getMember_recharge_fen()),
                    valueOrZero(snapshot.getMember_recharge_gift_fen()));
            report.put("member_recharge_summary", rechargeSummary.toMap());
            report.put("receivable_summary", snapshotReceivableSummary(snapshot));
            report.put("total_collections_fen", valueOrZero(snapshot.getTotal_collections_fen()));

            // 渠道明细从快照解析
            report.put("channels", fromJsonValue(snapshot.getChannel_breakdown_json()));
            report.put("drawer_summary", fromJsonMap(snapshot.getDrawer_summary_json()));
            report.put("total_cash_variance", snapshot.getTotal_cash_variance_fen() / 100.0);
            Map<String, Long> watermarks = new LinkedHashMap<>();
            watermarks.put("payment_ledger_id", valueOrZero(snapshot.getCutoff_ledger_id()));
            watermarks.put("cash_event_id", valueOrZero(snapshot.getCutoff_movement_id()));
            watermarks.put("order_id", valueOrZero(snapshot.getCutoff_order_id()));
            watermarks.put("receivable_ledger_id", valueOrZero(snapshot.getCutoff_receivable_ledger_id()));
            report.put("watermarks", watermarks);
        } else {
            // 实时预览 (X 报表)
            Map<String, Object> live = calculateWindowSummary(shop, win, businessDay);
            report.put("snapshot_no", "X-PREVIEW-" + businessDay);
            report.put("closed_at", null);
            report.put("operator_id", null);
            report.put("snapshot_hash", null);
            report.put("sales_summary", live);
            report.put("channels", live.get("channels"));
            report.put("drawer_summary", live.get("drawer_summary"));
            report.put("total_cash_variance", live.get("total_cash_variance"));
            report.put("watermarks", windowWatermarks(shop.getId(), win));
            report.put("member_recharge_summary", live.get("member_recharge_summary"));
            report.put("receivable_summary", live.get("receivable_summary"));
            report.put("total_collections_fen", live.get("total_collections_fen"));
        }

        // 调整项
        List<Map<String, Object>> adjList = new ArrayList<>();
        double totalAdjustment = 0;
        for (DailyAdjustment a : adjustments) {
            Map<String, Object> am = new LinkedHashMap<>();
            am.put("adjustment_no", a.getAdjustment_no());
            am.put("type", a.getAdjustment_type());
            double amt = a.getAmount_fen() / 100.0;
            am.put("amount", amt);
            am.put("reason", a.getReason());
            am.put("operator_id", a.getOperator_id());
            am.put("operator_name", AdminNameResolver.resolveDisplayName(a.getOperator_id(), adminService));
            am.put("created_at", a.getCreated_at());
            adjList.add(am);
            totalAdjustment += amt;
        }
        report.put("adjustments", adjList);
        report.put("total_adjustment", totalAdjustment);
        double originalNet = isClosed ? (snapshot.getNet_sales_fen() / 100.0) : 0;
        report.put("adjusted_net_sales", originalNet + totalAdjustment);

        // 生成热敏小票打印文本格式
        report.put("printable_text", buildPrintableZReportText(report));
        return report;
    }

    @Override
    public Map<String, Object> listZReports(Integer shopId, String dateFrom, String dateTo, Long cursor, Integer limit) {
        Shop shop = resolveShop(shopId);
        int pageSize = limit == null ? 20 : Math.max(1, Math.min(limit, 100));
        CloseSequenceContext sequence = resolveCloseSequence(shop);
        LocalDate sequenceStart = sequence.hasHistory
                ? Collections.min(sequence.snapshotByDay.keySet())
                : sequence.currentBusinessDay;
        LocalDate lowerBound = parseOptionalDate(dateFrom, sequenceStart);
        if (lowerBound.isBefore(sequenceStart)) {
            lowerBound = sequenceStart;
        }
        LocalDate upperBound = parseOptionalDate(dateTo, sequence.currentBusinessDay);
        if (upperBound.isAfter(sequence.currentBusinessDay)) {
            upperBound = sequence.currentBusinessDay;
        }
        LocalDate pageStart = resolveZReportPageStart(shop.getId(), cursor, upperBound, lowerBound);

        List<LocalDate> pageDays = new ArrayList<>();
        LocalDate day = pageStart;
        while (!day.isBefore(lowerBound) && pageDays.size() <= pageSize) {
            pageDays.add(day);
            day = day.minusDays(1);
        }
        boolean hasMore = pageDays.size() > pageSize;
        if (hasMore) {
            pageDays = new ArrayList<>(pageDays.subList(0, pageSize));
        }
        List<Map<String, Object>> items = new ArrayList<>();
        for (LocalDate businessDay : pageDays) {
            DailyCloseSnapshot snapshot = sequence.snapshotByDay.get(businessDay);
            items.add(buildZReportListItem(businessDay, snapshot, sequence));
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("current_business_day", sequence.currentBusinessDay.toString());
        result.put("next_close_business_day", sequence.nextCloseBusinessDay.toString());
        result.put("pending_day_count", sequence.pendingDayCount);
        result.put("items", items);
        result.put("has_more", hasMore);
        result.put("next_cursor", hasMore && !pageDays.isEmpty()
                ? Long.valueOf(pageDays.get(pageDays.size() - 1).format(DateTimeFormatter.BASIC_ISO_DATE))
                : null);
        return result;
    }

    private LocalDate resolveZReportPageStart(
            Integer shopId, Long cursor, LocalDate upperBound, LocalDate lowerBound) {
        if (cursor == null) {
            return upperBound;
        }
        LocalDate cursorDay = parseBusinessDayCursor(cursor);
        if (cursorDay == null) {
            DailyCloseSnapshot legacySnapshot = snapshotMapper.selectById(cursor);
            if (legacySnapshot == null || !Objects.equals(shopId, legacySnapshot.getShop_id())) {
                return lowerBound.minusDays(1);
            }
            cursorDay = snapshotBusinessDay(legacySnapshot);
            if (cursorDay == null) {
                return lowerBound.minusDays(1);
            }
        }
        LocalDate pageStart = cursorDay.minusDays(1);
        return pageStart.isAfter(upperBound) ? upperBound : pageStart;
    }

    private static LocalDate parseBusinessDayCursor(Long cursor) {
        String raw = String.valueOf(cursor);
        if (raw.length() != 8) {
            return null;
        }
        try {
            return LocalDate.parse(raw, DateTimeFormatter.BASIC_ISO_DATE);
        } catch (RuntimeException ignored) {
            return null;
        }
    }

    private static LocalDate parseOptionalDate(String raw, LocalDate fallback) {
        String normalized = normalizeDate(raw);
        return normalized == null || normalized.isEmpty() ? fallback : LocalDate.parse(normalized);
    }

    private Map<String, Object> buildZReportListItem(
            LocalDate businessDay, DailyCloseSnapshot snapshot, CloseSequenceContext sequence) {
        boolean closed = snapshot != null && DailyCloseSnapshot.STATE_CLOSED.equals(snapshot.getState());
        String closeState = closed
                ? DailyCloseSnapshot.STATE_CLOSED
                : snapshot != null && DailyCloseSnapshot.STATE_REOPENED.equals(snapshot.getState())
                ? DailyCloseSnapshot.STATE_REOPENED
                : "PENDING";
        boolean isNext = !closed && businessDay.equals(sequence.nextCloseBusinessDay);

        Map<String, Object> item = new LinkedHashMap<>();
        item.put("id", snapshot != null ? snapshot.getId() : null);
        item.put("snapshot_no", snapshot != null ? snapshot.getSnapshot_no() : null);
        item.put("snapshot_hash", snapshot != null ? snapshot.getSnapshot_hash() : null);
        item.put("business_day", businessDay.toString());
        item.put("close_state", closeState);
        item.put("can_close", isNext);
        item.put("is_next_close_business_day", isNext);
        item.put("closed_at", snapshot != null ? snapshot.getClosed_at() : null);
        item.put("net_sales_fen", snapshot != null ? snapshot.getNet_sales_fen() : null);
        item.put("order_count", snapshot != null ? snapshot.getOrder_count() : null);
        item.put("member_recharge_summary", snapshot != null
                ? new MemberRechargeSummary(
                snapshot.getMember_recharge_count() != null ? snapshot.getMember_recharge_count() : 0,
                valueOrZero(snapshot.getMember_recharge_fen()),
                valueOrZero(snapshot.getMember_recharge_gift_fen())).toMap()
                : MemberRechargeSummary.empty().toMap());
        item.put("receivable_summary", snapshot != null
                ? snapshotReceivableSummary(snapshot)
                : ReceivableWindowSummary.empty().toMap());
        item.put("total_collections_fen", snapshot != null
                ? valueOrZero(snapshot.getTotal_collections_fen()) : null);
        item.put("operator_id", snapshot != null ? snapshot.getOperator_id() : null);
        item.put("operator_name", snapshot != null
                ? AdminNameResolver.resolveDisplayName(snapshot.getOperator_id(), adminService) : null);
        item.put("watermarks", snapshot != null ? snapshotWatermarks(snapshot) : null);
        return item;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public DailyAdjustment recordAdjustment(
            Integer shopId,
            Integer adminId,
            Long snapshotId,
            String adjustmentType,
            int amountFen,
            Long orderId,
            Long paymentLedgerId,
            String reason,
            Integer approvedBy
    ) {
        DailyCloseSnapshot snapshot = snapshotMapper.selectById(snapshotId);
        if (snapshot == null) {
            throw new ApiException(404, "SNAPSHOT_NOT_FOUND", "指定的日结快照不存在");
        }
        if (!Objects.equals(shopId, snapshot.getShop_id())) {
            throw new ApiException(404, "SNAPSHOT_NOT_FOUND", "指定的日结快照不存在");
        }
        if (!DailyCloseSnapshot.STATE_CLOSED.equals(snapshot.getState())) {
            throw new ApiException(400, "INVALID_STATE", "只能对已关账 (CLOSED) 的营业日进行日结后调整");
        }

        String adjNo = "ADJ" + snapshot.getBusiness_day().replace("-", "") + (System.currentTimeMillis() % 100000);
        DailyAdjustment adj = DailyAdjustment.builder()
                .adjustment_no(adjNo)
                .snapshot_id(snapshot.getId())
                .shop_id(snapshot.getShop_id())
                .business_day(snapshot.getBusiness_day())
                .adjustment_type(adjustmentType != null ? adjustmentType : DailyAdjustment.TYPE_POST_CLOSE_REFUND)
                .amount_fen(amountFen)
                .order_id(orderId)
                .payment_ledger_id(paymentLedgerId)
                .reason(reason != null ? reason : "日结后业务补录或跨日退款")
                .operator_id(adminId != null ? adminId : 1)
                .approved_by(approvedBy)
                .created_at(new Date())
                .build();
        adjustmentMapper.insert(adj);
        return adj;
    }

    @Override
    public Map<String, Object> getAdjustments(Integer shopId, String statDate) {
        Shop shop = resolveShop(shopId);
        LocalDate settlementDay = resolveSettlementDay(shop, statDate);
        String businessDay = settlementDay.toString();

        DailyCloseSnapshot snapshot = snapshotMapper.selectOne(
                new QueryWrapper<DailyCloseSnapshot>()
                        .eq("shop_id", shop.getId())
                        .eq("business_day", businessDay)
                        .eq("state", DailyCloseSnapshot.STATE_CLOSED)
        );
        if (snapshot == null) {
            Map<String, Object> empty = new LinkedHashMap<>();
            empty.put("is_closed", false);
            empty.put("business_day", businessDay);
            empty.put("adjustments", Collections.emptyList());
            return empty;
        }

        List<DailyAdjustment> adjustments = adjustmentMapper.selectList(
                new QueryWrapper<DailyAdjustment>()
                        .eq("snapshot_id", snapshot.getId())
                        .orderByAsc("id")
        );
        double originalNet = snapshot.getNet_sales_fen() / 100.0;
        double adjTotal = adjustments.stream().mapToDouble(a -> a.getAmount_fen() / 100.0).sum();

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("is_closed", true);
        res.put("snapshot_no", snapshot.getSnapshot_no());
        res.put("business_day", businessDay);
        res.put("original_net_sales", originalNet);
        res.put("adjustment_total", adjTotal);
        res.put("adjusted_net_sales", originalNet + adjTotal);
        res.put("adjustments", adjustments);
        return res;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> reopen(
            Integer shopId,
            Integer adminId,
            String statDate,
            String password,
            String reason
    ) {
        Shop shop = resolveShop(shopId);
        LocalDate settlementDay = resolveSettlementDay(shop, statDate);
        String businessDay = settlementDay.toString();

        if (password == null || password.trim().isEmpty()) {
            throw new ApiException(400, "PASSWORD_REQUIRED", "重开日结必须提供店长/主管密码进行二次认证");
        }
        if (adminId != null) {
            Admin admin = adminService.getById(adminId);
            if (admin != null && !AdminPasswordUtil.matches(password, admin.getPassword())) {
                throw new ApiException(400, "AUTH_FAILED", "密码验证失败，无权执行日结重开");
            }
        }

        DailyCloseSnapshot snapshot = snapshotMapper.selectOne(
                new QueryWrapper<DailyCloseSnapshot>()
                        .eq("shop_id", shop.getId())
                        .eq("business_day", businessDay)
                        .eq("state", DailyCloseSnapshot.STATE_CLOSED)
        );
        if (snapshot == null) {
            throw new ApiException(404, "SNAPSHOT_NOT_FOUND", "当前营业日未执行过日结关账，无需重开");
        }

        List<DailyCloseSnapshot> snapshots = snapshotMapper.selectList(
                new QueryWrapper<DailyCloseSnapshot>()
                        .eq("shop_id", shop.getId())
                        .orderByAsc("business_day"));
        LocalDate latestSnapshotDay = latestSnapshotDay(snapshots);
        if (latestSnapshotDay != null && settlementDay.isBefore(latestSnapshotDay)) {
            Map<String, Object> details = new LinkedHashMap<>();
            details.put("requested_business_day", businessDay);
            details.put("latest_business_day", latestSnapshotDay.toString());
            throw new ApiException(409, "DAILY_REOPEN_OUT_OF_SEQUENCE",
                    "只能重开最后一个已日结营业日，请先处理后续营业日", details);
        }

        snapshot.setState(DailyCloseSnapshot.STATE_REOPENED);
        snapshot.setReopened_at(new Date());
        snapshot.setReopened_by(adminId);
        snapshot.setReopen_reason(reason != null ? reason : "管理员申请重开日结调整");
        snapshotMapper.updateById(snapshot);

        // 重置 t_daily_stat 状态为未结算
        Date statDateVal = java.sql.Date.valueOf(settlementDay);
        DailyStat ds = dailyStatService.getOne(
                new QueryWrapper<DailyStat>()
                        .eq("stat_date", statDateVal)
                        .eq("shop_id", shop.getId())
        );
        if (ds != null) {
            ds.setSettled_at(null);
            dailyStatService.updateById(ds);
        }

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("reopened", true);
        res.put("business_day", businessDay);
        res.put("snapshot_no", snapshot.getSnapshot_no());
        res.put("reopen_reason", snapshot.getReopen_reason());
        res.put("reopened_by", adminId);
        res.put("reopened_by_name", AdminNameResolver.resolveDisplayName(adminId, adminService));
        return res;
    }

    // ==========================================
    // 内部辅助方法
    // ==========================================

    private Map<String, Object> calculateWindowSummary(Shop shop, Date[] win, String businessDay) {
        QueryWrapper<Order> orderQ = new QueryWrapper<Order>()
                .eq("shop_id", shop.getId())
                .eq("transac_status", "success")
                .eq("merchantId", "1")
                .and(w -> w.ge("pay_time", win[0]).lt("pay_time", win[1])
                        .or(ow -> ow.isNull("pay_time").ge("order_time", win[0]).lt("order_time", win[1])))
                .and(qw -> qw.in("order_receiving", "rec_order", "off_order").or().isNull("order_receiving"));
        List<Order> orders = orderService.list(orderQ);

        double totalAmount = orders.stream().mapToDouble(OrderNetRevenue::netRevenueYuan).sum();
        double discountAmount = orders.stream().mapToDouble(o ->
                o.getDiscount_amount() != null ? o.getDiscount_amount() : 0).sum();
        double refundAmount = orders.stream().mapToDouble(o ->
                o.getRefund_amount() != null ? o.getRefund_amount() : 0).sum();

        // 渠道
        QueryWrapper<Payment> paymentQ = new QueryWrapper<Payment>()
                .eq("shop_id", shop.getId())
                .ge("pay_time", win[0]).lt("pay_time", win[1]);
        List<Payment> payments = paymentService.list(paymentQ);
        Map<String, BigDecimal> channels = payments.stream().collect(
                Collectors.groupingBy(Payment::getPayment_method,
                        Collectors.reducing(BigDecimal.ZERO, Payment::getAmount, BigDecimal::add))
        );

        // 钱箱
        QueryWrapper<DrawerSession> sessionQ = new QueryWrapper<DrawerSession>()
                .eq("shop_id", shop.getId())
                .eq("business_day", businessDay);
        List<DrawerSession> sessions = drawerSessionMapper.selectList(sessionQ);
        int totalVarianceFen = 0;
        for (DrawerSession s : sessions) {
            if (s.getVariance_fen() != null) totalVarianceFen += s.getVariance_fen();
        }

        List<PaymentLedger> ledgers = paymentLedgerMapper.selectList(new QueryWrapper<PaymentLedger>()
                .eq("shop_id", shop.getId())
                .eq("status", PaymentLedger.STATUS_SUCCEEDED)
                .ge("occurred_at", win[0]).lt("occurred_at", win[1])
                .orderByAsc("id"));
        long paymentCollectionsFen = ledgers.stream()
                .map(PaymentLedger::getAmount_fen).filter(Objects::nonNull)
                .mapToLong(Integer::longValue).sum();
        Map<String, String> paymentMethodByOrderNo = paymentMethodByOrderNo(orders);
        Map<String, Map<String, Object>> channelRows = new LinkedHashMap<>();
        for (PaymentLedger ledger : ledgers) {
            String code = PaymentChannelCatalog.reportingCode(
                    ledger.getChannel(), paymentMethodByOrderNo.get(ledger.getOrder_no()));
            Map<String, Object> row = channelRows.computeIfAbsent(code, ignored -> newChannelRow(code));
            int amountFen = ledger.getAmount_fen() != null ? ledger.getAmount_fen() : 0;
            if (PaymentLedger.ENTRY_TYPE_REFUND.equals(ledger.getEntry_type())
                    || PaymentLedger.ENTRY_TYPE_REVERSAL.equals(ledger.getEntry_type())) {
                row.put("refund_count", ((Integer) row.get("refund_count")) + 1);
            } else {
                row.put("success_count", ((Integer) row.get("success_count")) + 1);
            }
            row.put("net_amount_fen", ((Long) row.get("net_amount_fen")) + amountFen);
        }
        if (channelRows.isEmpty()) {
            for (Payment payment : payments) {
                String code = PaymentChannelCatalog.reportingCode(
                        payment.getPayment_method(), payment.getPayment_method());
                Map<String, Object> row = channelRows.computeIfAbsent(code, ignored -> newChannelRow(code));
                row.put("success_count", ((Integer) row.get("success_count")) + 1);
                long amountFen = payment.getAmount() != null ? payment.getAmount().movePointRight(2).longValue() : 0L;
                row.put("net_amount_fen", ((Long) row.get("net_amount_fen")) + amountFen);
            }
        }

        long creditOrderCount = orders.stream()
                .filter(DailyCloseServiceImpl::isReceivableOrder)
                .count();
        if (creditOrderCount > 0) {
            long creditNetFen = Math.round(orders.stream()
                    .filter(DailyCloseServiceImpl::isReceivableOrder)
                    .mapToDouble(OrderNetRevenue::netRevenueYuan).sum() * 100);
            String code = PaymentChannelCatalog.RECEIVABLE;
            Map<String, Object> row = channelRows.computeIfAbsent(code, ignored -> newChannelRow(code));
            row.put("success_count", ((Integer) row.get("success_count")) + (int) creditOrderCount);
            row.put("net_amount_fen", ((Long) row.get("net_amount_fen")) + creditNetFen);
            if (channels != null) {
                channels.put(PaymentChannelCatalog.NAME_RECEIVABLE,
                        BigDecimal.valueOf(creditNetFen).divide(BigDecimal.valueOf(100), 2, java.math.RoundingMode.HALF_UP));
            }
        }

        long netSalesFen = Math.round(totalAmount * 100);
        long discountAmountFen = Math.round(discountAmount * 100);
        long refundAmountFen = Math.round(refundAmount * 100);
        long grossSalesFen = netSalesFen + discountAmountFen + refundAmountFen;
        MemberRechargeSummary rechargeSummary = rechargeSummary(shop.getId(), win);
        ReceivableWindowSummary receivableSummary = receivableSummary(shop.getId(), win);

        Map<String, Object> live = new LinkedHashMap<>();
        live.put("total_amount", totalAmount);
        live.put("discount_amount", discountAmount);
        live.put("refund_amount", refundAmount);
        live.put("net_sales", totalAmount);
        live.put("order_count", orders.size());
        live.put("drawer_session_count", sessions.size());
        live.put("total_cash_variance", totalVarianceFen / 100.0);
        live.put("channels", channels);
        live.put("gross_sales_fen", grossSalesFen);
        live.put("discount_amount_fen", discountAmountFen);
        live.put("refund_amount_fen", refundAmountFen);
        live.put("net_sales_fen", netSalesFen);
        live.put("cash_variance_fen", totalVarianceFen);
        live.put("channels", new ArrayList<>(channelRows.values()));
        live.put("member_recharge_summary", rechargeSummary.toMap());
        live.put("receivable_summary", receivableSummary.toMap());
        live.put("total_collections_fen", paymentCollectionsFen + receivableSummary.getCollectedFen()
                + rechargeSummary.getPrincipalFen());
        return live;
    }

    private List<Order> successfulOrders(Integer shopId, Date[] win) {
        return orderService.list(new QueryWrapper<Order>()
                .eq("shop_id", shopId)
                .eq("transac_status", "success")
                .eq("merchantId", "1")
                .and(w -> w.ge("pay_time", win[0]).lt("pay_time", win[1])
                        .or(ow -> ow.isNull("pay_time").ge("order_time", win[0]).lt("order_time", win[1])))
                .and(qw -> qw.in("order_receiving", "rec_order", "off_order").or().isNull("order_receiving")));
    }

    private static String resolveChannelDisplayName(Map<String, Object> row) {
        if (row == null) {
            return "其他支付";
        }
        Object label = row.get("label");
        if (label != null && !String.valueOf(label).trim().isEmpty()) {
            return String.valueOf(label).trim();
        }
        Object name = row.get("name");
        if (name != null && !String.valueOf(name).trim().isEmpty()) {
            return String.valueOf(name).trim();
        }
        Object code = row.get("code") != null ? row.get("code") : row.get("channel");
        if (code != null && !String.valueOf(code).trim().isEmpty()) {
            String resolved = PaymentChannelCatalog.reportingLabel(String.valueOf(code).trim());
            if (resolved != null && !resolved.trim().isEmpty()) {
                return resolved.trim();
            }
        }
        return "其他支付";
    }

    private static boolean isReceivableOrder(Order o) {
        if (o == null || o.getPayment_method() == null) return false;
        String m = o.getPayment_method().trim();
        return ReceivableService.PAYMENT_METHOD_RECEIVABLE.equals(m)
                || PaymentChannelCatalog.RECEIVABLE.equalsIgnoreCase(m);
    }

    private static Map<String, Object> newChannelRow(String code) {
        Map<String, Object> row = new LinkedHashMap<>();
        String label = PaymentChannelCatalog.reportingLabel(code);
        row.put("code", code);
        row.put("channel", code);
        row.put("name", label);
        row.put("label", label);
        row.put("success_count", 0);
        row.put("refund_count", 0);
        row.put("net_amount_fen", 0L);
        return row;
    }

    private MemberRechargeSummary rechargeSummary(Integer shopId, Date[] win) {
        MemberRechargeSummary summary = memberRechargeService.summarizeSuccessfulByWindow(shopId, win[0], win[1]);
        return summary != null ? summary : MemberRechargeSummary.empty();
    }

    private ReceivableWindowSummary receivableSummary(Integer shopId, Date[] win) {
        return receivableService != null
                ? receivableService.summarizeWindow("1", shopId, win[0], win[1])
                : ReceivableWindowSummary.empty();
    }

    private static String normalizeIdempotencyKey(String value) {
        if (value == null || value.trim().isEmpty()) return null;
        String normalized = value.trim();
        if (normalized.length() > 64) {
            throw new ApiException(400, "INVALID_IDEMPOTENCY_KEY", "idempotency_key 长度不能超过 64 个字符");
        }
        return normalized;
    }

    private static Map<String, String> paymentMethodByOrderNo(List<Order> orders) {
        Map<String, String> methods = new HashMap<>();
        if (orders == null) return methods;
        for (Order order : orders) {
            if (order != null && order.getOrder_no() != null) {
                methods.put(order.getOrder_no(), order.getPayment_method());
            }
        }
        return methods;
    }

    private void validatePrecheckToken(
            String token, Integer shopId, Integer adminId, String businessDay, Date[] win) {
        if (token == null || token.trim().isEmpty()) {
            log.warn("daily precheck rejected reason=missing shop={} businessDay={}", shopId, businessDay);
            throw new ApiException(409, "PRECHECK_EXPIRED", "日结预检凭据缺失，请重新执行预检");
        }
        final Claims claims;
        try {
            claims = jwtTokenService.parseToken(token.trim());
        } catch (ExpiredJwtException ex) {
            log.warn("daily precheck rejected reason=expired shop={} businessDay={}", shopId, businessDay);
            throw new ApiException(409, "PRECHECK_EXPIRED", "日结预检凭据已过期，请重新执行预检");
        } catch (RuntimeException ex) {
            log.warn("daily precheck rejected reason=invalid shop={} businessDay={}", shopId, businessDay);
            throw new ApiException(409, "PRECHECK_EXPIRED", "日结预检凭据无效，请重新执行预检");
        }
        if (!PRECHECK_SUBJECT.equals(claims.getSubject())
                || !Objects.equals(shopId, intClaim(claims, "shop_id"))
                || !Objects.equals(businessDay, claims.get("business_day", String.class))
                || (adminId != null && !Objects.equals(adminId, intClaim(claims, "admin_id")))) {
            throw new ApiException(409, "PRECHECK_EXPIRED", "日结预检凭据与当前操作人、门店或营业日不匹配");
        }
        Map<String, Long> current = windowWatermarks(shopId, win);
        for (String key : Arrays.asList("payment_ledger_id", "cash_event_id", "order_id",
                "member_recharge_id", "member_recharge_success_count", "receivable_ledger_id")) {
            Long claimed = longClaim(claims, key);
            // Rolling deployments may still have an unexpired precheck token issued before the
            // receivable watermark was introduced. It is safe only while no receivable ledger
            // exists; once a receivable event is present, the current non-zero watermark rejects it.
            if ("receivable_ledger_id".equals(key) && claimed == null) {
                claimed = 0L;
            }
            if (!Objects.equals(current.get(key), claimed)) {
                log.warn("daily precheck rejected reason=watermark_changed shop={} businessDay={} key={}",
                        shopId, businessDay, key);
                throw new ApiException(409, "WATERMARK_CHANGED", "预检后财务数据已变化，请重新预检后再日结", current);
            }
        }
    }

    private Map<String, Long> windowWatermarks(Integer shopId, Date[] win) {
        PaymentLedger ledger = paymentLedgerMapper.selectOne(new QueryWrapper<PaymentLedger>()
                .eq("shop_id", shopId)
                .ge("occurred_at", win[0]).lt("occurred_at", win[1])
                .orderByDesc("id").last("LIMIT 1"));
        CashMovement movement = cashMovementMapper.selectOne(new QueryWrapper<CashMovement>()
                .eq("shop_id", shopId)
                .ge("occurred_at", win[0]).lt("occurred_at", win[1])
                .orderByDesc("id").last("LIMIT 1"));
        Order order = orderService.getOne(new QueryWrapper<Order>()
                .eq("shop_id", shopId)
                .and(w -> w.ge("pay_time", win[0]).lt("pay_time", win[1])
                        .or(ow -> ow.isNull("pay_time").ge("order_time", win[0]).lt("order_time", win[1])))
                .orderByDesc("id").last("LIMIT 1"), false);
        MemberRecharge recharge = memberRechargeService.getOne(new QueryWrapper<MemberRecharge>()
                .eq("shop_id", shopId)
                .and(w -> w.ge("pay_time", win[0]).lt("pay_time", win[1])
                        .or(ow -> ow.isNull("pay_time").ge("created_at", win[0]).lt("created_at", win[1])))
                .orderByDesc("id").last("LIMIT 1"), false);
        int successfulRechargeCount = memberRechargeService.count(new QueryWrapper<MemberRecharge>()
                .eq("shop_id", shopId).eq("status", "success")
                .ge("pay_time", win[0]).lt("pay_time", win[1]));
        ReceivableWindowSummary receivable = receivableSummary(shopId, win);
        Map<String, Long> watermarks = new LinkedHashMap<>();
        watermarks.put("payment_ledger_id", ledger != null && ledger.getId() != null ? ledger.getId() : 0L);
        watermarks.put("cash_event_id", movement != null && movement.getId() != null ? movement.getId() : 0L);
        watermarks.put("order_id", order != null && order.getId() != null ? order.getId().longValue() : 0L);
        watermarks.put("member_recharge_id", recharge != null && recharge.getId() != null ? recharge.getId() : 0L);
        watermarks.put("member_recharge_success_count", (long) successfulRechargeCount);
        watermarks.put("receivable_ledger_id", receivable.getCutoffLedgerId());
        return watermarks;
    }

    private static Integer intClaim(Claims claims, String key) {
        Object value = claims.get(key);
        return value instanceof Number ? ((Number) value).intValue() : null;
    }

    private static Long longClaim(Claims claims, String key) {
        Object value = claims.get(key);
        return value instanceof Number ? ((Number) value).longValue() : null;
    }

    private String buildPrintableZReportText(Map<String, Object> report) {
        StringBuilder sb = new StringBuilder();
        String line = "--------------------------------\n";
        String doubleLine = "================================\n";

        sb.append(doubleLine);
        sb.append("         ").append(report.get("report_type")).append(" 营业日结清单\n");
        sb.append(doubleLine);
        sb.append("门店: ").append(report.get("shop_name")).append("\n");
        sb.append("营业日: ").append(report.get("business_day")).append("\n");
        sb.append("快照编号: ").append(report.get("snapshot_no")).append("\n");
        if (report.get("closed_at") != null) {
            sb.append("关账时间: ").append(report.get("closed_at")).append("\n");
        }
        if (report.get("operator_name") != null) {
            sb.append("操作人:   ").append(report.get("operator_name")).append("\n");
        }
        sb.append(line);

        @SuppressWarnings("unchecked")
        Map<String, Object> sales = (Map<String, Object>) report.get("sales_summary");
        if (sales != null) {
            sb.append("【销售概况】\n");
            sb.append(String.format("总营业额:        ¥%.2f\n", toDouble(sales.get("total_amount") != null ? sales.get("total_amount") : sales.get("total_sales"))));
            sb.append(String.format("优惠折扣:        -¥%.2f\n", toDouble(sales.get("discount_amount"))));
            sb.append(String.format("退款总额:        -¥%.2f\n", toDouble(sales.get("refund_amount"))));
            sb.append(String.format("净销售额:        ¥%.2f\n", toDouble(sales.get("net_sales"))));
            sb.append(String.format("实际收款合计:    ¥%.2f\n", toDouble(report.get("total_collections_fen")) / 100.0));
            sb.append(String.format("成交笔数:        %s 笔\n", sales.get("order_count")));
            sb.append(line);
        }

        Object receivableValue = report.get("receivable_summary");
        if (receivableValue instanceof Map) {
            Map<?, ?> receivable = (Map<?, ?>) receivableValue;
            sb.append("【挂账与应收】\n");
            sb.append(String.format("新增挂账:        ¥%.2f\n", toDouble(receivable.get("charged_fen")) / 100.0));
            sb.append(String.format("应收回款:        ¥%.2f\n", toDouble(receivable.get("collected_fen")) / 100.0));
            sb.append(String.format("坏账核销:        ¥%.2f\n", toDouble(receivable.get("writeoff_fen")) / 100.0));
            sb.append(String.format("挂账撤销:        ¥%.2f\n", toDouble(receivable.get("reversed_fen")) / 100.0));
            sb.append(String.format("期末应收余额:    ¥%.2f\n", toDouble(receivable.get("outstanding_fen")) / 100.0));
            sb.append(line);
        }

        Object rechargeValue = report.get("member_recharge_summary");
        if (rechargeValue instanceof Map) {
            Map<?, ?> recharge = (Map<?, ?>) rechargeValue;
            sb.append("【会员充值】\n");
            sb.append(String.format("充值本金实收:    ¥%.2f\n", toDouble(recharge.get("principal_fen")) / 100.0));
            sb.append(String.format("活动赠送:        ¥%.2f\n", toDouble(recharge.get("gift_fen")) / 100.0));
            sb.append(String.format("会员入账合计:    ¥%.2f\n", toDouble(recharge.get("credited_total_fen")) / 100.0));
            sb.append(String.format("充值成功笔数:    %s 笔\n", recharge.get("success_count")));
            sb.append(line);
        }

        Object channels = report.get("channels");
        if (channels instanceof Map && !((Map<?, ?>) channels).isEmpty()) {
            sb.append("【多渠道实收】\n");
            for (Map.Entry<?, ?> entry : ((Map<?, ?>) channels).entrySet()) {
                sb.append(String.format("%-12s ¥%.2f\n", channelName(entry.getKey()), toDouble(entry.getValue())));
            }
            sb.append(line);
        } else if (channels instanceof List && !((List<?>) channels).isEmpty()) {
            sb.append("【多渠道实收】\n");
            for (Object value : (List<?>) channels) {
                if (!(value instanceof Map)) continue;
                Map<?, ?> row = (Map<?, ?>) value;
                sb.append(String.format("%-12s ¥%.2f\n",
                        String.valueOf(row.get("label")), toDouble(row.get("net_amount_fen")) / 100.0));
            }
            sb.append(line);
        }

        sb.append("【现金对账与长短款】\n");
        sb.append(String.format("累计长短款:      %s¥%.2f\n",
                toDouble(report.get("total_cash_variance")) >= 0 ? "+" : "",
                toDouble(report.get("total_cash_variance"))));

        Double adjTotal = toDouble(report.get("total_adjustment"));
        if (adjTotal != null && Math.abs(adjTotal) > 0.001) {
            sb.append(line);
            sb.append("【日后调整】\n");
            sb.append(String.format("后续调整累计:    ¥%.2f\n", adjTotal));
            sb.append(String.format("调整后净销售:    ¥%.2f\n", toDouble(report.get("adjusted_net_sales"))));
        }

        sb.append(doubleLine);
        if (report.get("snapshot_hash") != null) {
            sb.append("防伪哈希: ").append(String.valueOf(report.get("snapshot_hash")).substring(0, 16)).append("...\n");
        }
        sb.append("系统生成 · 财务归档凭据\n");
        sb.append(doubleLine);
        return sb.toString();
    }

    private String channelName(Object codeValue) {
        String code = codeValue != null ? String.valueOf(codeValue) : null;
        if ("wxpay".equalsIgnoreCase(code) || "wechat".equalsIgnoreCase(code)) return "微信支付";
        if ("alipay".equalsIgnoreCase(code)) return "支付宝";
        if ("cash".equalsIgnoreCase(code)) return "现金收银";
        if ("member".equalsIgnoreCase(code) || "balance".equalsIgnoreCase(code)) return "会员余额";
        return code != null ? code : "其他支付";
    }

    private double toDouble(Object obj) {
        if (obj == null) return 0.0;
        if (obj instanceof Number) return ((Number) obj).doubleValue();
        try {
            return Double.parseDouble(String.valueOf(obj));
        } catch (Exception e) {
            return 0.0;
        }
    }

    private Shop resolveShop(Integer shopId) {
        if (shopId == null || shopId <= 0) {
            throw new ApiException(4001, "SHOP_CONTEXT_MISSING", "缺少已授权的门店上下文");
        }
        Shop shop = shopService.getById(shopId);
        if (shop == null) {
            throw new ApiException(404, "SHOP_NOT_FOUND", "门店不存在");
        }
        return shop;
    }

    private LocalDate resolveSettlementDay(Shop shop, String date) {
        if (date == null || date.trim().isEmpty()) {
            return ShopBusinessWindowResolver.operationalBusinessDay(shop, LocalDateTime.now());
        }
        String s = date.trim();
        if (s.length() >= 10 && s.charAt(4) == '-' && s.charAt(7) == '-') {
            s = s.substring(0, 10);
        }
        return LocalDate.parse(s);
    }

    /**
     * 日结序列从门店第一张快照开始建立。上线前没有任何快照的门店允许以首次显式日结日
     * 作为兼容锚点；一旦存在快照，后续只能处理最早缺口或最早 REOPENED 营业日。
     */
    private CloseSequenceContext resolveCloseSequence(Shop shop) {
        LocalDate currentBusinessDay = ShopBusinessWindowResolver.operationalBusinessDay(shop, LocalDateTime.now());
        List<DailyCloseSnapshot> snapshots = snapshotMapper.selectList(
                new QueryWrapper<DailyCloseSnapshot>()
                        .eq("shop_id", shop.getId())
                        .le("business_day", currentBusinessDay.toString())
                        .orderByAsc("business_day"));
        if (snapshots == null || snapshots.isEmpty()) {
            return new CloseSequenceContext(currentBusinessDay, currentBusinessDay, 1,
                    false, Collections.emptyMap());
        }

        NavigableMap<LocalDate, DailyCloseSnapshot> byDay = new TreeMap<>();
        for (DailyCloseSnapshot snapshot : snapshots) {
            LocalDate day = snapshotBusinessDay(snapshot);
            if (day != null && !day.isAfter(currentBusinessDay)) {
                byDay.put(day, snapshot);
            }
        }
        if (byDay.isEmpty()) {
            return new CloseSequenceContext(currentBusinessDay, currentBusinessDay, 1,
                    false, Collections.emptyMap());
        }

        LocalDate cursor = byDay.firstKey();
        int pending = 0;
        LocalDate firstPending = null;
        while (!cursor.isAfter(currentBusinessDay)) {
            DailyCloseSnapshot snapshot = byDay.get(cursor);
            boolean closed = snapshot != null && DailyCloseSnapshot.STATE_CLOSED.equals(snapshot.getState());
            if (!closed) {
                pending++;
                if (firstPending == null) {
                    firstPending = cursor;
                }
            }
            cursor = cursor.plusDays(1);
        }
        LocalDate next = firstPending != null ? firstPending : currentBusinessDay;
        return new CloseSequenceContext(currentBusinessDay, next, pending, true, byDay);
    }

    private LocalDate resolveCloseSettlementDay(
            Shop shop, String requestedDate, CloseSequenceContext sequence) {
        LocalDate requested = requestedDate == null || requestedDate.trim().isEmpty()
                ? (sequence.hasHistory ? sequence.nextCloseBusinessDay : sequence.currentBusinessDay)
                : resolveSettlementDay(shop, requestedDate);
        boolean existingClosed = sequence.snapshotByDay.containsKey(requested)
                && DailyCloseSnapshot.STATE_CLOSED.equals(sequence.snapshotByDay.get(requested).getState());
        if (requested.isAfter(sequence.currentBusinessDay)
                || (sequence.hasHistory && !requested.equals(sequence.nextCloseBusinessDay) && !existingClosed)) {
            Map<String, Object> details = new LinkedHashMap<>();
            details.put("expected_business_day", sequence.nextCloseBusinessDay.toString());
            details.put("requested_business_day", requested.toString());
            details.put("current_business_day", sequence.currentBusinessDay.toString());
            throw new ApiException(409, "DAILY_CLOSE_OUT_OF_SEQUENCE",
                    "必须按营业日顺序日结，请先完成 " + sequence.nextCloseBusinessDay, details);
        }
        return requested;
    }

    private static LocalDate latestSnapshotDay(List<DailyCloseSnapshot> snapshots) {
        LocalDate latest = null;
        if (snapshots != null) {
            for (DailyCloseSnapshot snapshot : snapshots) {
                LocalDate day = snapshotBusinessDay(snapshot);
                if (day != null && (latest == null || day.isAfter(latest))) {
                    latest = day;
                }
            }
        }
        return latest;
    }

    private static LocalDate snapshotBusinessDay(DailyCloseSnapshot snapshot) {
        if (snapshot == null || snapshot.getBusiness_day() == null) {
            return null;
        }
        try {
            return LocalDate.parse(snapshot.getBusiness_day());
        } catch (RuntimeException ignored) {
            return null;
        }
    }

    private static final class CloseSequenceContext {
        private final LocalDate currentBusinessDay;
        private final LocalDate nextCloseBusinessDay;
        private final int pendingDayCount;
        private final boolean hasHistory;
        private final Map<LocalDate, DailyCloseSnapshot> snapshotByDay;

        private CloseSequenceContext(
                LocalDate currentBusinessDay,
                LocalDate nextCloseBusinessDay,
                int pendingDayCount,
                boolean hasHistory,
                Map<LocalDate, DailyCloseSnapshot> snapshotByDay) {
            this.currentBusinessDay = currentBusinessDay;
            this.nextCloseBusinessDay = nextCloseBusinessDay;
            this.pendingDayCount = pendingDayCount;
            this.hasHistory = hasHistory;
            this.snapshotByDay = snapshotByDay;
        }
    }

    private Date[] settlementWindow(Shop shop, String date, LocalDate settlementDay) {
        if (date == null || date.trim().isEmpty()) {
            return ShopBusinessWindowResolver.operationalWindow(shop);
        }
        return ShopBusinessWindowResolver.settlementWindowFor(shop, settlementDay);
    }

    private String toJson(Object obj) {
        try {
            return objectMapper.writeValueAsString(obj);
        } catch (Exception e) {
            return "{}";
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> fromJsonMap(String json) {
        if (json == null || json.trim().isEmpty()) return Collections.emptyMap();
        try {
            return objectMapper.readValue(json, Map.class);
        } catch (Exception e) {
            return Collections.emptyMap();
        }
    }

    private Object fromJsonValue(String json) {
        if (json == null || json.trim().isEmpty()) return Collections.emptyList();
        try {
            return objectMapper.readValue(json, Object.class);
        } catch (Exception e) {
            return Collections.emptyList();
        }
    }

    private static long valueOrZero(Long value) {
        return value != null ? value : 0L;
    }

    private static String normalizeDate(String raw) {
        if (raw == null) {
            return null;
        }
        String value = raw.trim();
        if (value.isEmpty()) {
            return null;
        }
        return value.length() >= 10 ? value.substring(0, 10) : value;
    }

    private static Map<String, Long> snapshotWatermarks(DailyCloseSnapshot snapshot) {
        Map<String, Long> watermarks = new LinkedHashMap<>();
        watermarks.put("payment_ledger_id", valueOrZero(snapshot.getCutoff_ledger_id()));
        watermarks.put("cash_event_id", valueOrZero(snapshot.getCutoff_movement_id()));
        watermarks.put("order_id", valueOrZero(snapshot.getCutoff_order_id()));
        watermarks.put("member_recharge_id", valueOrZero(snapshot.getCutoff_recharge_id()));
        watermarks.put("receivable_ledger_id", valueOrZero(snapshot.getCutoff_receivable_ledger_id()));
        return watermarks;
    }

    private static Map<String, Object> snapshotReceivableSummary(DailyCloseSnapshot snapshot) {
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("charged_fen", valueOrZero(snapshot.getReceivable_charged_fen()));
        summary.put("collected_fen", valueOrZero(snapshot.getReceivable_collected_fen()));
        summary.put("writeoff_fen", valueOrZero(snapshot.getReceivable_writeoff_fen()));
        summary.put("reversed_fen", valueOrZero(snapshot.getReceivable_reversed_fen()));
        summary.put("outstanding_fen", valueOrZero(snapshot.getReceivable_outstanding_fen()));
        summary.put("cutoff_ledger_id", valueOrZero(snapshot.getCutoff_receivable_ledger_id()));
        return summary;
    }

    private static String sha256Hex(String input) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(input.getBytes(StandardCharsets.UTF_8));
            StringBuilder hexString = new StringBuilder();
            for (byte b : hash) {
                String hex = Integer.toHexString(0xff & b);
                if (hex.length() == 1) hexString.append('0');
                hexString.append(hex);
            }
            return hexString.toString();
        } catch (Exception e) {
            return UUID.randomUUID().toString().replace("-", "");
        }
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> voidStalePackTakeoutOrders(Integer shopId, Integer adminId, String statDate, Integer minutesThreshold) {
        int thresholdMinutes = (minutesThreshold != null && minutesThreshold > 0) ? minutesThreshold : 30;
        Shop shop = resolveShop(shopId);
        CloseSequenceContext sequence = resolveCloseSequence(shop);
        LocalDate settlementDay = resolveCloseSettlementDay(shop, statDate, sequence);
        String businessDay = settlementDay.toString();
        Date[] win = settlementWindow(shop, businessDay, settlementDay);

        long nowMillis = System.currentTimeMillis();
        long staleCutoffMillis = nowMillis - (thresholdMinutes * 60 * 1000L);

        // 查询当前营业日内未结账的订单
        QueryWrapper<Order> q = new QueryWrapper<Order>()
                .eq("shop_id", shop.getId())
                .eq("merchantId", "1")
                .eq("transac_status", "unsettled")
                .ge("order_time", win[0]).lt("order_time", win[1]);
        List<Order> openOrders = orderService.list(q);

        List<Order> toVoidOrders = new ArrayList<>();
        if (openOrders != null) {
            for (Order o : openOrders) {
                // 仅筛选打包/外卖，且订单创建时间超过阈值
                if (com.lanf.payment.support.PaymentDiningTypeUtil.isPackOrDeliveryType(o.getDineInOrTakeOut())) {
                    Date orderTime = o.getOrder_time();
                    if (orderTime != null && orderTime.getTime() <= staleCutoffMillis) {
                        toVoidOrders.add(o);
                    }
                }
            }
        }

        List<String> voidedOrderNos = new ArrayList<>();
        BigDecimal voidedAmount = BigDecimal.ZERO;

        for (Order order : toVoidOrders) {
            String orderNo = order.getOrder_no();
            boolean updated = orderService.update(new com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper<Order>()
                    .eq("id", order.getId())
                    .eq("shop_id", shop.getId())
                    .eq("transac_status", "unsettled")
                    .set("transac_status", "cancelled")
                    .set("order_receiving", "cancelled"));

            if (updated) {
                voidedOrderNos.add(orderNo);
                double sett = order.getSett_amount() != null ? order.getSett_amount() : 0.0;
                double fee = order.getService_fee() != null ? order.getService_fee() : 0.0;
                double disc = order.getDiscount_amount() != null ? order.getDiscount_amount() : 0.0;
                double payable = Math.max(0.0, sett + fee - disc);
                voidedAmount = voidedAmount.add(BigDecimal.valueOf(payable));

                // 1. 回退库存
                restoreStockForOrder(order.getId(), shop.getId());

                // 2. 取消配送单
                if (takeoutDeliveryService != null) {
                    try {
                        takeoutDeliveryService.markCancelledIfPresent(orderNo);
                    } catch (Exception ex) {
                        log.warn("作废订单时标记配送取消失败 orderNo={}: {}", orderNo, ex.getMessage());
                    }
                }

                // 3. 通知 KDS 厨显作废工单
                if (kdsOrderHook != null) {
                    try {
                        kdsOrderHook.afterOrderCancelled(order);
                    } catch (Exception ex) {
                        log.warn("作废订单时通知 KDS 异常 orderNo={}: {}", orderNo, ex.getMessage());
                    }
                }

                // 4. 清理收款意向占用
                if (collectionIntentService != null) {
                    try {
                        collectionIntentService.cancelAllForOrder(shop.getId(), orderNo);
                    } catch (Exception ex) {
                        log.warn("作废订单时清理收款意向异常 orderNo={}: {}", orderNo, ex.getMessage());
                    }
                }
            }
        }

        // 5. 记录安全审计日志
        if (securityAuditService != null && !voidedOrderNos.isEmpty()) {
            Map<String, Object> details = new LinkedHashMap<>();
            details.put("voided_count", voidedOrderNos.size());
            details.put("voided_amount", voidedAmount.setScale(2, java.math.RoundingMode.HALF_UP).doubleValue());
            details.put("threshold_minutes", thresholdMinutes);
            details.put("business_day", businessDay);
            details.put("order_nos", voidedOrderNos);
            try {
                securityAuditService.recordPrivilegedAction(
                        httpServletRequest,
                        shop.getId(),
                        "order",
                        "BATCH_VOID_STALE_TAKEOUT",
                        "COUNT:" + voidedOrderNos.size(),
                        adminId,
                        details,
                        "一键作废超过 " + thresholdMinutes + " 分钟未支付打包/外卖单共 " + voidedOrderNos.size() + " 笔"
                );
            } catch (Exception ex) {
                log.warn("记录一键作废打包外卖单审计日志异常: {}", ex.getMessage());
            }
        }

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("voided_count", voidedOrderNos.size());
        res.put("voided_amount", voidedAmount.setScale(2, java.math.RoundingMode.HALF_UP).doubleValue());
        res.put("threshold_minutes", thresholdMinutes);
        res.put("voided_order_nos", voidedOrderNos);
        return res;
    }

    private void restoreStockForOrder(Integer orderId, Integer shopId) {
        if (orderId == null || dishShopStockService == null || orderDetailService == null) {
            return;
        }
        try {
            List<OrderDetail> details = orderDetailService.list(
                    new QueryWrapper<OrderDetail>().eq("mId", orderId));
            if (details != null) {
                for (OrderDetail od : details) {
                    if (com.lanf.order.OrderDetailLineStatus.isRefunded(od.getLine_status())) {
                        continue;
                    }
                    try {
                        dishShopStockService.restoreForDetail(od, shopId);
                    } catch (RuntimeException ex) {
                        log.warn("一键作废订单回退库存跳过，明细 id={} name={}: {}", od.getId(), od.getName(), ex.getMessage());
                    }
                }
            }
        } catch (Exception ex) {
            log.warn("一键作废订单查询明细回退库存异常 orderId={}: {}", orderId, ex.getMessage());
        }
    }
}

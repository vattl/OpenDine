package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.entity.LedgerBackfillLog;
import com.lanf.entity.Order;
import com.lanf.entity.PaymentLedger;
import com.lanf.entity.Shop;
import com.lanf.entity.SystemConfig;
import com.lanf.mapper.LedgerBackfillLogMapper;
import com.lanf.mapper.PaymentLedgerMapper;
import com.lanf.mapper.SystemConfigMapper;
import com.lanf.payment.support.PaymentChannelCatalog;
import com.lanf.service.ILedgerMigrationService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.util.OrderNetRevenue;
import com.lanf.util.ShopBusinessWindowResolver;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;

/**
 * 历史账本回填与双写影子切读服务实现 (POS-SDC-501 & POS-SDC-502)
 */
@Service
public class LedgerMigrationServiceImpl implements ILedgerMigrationService {

    private static final Logger log = LoggerFactory.getLogger(LedgerMigrationServiceImpl.class);
    private static final ZoneId SHANGHAI_ZONE = ZoneId.of("Asia/Shanghai");
    private static final DateTimeFormatter TIME_FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    @Autowired
    private PaymentLedgerMapper paymentLedgerMapper;
    @Autowired
    private LedgerBackfillLogMapper ledgerBackfillLogMapper;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private IShopService shopService;
    @Autowired
    private SystemConfigMapper systemConfigMapper;
    @Autowired
    private ObjectMapper objectMapper;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> executeBackfill(Integer shopId, Integer adminId, String statDate, boolean dryRun) {
        log.info("[LedgerMigration] 开始执行历史账本回填: shopId={}, statDate={}, dryRun={}, adminId={}",
                shopId, statDate, dryRun, adminId);

        Shop shop = shopId != null ? shopService.getById(shopId) : null;
        QueryWrapper<Order> oq = new QueryWrapper<Order>()
                .eq("transac_status", "success");
        if (shopId != null && shopId > 0) {
            oq.eq("shop_id", shopId);
        }

        if (statDate != null && !statDate.trim().isEmpty()) {
            String s = statDate.trim();
            if (s.length() >= 10 && s.charAt(4) == '-' && s.charAt(7) == '-') {
                s = s.substring(0, 10);
            }
            LocalDate day = LocalDate.parse(s);
            if (shop != null) {
                Date[] win = ShopBusinessWindowResolver.operationalWindowFor(shop, day);
                oq.ge("order_time", win[0]).lt("order_time", win[1]);
            } else {
                oq.likeRight("order_time", statDate.trim());
            }
        }

        List<Order> orders = orderService.list(oq);
        int totalOrdersScanned = orders.size();
        int backfilledOrders = 0;
        int skippedOrders = 0;
        int totalRowsInserted = 0;
        long totalAmountFen = 0L;
        int anomaliesCount = 0;

        List<Map<String, Object>> anomalies = new ArrayList<>();
        Map<String, Long> channelTotalsFen = new LinkedHashMap<>();
        channelTotalsFen.put(PaymentLedger.CHANNEL_CASH, 0L);
        channelTotalsFen.put(PaymentLedger.CHANNEL_WECHAT, 0L);
        channelTotalsFen.put(PaymentLedger.CHANNEL_ALIPAY, 0L);
        channelTotalsFen.put(PaymentLedger.CHANNEL_WECHAT_QR, 0L);
        channelTotalsFen.put(PaymentLedger.CHANNEL_ALIPAY_QR, 0L);
        channelTotalsFen.put(PaymentLedger.CHANNEL_BALANCE_PRINCIPAL, 0L);
        channelTotalsFen.put(PaymentLedger.CHANNEL_GIFT, 0L);
        channelTotalsFen.put(PaymentLedger.CHANNEL_OTHER, 0L);

        for (Order order : orders) {
            Integer currentShopId = order.getShop_id() != null ? order.getShop_id() : (shopId != null ? shopId : 0);
            Integer count = paymentLedgerMapper.selectCount(new QueryWrapper<PaymentLedger>()
                    .eq("shop_id", currentShopId)
                    .eq("order_id", order.getId()));
            if (count != null && count > 0) {
                skippedOrders++;
                continue;
            }

            // 解析各渠道实付金额（元转分）
            int cashFen = order.getPay_amount_cash() != null ? (int) Math.round(order.getPay_amount_cash() * 100) : 0;
            int wechatFen = order.getPay_amount_wechat() != null ? (int) Math.round(order.getPay_amount_wechat() * 100) : 0;
            int alipayFen = order.getPay_amount_alipay() != null ? (int) Math.round(order.getPay_amount_alipay() * 100) : 0;
            int balanceFen = order.getPay_amount_balance() != null ? (int) Math.round(order.getPay_amount_balance() * 100) : 0;
            int giftFen = order.getPay_amount_gift() != null ? (int) Math.round(order.getPay_amount_gift() * 100) : 0;
            int expectedNetFen = OrderNetRevenue.netRevenueFen(order);

            Map<String, Integer> channels = new LinkedHashMap<>();
            if (cashFen > 0) channels.put(PaymentLedger.CHANNEL_CASH, cashFen);
            if (wechatFen > 0) channels.put(
                    PaymentChannelCatalog.ledgerChannel(
                            order.getPayment_method(), PaymentLedger.CHANNEL_WECHAT), wechatFen);
            if (alipayFen > 0) channels.put(
                    PaymentChannelCatalog.ledgerChannel(
                            order.getPayment_method(), PaymentLedger.CHANNEL_ALIPAY), alipayFen);
            if (balanceFen > 0) channels.put(PaymentLedger.CHANNEL_BALANCE_PRINCIPAL, balanceFen);
            if (giftFen > 0) channels.put(PaymentLedger.CHANNEL_GIFT, giftFen);

            if (channels.isEmpty() && expectedNetFen > 0) {
                String pm = order.getPayment_method() != null ? order.getPayment_method().toLowerCase() : "";
                String paymentCode = PaymentChannelCatalog.codeFromPaymentMethod(order.getPayment_method());
                if (PaymentChannelCatalog.OFFLINE_WECHAT_QR.equals(paymentCode)) {
                    channels.put(PaymentLedger.CHANNEL_WECHAT_QR, expectedNetFen);
                } else if (PaymentChannelCatalog.OFFLINE_ALIPAY_QR.equals(paymentCode)) {
                    channels.put(PaymentLedger.CHANNEL_ALIPAY_QR, expectedNetFen);
                } else if (pm.contains("微信") || pm.contains("wechat")) {
                    channels.put(PaymentLedger.CHANNEL_WECHAT, expectedNetFen);
                } else if (pm.contains("支付宝") || pm.contains("alipay")) {
                    channels.put(PaymentLedger.CHANNEL_ALIPAY, expectedNetFen);
                } else if (pm.contains("现金") || pm.contains("cash")) {
                    channels.put(PaymentLedger.CHANNEL_CASH, expectedNetFen);
                } else if (pm.contains("余额") || pm.contains("balance")) {
                    channels.put(PaymentLedger.CHANNEL_BALANCE_PRINCIPAL, expectedNetFen);
                } else {
                    channels.put(PaymentLedger.CHANNEL_OTHER, expectedNetFen);
                }
            }

            int sumFen = channels.values().stream().mapToInt(Integer::intValue).sum();
            String trustLevel = PaymentLedger.TRUST_HIGH;
            if (sumFen != expectedNetFen) {
                trustLevel = PaymentLedger.TRUST_SUSPECT;
                Map<String, Object> anom = new HashMap<>();
                anom.put("order_id", order.getId());
                anom.put("order_no", order.getOrder_no());
                anom.put("expected_fen", expectedNetFen);
                anom.put("channel_sum_fen", sumFen);
                anom.put("reason", "CHANNEL_SUM_MISMATCH");
                anomalies.add(anom);
                anomaliesCount++;
            }

            Date orderTime = order.getPay_time() != null ? order.getPay_time() : order.getOrder_time();
            if (orderTime == null) {
                orderTime = new Date();
            }
            LocalDateTime ldt = orderTime.toInstant().atZone(SHANGHAI_ZONE).toLocalDateTime();
            Shop orderShop = (shop != null && shop.getId().equals(currentShopId)) ? shop : shopService.getById(currentShopId);
            String bDay = statDate != null ? statDate : (orderShop != null ? ShopBusinessWindowResolver.operationalBusinessDay(orderShop, ldt).toString() : ldt.toLocalDate().toString());

            for (Map.Entry<String, Integer> entry : channels.entrySet()) {
                String chCode = entry.getKey();
                int amtFen = entry.getValue();

                PaymentLedger ledger = PaymentLedger.builder()
                        .ledger_no("PL-BF-" + order.getId() + "-" + chCode)
                        .request_id("BF-" + order.getId() + "-" + chCode)
                        .shop_id(currentShopId)
                        .order_id(order.getId().longValue())
                        .order_no(order.getOrder_no())
                        .terminal_id("UNKNOWN")
                        .operator_id(null)
                        .entry_type(PaymentLedger.ENTRY_TYPE_PAYMENT)
                        .channel(chCode)
                        .amount_fen(amtFen)
                        .status(PaymentLedger.STATUS_SUCCEEDED)
                        .source(PaymentLedger.SOURCE_BACKFILLED_ORDER)
                        .trust_level(trustLevel)
                        .occurred_at(orderTime)
                        .business_day(bDay)
                        .created_at(new Date())
                        .build();

                if (!dryRun) {
                    paymentLedgerMapper.insert(ledger);
                }
                totalRowsInserted++;
                totalAmountFen += amtFen;
                channelTotalsFen.put(chCode, channelTotalsFen.getOrDefault(chCode, 0L) + amtFen);
            }
            backfilledOrders++;
        }

        // SHA-256 数据防篡改签名
        String rawSignPayload = String.format("%d|%s|%d|%d|%d|%d|%d|%b",
                shopId != null ? shopId : 0, statDate != null ? statDate : "ALL",
                totalOrdersScanned, backfilledOrders, skippedOrders, totalAmountFen, anomaliesCount, dryRun);
        String integrityHash = sha256Hex(rawSignPayload);

        String anomaliesJson = null;
        try {
            anomaliesJson = objectMapper.writeValueAsString(anomalies);
        } catch (Exception e) {
            log.warn("序列化回填异常单失败", e);
        }

        if (!dryRun) {
            LedgerBackfillLog backfillLog = LedgerBackfillLog.builder()
                    .shop_id(shopId != null ? shopId : 0)
                    .stat_date(statDate)
                    .dry_run(false)
                    .total_orders_scanned(totalOrdersScanned)
                    .backfilled_orders(backfilledOrders)
                    .skipped_orders(skippedOrders)
                    .total_rows_inserted(totalRowsInserted)
                    .total_amount_fen(totalAmountFen)
                    .anomalies_count(anomaliesCount)
                    .anomalies_json(anomaliesJson)
                    .integrity_hash(integrityHash)
                    .executed_by(adminId)
                    .executed_at(new Date())
                    .build();
            ledgerBackfillLogMapper.insert(backfillLog);
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("dry_run", dryRun);
        result.put("shop_id", shopId);
        result.put("stat_date", statDate);
        result.put("total_orders_scanned", totalOrdersScanned);
        result.put("backfilled_orders", backfilledOrders);
        result.put("skipped_orders", skippedOrders);
        result.put("total_rows_inserted", totalRowsInserted);
        result.put("total_amount_fen", totalAmountFen);
        result.put("channel_totals_fen", channelTotalsFen);
        result.put("anomalies_count", anomaliesCount);
        result.put("anomalies", anomalies);
        result.put("integrity_hash", integrityHash);
        result.put("executed_at", LocalDateTime.now().format(TIME_FMT));
        return result;
    }

    @Override
    public Map<String, Object> shadowVerify(Integer shopId, String statDate) {
        if (shopId == null || statDate == null || statDate.trim().isEmpty()) {
            throw new ApiException(400, "PARAM_ERROR", "门店 ID 与结算日期 stat_date 不能为空");
        }
        Shop shop = shopService.getById(shopId);
        if (shop == null) {
            throw new ApiException(404, "SHOP_NOT_FOUND", "门店不存在: " + shopId);
        }

        String s = statDate.trim();
        if (s.length() >= 10 && s.charAt(4) == '-' && s.charAt(7) == '-') {
            s = s.substring(0, 10);
        }
        LocalDate day = LocalDate.parse(s);
        Date[] win = ShopBusinessWindowResolver.operationalWindowFor(shop, day);

        // 1. 传统旧订单口径 (t_order)
        List<Order> orders = orderService.list(new QueryWrapper<Order>()
                .eq("shop_id", shopId)
                .eq("transac_status", "success")
                .ge("order_time", win[0]).lt("order_time", win[1]));

        int legacyOrderCount = orders.size();
        long legacyNetFen = orders.stream().mapToLong(OrderNetRevenue::netRevenueFen).sum();
        long legacyCashFen = Math.round(orders.stream().mapToDouble(o -> o.getPay_amount_cash() != null ? o.getPay_amount_cash() : 0.0).sum() * 100);
        long legacyWechatFen = Math.round(orders.stream().mapToDouble(o -> o.getPay_amount_wechat() != null ? o.getPay_amount_wechat() : 0.0).sum() * 100);
        long legacyAlipayFen = Math.round(orders.stream().mapToDouble(o -> o.getPay_amount_alipay() != null ? o.getPay_amount_alipay() : 0.0).sum() * 100);
        long legacyBalanceFen = Math.round(orders.stream().mapToDouble(o -> o.getPay_amount_balance() != null ? o.getPay_amount_balance() : 0.0).sum() * 100);
        long legacyGiftFen = Math.round(orders.stream().mapToDouble(o -> o.getPay_amount_gift() != null ? o.getPay_amount_gift() : 0.0).sum() * 100);

        // 2. 新支付账本口径 (t_payment_ledger)
        List<PaymentLedger> ledgers = paymentLedgerMapper.selectList(new QueryWrapper<PaymentLedger>()
                .eq("shop_id", shopId)
                .eq("business_day", statDate)
                .eq("status", PaymentLedger.STATUS_SUCCEEDED));

        int ledgerRowCount = ledgers.size();
        long ledgerNetFen = ledgers.stream().mapToLong(PaymentLedger::getAmount_fen).sum();
        long ledgerCashFen = ledgers.stream().filter(l -> PaymentLedger.CHANNEL_CASH.equals(l.getChannel())).mapToLong(PaymentLedger::getAmount_fen).sum();
        long ledgerWechatFen = ledgers.stream().filter(l -> PaymentLedger.CHANNEL_WECHAT.equals(l.getChannel())
                || PaymentLedger.CHANNEL_WECHAT_QR.equals(l.getChannel())).mapToLong(PaymentLedger::getAmount_fen).sum();
        long ledgerAlipayFen = ledgers.stream().filter(l -> PaymentLedger.CHANNEL_ALIPAY.equals(l.getChannel())
                || PaymentLedger.CHANNEL_ALIPAY_QR.equals(l.getChannel())).mapToLong(PaymentLedger::getAmount_fen).sum();
        long ledgerBalanceFen = ledgers.stream().filter(l -> PaymentLedger.CHANNEL_BALANCE_PRINCIPAL.equals(l.getChannel())).mapToLong(PaymentLedger::getAmount_fen).sum();
        long ledgerGiftFen = ledgers.stream().filter(l -> PaymentLedger.CHANNEL_GIFT.equals(l.getChannel())).mapToLong(PaymentLedger::getAmount_fen).sum();

        // 3. 逐单对碰与差异挖掘
        Map<Long, Integer> orderLedgerSums = ledgers.stream()
                .collect(Collectors.groupingBy(PaymentLedger::getOrder_id, Collectors.summingInt(PaymentLedger::getAmount_fen)));

        List<Map<String, Object>> discrepancies = new ArrayList<>();
        for (Order o : orders) {
            int expFen = OrderNetRevenue.netRevenueFen(o);
            int actFen = orderLedgerSums.getOrDefault(o.getId().longValue(), 0);
            if (expFen != actFen) {
                Map<String, Object> disc = new HashMap<>();
                disc.put("order_id", o.getId());
                disc.put("order_no", o.getOrder_no());
                disc.put("expected_fen", expFen);
                disc.put("ledger_actual_fen", actFen);
                disc.put("diff_fen", actFen - expFen);
                disc.put("type", actFen == 0 ? "LEDGER_MISSING" : "AMOUNT_MISMATCH");
                discrepancies.add(disc);
            }
        }

        long netVarianceFen = ledgerNetFen - legacyNetFen;
        long cashVarianceFen = ledgerCashFen - legacyCashFen;
        long wechatVarianceFen = ledgerWechatFen - legacyWechatFen;
        long alipayVarianceFen = ledgerAlipayFen - legacyAlipayFen;
        long balanceVarianceFen = ledgerBalanceFen - legacyBalanceFen;

        boolean readyForCutover = (netVarianceFen == 0 && discrepancies.isEmpty());

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("shop_id", shopId);
        res.put("stat_date", statDate);
        res.put("ready_for_cutover", readyForCutover);
        res.put("net_variance_fen", netVarianceFen);
        res.put("discrepancy_count", discrepancies.size());
        res.put("discrepancies", discrepancies);

        Map<String, Object> legacySum = new LinkedHashMap<>();
        legacySum.put("order_count", legacyOrderCount);
        legacySum.put("net_revenue_fen", legacyNetFen);
        legacySum.put("cash_fen", legacyCashFen);
        legacySum.put("wechat_fen", legacyWechatFen);
        legacySum.put("alipay_fen", legacyAlipayFen);
        legacySum.put("balance_fen", legacyBalanceFen);
        legacySum.put("gift_fen", legacyGiftFen);
        res.put("legacy_order_summary", legacySum);

        Map<String, Object> ledgerSum = new LinkedHashMap<>();
        ledgerSum.put("row_count", ledgerRowCount);
        ledgerSum.put("net_revenue_fen", ledgerNetFen);
        ledgerSum.put("cash_fen", ledgerCashFen);
        ledgerSum.put("wechat_fen", ledgerWechatFen);
        ledgerSum.put("alipay_fen", ledgerAlipayFen);
        ledgerSum.put("balance_fen", ledgerBalanceFen);
        ledgerSum.put("gift_fen", ledgerGiftFen);
        res.put("ledger_summary", ledgerSum);

        Map<String, Object> variances = new LinkedHashMap<>();
        variances.put("net_variance_fen", netVarianceFen);
        variances.put("cash_variance_fen", cashVarianceFen);
        variances.put("wechat_variance_fen", wechatVarianceFen);
        variances.put("alipay_variance_fen", alipayVarianceFen);
        variances.put("balance_variance_fen", balanceVarianceFen);
        res.put("channel_variances", variances);

        return res;
    }

    @Override
    public Map<String, Object> getCutoverStatus(Integer shopId) {
        String currentReadSource = getReadSource(shopId);

        QueryWrapper<PaymentLedger> q = new QueryWrapper<PaymentLedger>();
        if (shopId != null && shopId > 0) {
            q.eq("shop_id", shopId);
        }
        int totalLedgerRows = paymentLedgerMapper.selectCount(q);

        QueryWrapper<PaymentLedger> qNative = new QueryWrapper<PaymentLedger>()
                .eq("source", PaymentLedger.SOURCE_NATIVE);
        if (shopId != null && shopId > 0) qNative.eq("shop_id", shopId);
        int nativeRows = paymentLedgerMapper.selectCount(qNative);

        QueryWrapper<PaymentLedger> qBf = new QueryWrapper<PaymentLedger>()
                .eq("source", PaymentLedger.SOURCE_BACKFILLED_ORDER);
        if (shopId != null && shopId > 0) qBf.eq("shop_id", shopId);
        int backfilledRows = paymentLedgerMapper.selectCount(qBf);

        QueryWrapper<LedgerBackfillLog> logQ = new QueryWrapper<LedgerBackfillLog>()
                .orderByDesc("executed_at");
        if (shopId != null && shopId > 0) {
            logQ.eq("shop_id", shopId);
        }
        List<LedgerBackfillLog> logs = ledgerBackfillLogMapper.selectList(logQ);
        LedgerBackfillLog lastLog = logs.isEmpty() ? null : logs.get(0);

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("shop_id", shopId);
        res.put("current_read_source", currentReadSource);
        res.put("is_cutover_to_ledger", READ_SOURCE_PAYMENT_LEDGER.equals(currentReadSource));
        res.put("total_ledger_rows", totalLedgerRows);
        res.put("native_rows", nativeRows);
        res.put("backfilled_rows", backfilledRows);
        res.put("last_backfill_log", lastLog);
        return res;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> cutoverReadSource(Integer shopId, Integer adminId, String targetSource) {
        if (!READ_SOURCE_PAYMENT_LEDGER.equalsIgnoreCase(targetSource)
                && !READ_SOURCE_LEGACY_ORDER.equalsIgnoreCase(targetSource)) {
            throw new ApiException(400, "INVALID_READ_SOURCE",
                    "读源类型必须为 " + READ_SOURCE_PAYMENT_LEDGER + " 或 " + READ_SOURCE_LEGACY_ORDER);
        }
        int resolvedShopId = shopId != null ? shopId : 0;
        String normalizedSource = targetSource.toUpperCase();

        SystemConfig existing = systemConfigMapper.selectByShopAndKey(resolvedShopId, CONFIG_KEY_READ_SOURCE);
        if (existing == null) {
            SystemConfig cfg = new SystemConfig();
            cfg.setShop_id(resolvedShopId);
            cfg.setConfig_key(CONFIG_KEY_READ_SOURCE);
            cfg.setConfig_value(normalizedSource);
            cfg.setRemark("POS 商业级收银结算数据读源切换 (操作人: " + adminId + ")");
            systemConfigMapper.insert(cfg);
        } else {
            existing.setConfig_value(normalizedSource);
            existing.setRemark("POS 商业级收银结算数据读源切换 (操作人: " + adminId + ")");
            systemConfigMapper.updateById(existing);
        }

        log.info("[LedgerMigration] 读源已切换: shopId={}, targetSource={}, adminId={}",
                resolvedShopId, normalizedSource, adminId);

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("shop_id", resolvedShopId);
        res.put("current_read_source", normalizedSource);
        res.put("cutover_at", LocalDateTime.now().format(TIME_FMT));
        res.put("operator_id", adminId);
        return res;
    }

    @Override
    public String getReadSource(Integer shopId) {
        int targetShopId = shopId != null ? shopId : 0;
        SystemConfig sc = systemConfigMapper.selectByShopAndKey(targetShopId, CONFIG_KEY_READ_SOURCE);
        if (sc != null && sc.getConfig_value() != null) {
            return sc.getConfig_value().trim().toUpperCase();
        }
        if (targetShopId != 0) {
            SystemConfig globalSc = systemConfigMapper.selectByShopAndKey(0, CONFIG_KEY_READ_SOURCE);
            if (globalSc != null && globalSc.getConfig_value() != null) {
                return globalSc.getConfig_value().trim().toUpperCase();
            }
        }
        // 默认即为商用级别新台账模式
        return READ_SOURCE_PAYMENT_LEDGER;
    }

    private static String sha256Hex(String input) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] hash = md.digest(input.getBytes(StandardCharsets.UTF_8));
            StringBuilder hexString = new StringBuilder();
            for (byte b : hash) {
                String hex = Integer.toHexString(0xff & b);
                if (hex.length() == 1) hexString.append('0');
                hexString.append(hex);
            }
            return hexString.toString();
        } catch (Exception e) {
            throw new RuntimeException("SHA-256 计算失败: " + e.getMessage(), e);
        }
    }
}

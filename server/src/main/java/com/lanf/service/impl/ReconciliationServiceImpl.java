package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.entity.*;
import com.lanf.mapper.*;
import com.lanf.service.IOrderService;
import com.lanf.service.IReconciliationService;
import com.lanf.service.IShopService;
import com.lanf.receivable.service.ReceivableService;
import com.lanf.util.AdminShopRequest;
import com.lanf.util.OrderNetRevenue;
import com.lanf.util.OrderPayChannelAmounts;
import com.lanf.util.ShopBusinessWindowResolver;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;

@Service
public class ReconciliationServiceImpl implements IReconciliationService {

    @Autowired
    private ChannelStatementBatchMapper batchMapper;
    @Autowired
    private ChannelStatementEntryMapper entryMapper;
    @Autowired
    private ReconciliationCaseMapper caseMapper;
    @Autowired
    private PaymentLedgerMapper ledgerMapper;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private IShopService shopService;
    @Autowired
    private ObjectMapper objectMapper;

    private static final String DATE_FORMAT = "yyyy-MM-dd HH:mm:ss";
    private static final String DATE_ONLY_FORMAT = "yyyy-MM-dd";

    @Override
    @Transactional(rollbackFor = Exception.class)
    public ChannelStatementBatch importStatement(Integer shopId, Integer adminId, String channel, String fileName, String contentText) {
        if (contentText == null || contentText.trim().isEmpty()) {
            throw new ApiException(400, "INVALID_PARAM", "对账单文件内容不能为空");
        }
        if (shopId == null) {
            shopId = 1;
        }
        if (channel == null || channel.trim().isEmpty()) {
            channel = "WECHAT";
        }
        channel = channel.trim().toUpperCase();

        // 1. 计算文件 SHA-256 并防重校验
        String sha256 = computeSha256(contentText);
        QueryWrapper<ChannelStatementBatch> dupQ = new QueryWrapper<ChannelStatementBatch>()
                .eq("shop_id", shopId)
                .eq("file_hash_sha256", sha256);
        ChannelStatementBatch existing = batchMapper.selectOne(dupQ);
        if (existing != null) {
            throw new ApiException(409, "DUPLICATE_FILE", "对账单文件已导入，批次号：" + existing.getBatch_no() + "（导入时间：" + existing.getImported_at() + "）");
        }

        // 2. 智能解析对账单内容
        List<String> errorLines = new ArrayList<>();
        List<ParsedEntry> parsedEntries = parseContent(contentText, channel, errorLines);

        if (parsedEntries.isEmpty()) {
            throw new ApiException(400, "PARSE_FAILED", "未解析到有效对账明细。可能原因：格式不匹配或全部行校验失败。错误摘要：" + String.join("; ", errorLines));
        }

        // 3. 计算批次汇总指标
        Date statementDate = parsedEntries.get(0).tradeTime;
        long totalAmountFen = 0;
        long totalFeeFen = 0;
        for (ParsedEntry pe : parsedEntries) {
            totalAmountFen += pe.amountFen;
            totalFeeFen += pe.feeFen;
        }
        long netAmountFen = totalAmountFen - totalFeeFen;

        String dayStr = new SimpleDateFormat(DATE_ONLY_FORMAT).format(statementDate);
        String batchNo = "BAT-" + dayStr.replace("-", "") + "-" + UUID.randomUUID().toString().substring(0, 6).toUpperCase();

        ChannelStatementBatch batch = ChannelStatementBatch.builder()
                .batch_no(batchNo)
                .shop_id(shopId)
                .channel(channel)
                .statement_date(statementDate)
                .file_name(fileName != null ? fileName : "statement_" + batchNo + ".csv")
                .file_hash_sha256(sha256)
                .total_count(parsedEntries.size())
                .total_amount_fen(totalAmountFen)
                .fee_fen(totalFeeFen)
                .net_amount_fen(netAmountFen)
                .status(ChannelStatementBatch.STATUS_PARSED)
                .error_summary(errorLines.isEmpty() ? null : String.join("\n", errorLines))
                .imported_by(adminId)
                .imported_at(new Date())
                .created_at(new Date())
                .build();
        batchMapper.insert(batch);

        // 4. 落库渠道对账明细
        for (ParsedEntry pe : parsedEntries) {
            ChannelStatementEntry entry = ChannelStatementEntry.builder()
                    .batch_id(batch.getId())
                    .shop_id(shopId)
                    .channel(channel)
                    .channel_trade_no(pe.channelTradeNo)
                    .merchant_order_no(pe.merchantOrderNo)
                    .entry_type(pe.entryType)
                    .amount_fen(pe.amountFen)
                    .fee_fen(pe.feeFen)
                    .net_amount_fen(pe.amountFen - pe.feeFen)
                    .trade_time(pe.tradeTime)
                    .match_status(ChannelStatementEntry.MATCH_STATUS_UNMATCHED)
                    .created_at(new Date())
                    .build();
            entryMapper.insert(entry);
            pe.savedEntryId = entry.getId();
        }

        // 5. 自动执行该营业日的三层对账匹配与差异单生成
        triggerReconciliation(shopId, dayStr, channel, batch.getId());

        return batch;
    }

    @Override
    public Map<String, Object> getReconciliationOverview(Integer shopId, String statDate) {
        Shop shop = resolveShop(shopId);
        LocalDate settlementDay = resolveSettlementDay(shop, statDate);
        String businessDay = settlementDay.toString();
        Date[] win = settlementWindow(shop, businessDay, settlementDay);

        // 1. 查询渠道对账单导入批次
        QueryWrapper<ChannelStatementBatch> batchQ = new QueryWrapper<ChannelStatementBatch>()
                .eq("shop_id", shop.getId())
                .ge("statement_date", win[0]).lt("statement_date", win[1]);
        List<ChannelStatementBatch> batches = batchMapper.selectList(batchQ);
        boolean hasChannelStatement = !batches.isEmpty();

        // 2. 第一层：订单 vs 内部支付台账 (Order vs Payment Ledger)
        QueryWrapper<Order> orderQ = new QueryWrapper<Order>()
                .eq("transac_status", "success")
                .eq("shop_id", shop.getId())
                .and(w -> w.ge("pay_time", win[0]).lt("pay_time", win[1])
                        .or(ow -> ow.isNull("pay_time").ge("order_time", win[0]).lt("order_time", win[1])))
                .and(w -> w.ne("payment_method", ReceivableService.PAYMENT_METHOD_RECEIVABLE)
                        .or().isNull("payment_method"));
        List<Order> orders = orderService.list(orderQ);
        long orderTotalAmountFen = 0;
        for (Order o : orders) {
            int projectedFen = OrderPayChannelAmounts.totalPayChannelAmountFen(o);
            orderTotalAmountFen += projectedFen > 0 ? projectedFen : OrderNetRevenue.netRevenueFen(o);
        }

        QueryWrapper<PaymentLedger> ledgerQ = new QueryWrapper<PaymentLedger>()
                .eq("shop_id", shop.getId())
                .eq("business_day", businessDay)
                .eq("status", "SUCCEEDED");
        List<PaymentLedger> ledgers = ledgerMapper.selectList(ledgerQ);
        long ledgerTotalAmountFen = 0;
        int ledgerPaymentsCount = 0;
        int ledgerRefundsCount = 0;
        for (PaymentLedger pl : ledgers) {
            ledgerTotalAmountFen += pl.getAmount_fen();
            if ("PAYMENT".equals(pl.getEntry_type())) {
                ledgerPaymentsCount++;
            } else if ("REFUND".equals(pl.getEntry_type()) || "REVERSAL".equals(pl.getEntry_type())) {
                ledgerRefundsCount++;
            }
        }
        long layer1DiffFen = orderTotalAmountFen - ledgerTotalAmountFen;
        boolean layer1Balanced = (layer1DiffFen == 0);

        Map<String, Object> layer1 = new LinkedHashMap<>();
        layer1.put("layer", 1);
        layer1.put("name", "订单与内部台账核对");
        layer1.put("order_count", orders.size());
        layer1.put("order_net_sales_fen", orderTotalAmountFen);
        layer1.put("ledger_count", ledgers.size());
        layer1.put("ledger_net_amount_fen", ledgerTotalAmountFen);
        layer1.put("difference_fen", layer1DiffFen);
        layer1.put("balanced", layer1Balanced);

        // 3. 第二层：内部支付台账 vs 渠道对账单 (Ledger vs Channel Statement)
        Map<String, Object> layer2 = new LinkedHashMap<>();
        layer2.put("layer", 2);
        layer2.put("name", "内部台账与渠道账单核对");
        layer2.put("has_statement", hasChannelStatement);

        long channelTotalAmountFen = 0;
        long channelFeeFen = 0;
        int channelTradeCount = 0;
        int matchedCount = 0;
        int unmatchedInternalCount = 0;
        int unmatchedChannelCount = 0;
        int amountMismatchCount = 0;

        Set<String> statementChannels = new HashSet<>();
        for (ChannelStatementBatch batch : batches) {
            if (batch.getChannel() != null && !batch.getChannel().trim().isEmpty()) {
                statementChannels.add(batch.getChannel().trim().toUpperCase(Locale.ROOT));
            }
        }
        List<PaymentLedger> externalLedgers = new ArrayList<>();
        for (PaymentLedger ledger : ledgers) {
            boolean externalEntry = PaymentLedger.ENTRY_TYPE_PAYMENT.equals(ledger.getEntry_type())
                    || PaymentLedger.ENTRY_TYPE_REFUND.equals(ledger.getEntry_type());
            boolean selectedChannel = statementChannels.isEmpty()
                    || (ledger.getChannel() != null
                    && statementChannels.contains(ledger.getChannel().trim().toUpperCase(Locale.ROOT)));
            if (externalEntry && selectedChannel) {
                externalLedgers.add(ledger);
            }
        }
        long externalLedgerNetFen = externalLedgers.stream()
                .map(PaymentLedger::getAmount_fen).filter(Objects::nonNull)
                .mapToLong(Integer::longValue).sum();

        if (!hasChannelStatement) {
            layer2.put("status", "UNIMPORTED");
            layer2.put("message", "未导入微信/支付宝官方渠道对账单，仅展示内部流水汇总，严禁标记已对平");
            layer2.put("internal_payments_count", ledgerPaymentsCount);
            layer2.put("internal_refunds_count", ledgerRefundsCount);
            layer2.put("internal_net_amount_fen", ledgerTotalAmountFen);
        } else {
            // 已导入：统计批次及明细
            for (ChannelStatementBatch b : batches) {
                channelTotalAmountFen += b.getTotal_amount_fen();
                channelFeeFen += b.getFee_fen();
                channelTradeCount += b.getTotal_count();
            }

            QueryWrapper<ChannelStatementEntry> entryQ = new QueryWrapper<ChannelStatementEntry>()
                    .eq("shop_id", shop.getId())
                    .in("batch_id", batches.stream().map(ChannelStatementBatch::getId).toArray());
            List<ChannelStatementEntry> entries = entryMapper.selectList(entryQ);

            for (ChannelStatementEntry e : entries) {
                if (ChannelStatementEntry.MATCH_STATUS_MATCHED.equals(e.getMatch_status())) {
                    matchedCount++;
                } else if (ChannelStatementEntry.MATCH_STATUS_AMOUNT_MISMATCH.equals(e.getMatch_status())) {
                    amountMismatchCount++;
                } else if (ChannelStatementEntry.MATCH_STATUS_UNMATCHED.equals(e.getMatch_status())) {
                    unmatchedChannelCount++;
                }
            }
            unmatchedInternalCount = Math.max(0, externalLedgers.size() - matchedCount - amountMismatchCount);

            layer2.put("status", (amountMismatchCount == 0 && unmatchedChannelCount == 0 && unmatchedInternalCount == 0) ? "BALANCED" : "DISCREPANCY");
            layer2.put("channel_trade_count", channelTradeCount);
            layer2.put("channel_total_amount_fen", channelTotalAmountFen);
            layer2.put("matched_count", matchedCount);
            layer2.put("amount_mismatch_count", amountMismatchCount);
            layer2.put("unmatched_internal_count", unmatchedInternalCount);
            layer2.put("unmatched_channel_count", unmatchedChannelCount);
            layer2.put("internal_net_amount_fen", externalLedgerNetFen);
            layer2.put("difference_fen", externalLedgerNetFen - channelTotalAmountFen);
        }

        // 4. 第三层：渠道账单 vs 扣费到账净额 (Channel vs Settlement)
        Map<String, Object> layer3 = new LinkedHashMap<>();
        layer3.put("layer", 3);
        layer3.put("name", "渠道账单与资金结算核对");
        layer3.put("channel_gross_fen", channelTotalAmountFen);
        layer3.put("fee_fen", channelFeeFen);
        layer3.put("net_settlement_fen", channelTotalAmountFen - channelFeeFen);

        // 5. 差异处理单统计
        QueryWrapper<ReconciliationCase> caseQ = new QueryWrapper<ReconciliationCase>()
                .eq("shop_id", shop.getId())
                .eq("business_day", java.sql.Date.valueOf(settlementDay));
        List<ReconciliationCase> cases = caseMapper.selectList(caseQ);
        long openCasesCount = cases.stream().filter(c -> !ReconciliationCase.STATUS_CLOSED.equals(c.getStatus())).count();

        // 6. 综合状态判定规则 (核心守则)
        // 未导入账单 -> UNIMPORTED
        // 导入账单且存在未关闭差异单或不平衡 -> DISCREPANCY
        // 导入账单且第一层平衡且第二层平衡且无未关闭差异单 -> RECONCILED
        String summaryStatus;
        if (!hasChannelStatement) {
            summaryStatus = "UNIMPORTED";
        } else if (!layer1Balanced || openCasesCount > 0 || amountMismatchCount > 0
                || unmatchedChannelCount > 0 || unmatchedInternalCount > 0) {
            summaryStatus = "DISCREPANCY";
        } else {
            summaryStatus = "RECONCILED";
        }

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("business_day", businessDay);
        res.put("shop_id", shop.getId());
        res.put("shop_name", shop.getName());
        res.put("has_channel_statement", hasChannelStatement);
        res.put("summary_status", summaryStatus);
        res.put("open_cases_count", openCasesCount);
        res.put("total_cases_count", cases.size());
        res.put("batches_count", batches.size());
        res.put("layer1", layer1);
        res.put("layer2", layer2);
        res.put("layer3", layer3);
        return res;
    }

    @Override
    public List<ChannelStatementBatch> getBatches(Integer shopId, String statDate, String channel) {
        Shop shop = resolveShop(shopId);
        QueryWrapper<ChannelStatementBatch> q = new QueryWrapper<ChannelStatementBatch>()
                .eq("shop_id", shop.getId())
                .orderByDesc("imported_at");
        if (statDate != null && !statDate.trim().isEmpty()) {
            q.eq("statement_date", statDate.trim());
        }
        if (channel != null && !channel.trim().isEmpty()) {
            q.eq("channel", channel.trim().toUpperCase());
        }
        return batchMapper.selectList(q);
    }

    @Override
    public List<ReconciliationCase> getCases(Integer shopId, String statDate, String status, String discrepancyType) {
        Shop shop = resolveShop(shopId);
        QueryWrapper<ReconciliationCase> q = new QueryWrapper<ReconciliationCase>()
                .eq("shop_id", shop.getId())
                .orderByDesc("created_at");
        if (statDate != null && !statDate.trim().isEmpty()) {
            q.eq("business_day", statDate.trim());
        }
        if (status != null && !status.trim().isEmpty()) {
            q.eq("status", status.trim());
        }
        if (discrepancyType != null && !discrepancyType.trim().isEmpty()) {
            q.eq("discrepancy_type", discrepancyType.trim());
        }
        return caseMapper.selectList(q);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public ReconciliationCase resolveCase(Integer shopId, Integer adminId, Long caseId, String status, String resolutionNote, String responsiblePerson) {
        ReconciliationCase rc = caseMapper.selectById(caseId);
        if (rc == null) {
            throw new ApiException(404, "NOT_FOUND", "差异处理单不存在");
        }
        if (shopId != null && !shopId.equals(rc.getShop_id())) {
            throw new ApiException(403, "FORBIDDEN", "无权操作其他门店差异单");
        }

        if (status != null && !status.trim().isEmpty()) {
            rc.setStatus(status.trim().toUpperCase());
        } else {
            rc.setStatus(ReconciliationCase.STATUS_CLOSED);
        }
        if (resolutionNote != null) {
            rc.setResolution_note(resolutionNote.trim());
        }
        if (responsiblePerson != null) {
            rc.setResponsible_person(responsiblePerson.trim());
        }
        rc.setResolved_by(adminId);
        rc.setResolved_at(new Date());
        rc.setUpdated_at(new Date());
        caseMapper.updateById(rc);
        return rc;
    }

    /**
     * 自动触发该营业日的三层对账匹配与差异单生成
     */
    private void triggerReconciliation(Integer shopId, String dayStr, String channel, Long batchId) {
        // 查找当日该渠道的所有内部支付台账
        QueryWrapper<PaymentLedger> lq = new QueryWrapper<PaymentLedger>()
                .eq("shop_id", shopId)
                .eq("business_day", dayStr)
                .eq("status", "SUCCEEDED")
                .in("entry_type", PaymentLedger.ENTRY_TYPE_PAYMENT, PaymentLedger.ENTRY_TYPE_REFUND);
        if ("WECHAT".equalsIgnoreCase(channel)) {
            lq.eq("channel", "WECHAT");
        } else if ("ALIPAY".equalsIgnoreCase(channel)) {
            lq.eq("channel", "ALIPAY");
        }
        List<PaymentLedger> ledgers = ledgerMapper.selectList(lq);

        // 查找该批次导入的渠道明细
        QueryWrapper<ChannelStatementEntry> eq = new QueryWrapper<ChannelStatementEntry>()
                .eq("batch_id", batchId);
        List<ChannelStatementEntry> entries = entryMapper.selectList(eq);

        Map<String, List<ChannelStatementEntry>> entryByTradeNo = new HashMap<>();
        Map<String, List<ChannelStatementEntry>> entryByOrderNo = new HashMap<>();
        for (ChannelStatementEntry e : entries) {
            String type = normalizedEntryType(e.getEntry_type());
            if (e.getChannel_trade_no() != null) {
                entryByTradeNo.computeIfAbsent(type + "|" + e.getChannel_trade_no(), ignored -> new ArrayList<>())
                        .add(e);
            }
            if (e.getMerchant_order_no() != null) {
                entryByOrderNo.computeIfAbsent(type + "|" + e.getMerchant_order_no(), ignored -> new ArrayList<>())
                        .add(e);
            }
        }

        Set<Long> matchedEntryIds = new HashSet<>();

        // 遍历内部台账匹配渠道明细
        for (PaymentLedger ledger : ledgers) {
            ChannelStatementEntry matched = null;
            String type = normalizedEntryType(ledger.getEntry_type());
            if (ledger.getProvider_transaction_id() != null) {
                matched = findUnmatchedEntry(entryByTradeNo.get(
                        type + "|" + ledger.getProvider_transaction_id()), matchedEntryIds, ledger.getAmount_fen());
            }
            if (matched == null && ledger.getOrder_no() != null) {
                matched = findUnmatchedEntry(entryByOrderNo.get(
                        type + "|" + ledger.getOrder_no()), matchedEntryIds, ledger.getAmount_fen());
            }

            if (matched == null) {
                // 内部有流水，渠道缺失 -> CHANNEL_MISSING 差异单
                createCaseIfAbsent(shopId, dayStr, channel, ReconciliationCase.LAYER_LEDGER_VS_CHANNEL,
                        ReconciliationCase.TYPE_CHANNEL_MISSING, ledger.getOrder_id(), ledger.getId(), null,
                        ledger.getAmount_fen(), 0, "内部存在成功支付台账，但渠道对账单未找到对应记录");
            } else {
                matchedEntryIds.add(matched.getId());
                matched.setMatched_ledger_id(ledger.getId());

                if (!matched.getAmount_fen().equals(ledger.getAmount_fen())) {
                    // 金额不符 -> AMOUNT_MISMATCH
                    matched.setMatch_status(ChannelStatementEntry.MATCH_STATUS_AMOUNT_MISMATCH);
                    createCaseIfAbsent(shopId, dayStr, channel, ReconciliationCase.LAYER_LEDGER_VS_CHANNEL,
                            ReconciliationCase.TYPE_AMOUNT_MISMATCH, ledger.getOrder_id(), ledger.getId(), matched.getId(),
                            ledger.getAmount_fen(), matched.getAmount_fen(), "内部支付台账金额与渠道明细金额不一致");
                } else {
                    matched.setMatch_status(ChannelStatementEntry.MATCH_STATUS_MATCHED);
                }
                entryMapper.updateById(matched);
            }
        }

        // 遍历渠道明细未匹配内部台账的情况 -> INTERNAL_MISSING 差异单
        for (ChannelStatementEntry entry : entries) {
            if (!matchedEntryIds.contains(entry.getId())) {
                entry.setMatch_status(ChannelStatementEntry.MATCH_STATUS_UNMATCHED);
                entryMapper.updateById(entry);
                createCaseIfAbsent(shopId, dayStr, channel, ReconciliationCase.LAYER_LEDGER_VS_CHANNEL,
                        ReconciliationCase.TYPE_INTERNAL_MISSING, null, null, entry.getId(),
                        0, entry.getAmount_fen(), "渠道对账单存在该笔交易，但内部系统无对应成功支付台账（可能漏单或回调丢失）");
            }
        }
    }

    private static String normalizedEntryType(String type) {
        return ChannelStatementEntry.ENTRY_TYPE_REFUND.equalsIgnoreCase(type)
                ? ChannelStatementEntry.ENTRY_TYPE_REFUND : ChannelStatementEntry.ENTRY_TYPE_PAYMENT;
    }

    private static ChannelStatementEntry findUnmatchedEntry(
            List<ChannelStatementEntry> candidates, Set<Long> matchedEntryIds, Integer expectedAmountFen) {
        if (candidates == null || candidates.isEmpty()) {
            return null;
        }
        ChannelStatementEntry fallback = null;
        for (ChannelStatementEntry candidate : candidates) {
            if (candidate == null || matchedEntryIds.contains(candidate.getId())) {
                continue;
            }
            if (Objects.equals(expectedAmountFen, candidate.getAmount_fen())) {
                return candidate;
            }
            if (fallback == null) {
                fallback = candidate;
            }
        }
        return fallback;
    }

    private void createCaseIfAbsent(Integer shopId, String dayStr, String channel, int layer,
                                    String discrepancyType, Long orderId, Long ledgerId, Long entryId,
                                    int internalAmount, int channelAmount, String reason) {
        QueryWrapper<ReconciliationCase> q = new QueryWrapper<ReconciliationCase>()
                .eq("shop_id", shopId)
                .eq("business_day", dayStr)
                .eq("discrepancy_type", discrepancyType);
        if (ledgerId != null) {
            q.eq("ledger_id", ledgerId);
        } else if (entryId != null) {
            q.eq("statement_entry_id", entryId);
        }
        if (caseMapper.selectCount(q) > 0) {
            return;
        }

        String caseNo = "CASE-" + dayStr.replace("-", "") + "-" + UUID.randomUUID().toString().substring(0, 6).toUpperCase();
        try {
            ReconciliationCase rc = ReconciliationCase.builder()
                    .case_no(caseNo)
                    .shop_id(shopId)
                    .business_day(java.sql.Date.valueOf(LocalDate.parse(dayStr)))
                    .channel(channel)
                    .layer(layer)
                    .discrepancy_type(discrepancyType)
                    .status(ReconciliationCase.STATUS_OPEN)
                    .order_id(orderId)
                    .ledger_id(ledgerId)
                    .statement_entry_id(entryId)
                    .internal_amount_fen(internalAmount)
                    .channel_amount_fen(channelAmount)
                    .difference_fen(internalAmount - channelAmount)
                    .reason(reason)
                    .created_at(new Date())
                    .updated_at(new Date())
                    .build();
            caseMapper.insert(rc);
        } catch (Exception ignored) {
        }
    }

    private List<ParsedEntry> parseContent(String content, String channel, List<String> errorLines) {
        content = content.trim();
        if (content.startsWith("\uFEFF")) {
            content = content.substring(1);
        }

        if (content.startsWith("[")) {
            // JSON 解析
            return parseJson(content, channel, errorLines);
        } else {
            // CSV 解析
            return parseCsv(content, channel, errorLines);
        }
    }

    private List<ParsedEntry> parseJson(String json, String channel, List<String> errorLines) {
        List<ParsedEntry> list = new ArrayList<>();
        try {
            List<Map<String, Object>> rows = objectMapper.readValue(json, new TypeReference<List<Map<String, Object>>>() {});
            int index = 0;
            for (Map<String, Object> row : rows) {
                index++;
                try {
                    ParsedEntry pe = new ParsedEntry();
                    pe.channel = channel;
                    pe.channelTradeNo = String.valueOf(row.getOrDefault("channel_trade_no", row.get("trade_no")));
                    pe.merchantOrderNo = String.valueOf(row.getOrDefault("merchant_order_no", row.get("order_no")));
                    String type = String.valueOf(row.getOrDefault("entry_type", "PAYMENT")).toUpperCase();
                    pe.entryType = type.contains("REFUND") ? ChannelStatementEntry.ENTRY_TYPE_REFUND : ChannelStatementEntry.ENTRY_TYPE_PAYMENT;

                    Object amtObj = row.get("amount");
                    if (amtObj == null) amtObj = row.get("amount_fen");
                    if (amtObj instanceof Number) {
                        double val = ((Number) amtObj).doubleValue();
                        pe.amountFen = val > 1000 ? (int) Math.round(val) : (int) Math.round(val * 100);
                    } else {
                        pe.amountFen = (int) Math.round(Double.parseDouble(String.valueOf(amtObj)) * 100);
                    }

                    Object feeObj = row.getOrDefault("fee", row.get("fee_fen"));
                    if (feeObj instanceof Number) {
                        double fval = ((Number) feeObj).doubleValue();
                        pe.feeFen = fval > 100 ? (int) Math.round(fval) : (int) Math.round(fval * 100);
                    } else if (feeObj != null) {
                        pe.feeFen = (int) Math.round(Double.parseDouble(String.valueOf(feeObj)) * 100);
                    }

                    String timeStr = String.valueOf(row.getOrDefault("trade_time", row.get("time")));
                    pe.tradeTime = parseDate(timeStr);
                    list.add(pe);
                } catch (Exception e) {
                    errorLines.add("JSON item " + index + ": " + e.getMessage());
                }
            }
        } catch (Exception e) {
            errorLines.add("JSON 解析错误: " + e.getMessage());
        }
        return list;
    }

    private List<ParsedEntry> parseCsv(String csv, String channel, List<String> errorLines) {
        List<ParsedEntry> list = new ArrayList<>();
        String[] lines = csv.split("\\r?\\n");
        if (lines.length == 0) return list;

        int headerIndex = -1;
        boolean isWechat = false;
        boolean isAlipay = false;

        for (int i = 0; i < lines.length; i++) {
            String l = lines[i].trim();
            if (l.isEmpty() || l.startsWith("#")) continue;
            if (l.contains("微信订单号") || l.contains("商户订单号") || l.contains("业务流水号") || l.contains("trade_time") || l.contains("channel_trade_no")) {
                headerIndex = i;
                if (l.contains("微信订单号")) isWechat = true;
                if (l.contains("业务流水号") || l.contains("发生时间")) isAlipay = true;
                break;
            }
        }

        if (headerIndex == -1) {
            headerIndex = 0; // 假定第 0 行为表头
        }

        String[] headers = splitCsvLine(lines[headerIndex]);
        Map<String, Integer> colMap = new HashMap<>();
        for (int c = 0; c < headers.length; c++) {
            colMap.put(headers[c].trim().replaceAll("^`+|`+$", ""), c);
        }

        for (int i = headerIndex + 1; i < lines.length; i++) {
            String line = lines[i].trim();
            if (line.isEmpty() || line.startsWith("#") || line.startsWith("总交易单数") || line.startsWith("总申请退款金额")) {
                continue;
            }
            try {
                String[] cols = splitCsvLine(line);
                if (cols.length < 3) {
                    continue;
                }
                ParsedEntry pe = new ParsedEntry();
                pe.channel = channel;

                if (isWechat || colMap.containsKey("微信订单号")) {
                    pe.tradeTime = parseDate(cleanCsvVal(cols, colMap, "交易时间", 0));
                    pe.channelTradeNo = cleanCsvVal(cols, colMap, "微信订单号", 5);
                    pe.merchantOrderNo = cleanCsvVal(cols, colMap, "商户订单号", 6);
                    String status = cleanCsvVal(cols, colMap, "交易状态", 9);
                    pe.entryType = (status != null && status.contains("REFUND")) ? ChannelStatementEntry.ENTRY_TYPE_REFUND : ChannelStatementEntry.ENTRY_TYPE_PAYMENT;
                    double amt = Double.parseDouble(cleanCsvVal(cols, colMap, "应结订单金额", 12));
                    pe.amountFen = (int) Math.round(amt * 100);
                    String feeStr = cleanCsvVal(cols, colMap, "手续费", 22);
                    pe.feeFen = (feeStr != null && !feeStr.isEmpty()) ? (int) Math.round(Double.parseDouble(feeStr) * 100) : 0;
                } else if (isAlipay || colMap.containsKey("业务流水号")) {
                    pe.tradeTime = parseDate(cleanCsvVal(cols, colMap, "发生时间", 4));
                    pe.channelTradeNo = cleanCsvVal(cols, colMap, "账务流水号", 0);
                    pe.merchantOrderNo = cleanCsvVal(cols, colMap, "商户订单号", 2);
                    String inStr = cleanCsvVal(cols, colMap, "收入金额（+元）", 6);
                    String outStr = cleanCsvVal(cols, colMap, "支出金额（-元）", 7);
                    if (inStr != null && !inStr.isEmpty() && Double.parseDouble(inStr) > 0) {
                        pe.entryType = ChannelStatementEntry.ENTRY_TYPE_PAYMENT;
                        pe.amountFen = (int) Math.round(Double.parseDouble(inStr) * 100);
                    } else {
                        pe.entryType = ChannelStatementEntry.ENTRY_TYPE_REFUND;
                        pe.amountFen = (outStr != null && !outStr.isEmpty()) ? (int) Math.round(Math.abs(Double.parseDouble(outStr)) * 100) : 0;
                    }
                    pe.feeFen = 0;
                } else {
                    // 通用 CSV: trade_time, channel, channel_trade_no, merchant_order_no, entry_type, amount, fee
                    pe.tradeTime = parseDate(cleanCsvVal(cols, colMap, "trade_time", 0));
                    pe.channelTradeNo = cleanCsvVal(cols, colMap, "channel_trade_no", 2);
                    pe.merchantOrderNo = cleanCsvVal(cols, colMap, "merchant_order_no", 3);
                    String type = cleanCsvVal(cols, colMap, "entry_type", 4);
                    pe.entryType = (type != null && type.toUpperCase().contains("REFUND")) ? ChannelStatementEntry.ENTRY_TYPE_REFUND : ChannelStatementEntry.ENTRY_TYPE_PAYMENT;
                    double amt = Double.parseDouble(cleanCsvVal(cols, colMap, "amount", 5));
                    pe.amountFen = (int) Math.round(amt * 100);
                    String feeStr = cleanCsvVal(cols, colMap, "fee", 6);
                    pe.feeFen = (feeStr != null && !feeStr.isEmpty()) ? (int) Math.round(Double.parseDouble(feeStr) * 100) : 0;
                }

                if (ChannelStatementEntry.ENTRY_TYPE_REFUND.equals(pe.entryType) && pe.amountFen > 0) {
                    pe.amountFen = -pe.amountFen;
                }
                if (pe.channelTradeNo == null || pe.channelTradeNo.isEmpty()) {
                    pe.channelTradeNo = pe.merchantOrderNo;
                }
                list.add(pe);
            } catch (Exception e) {
                errorLines.add("Line " + (i + 1) + ": " + e.getMessage());
            }
        }
        return list;
    }

    private String cleanCsvVal(String[] cols, Map<String, Integer> colMap, String colName, int fallbackIdx) {
        Integer idx = colMap.get(colName);
        if (idx == null) idx = fallbackIdx;
        if (idx >= cols.length) return null;
        String val = cols[idx].trim();
        return val.replaceAll("^`+|`+$", "").trim();
    }

    private String[] splitCsvLine(String line) {
        List<String> tokens = new ArrayList<>();
        boolean inQuotes = false;
        StringBuilder sb = new StringBuilder();
        for (char c : line.toCharArray()) {
            if (c == '\"') {
                inQuotes = !inQuotes;
            } else if (c == ',' && !inQuotes) {
                tokens.add(sb.toString());
                sb.setLength(0);
            } else {
                sb.append(c);
            }
        }
        tokens.add(sb.toString());
        return tokens.toArray(new String[0]);
    }

    private Date parseDate(String str) {
        if (str == null || str.trim().isEmpty()) {
            return new Date();
        }
        str = str.trim().replaceAll("^`+|`+$", "").trim();
        String[] formats = new String[]{"yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd"};
        for (String f : formats) {
            try {
                return new SimpleDateFormat(f).parse(str);
            } catch (ParseException ignored) {
            }
        }
        return new Date();
    }

    private String computeSha256(String text) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] hash = md.digest(text.getBytes(StandardCharsets.UTF_8));
            StringBuilder hexString = new StringBuilder();
            for (byte b : hash) {
                String hex = Integer.toHexString(0xff & b);
                if (hex.length() == 1) hexString.append('0');
                hexString.append(hex);
            }
            return hexString.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new RuntimeException("SHA-256 algorithm not available", e);
        }
    }

    private Shop resolveShop(Integer shopId) {
        Shop s = null;
        if (shopId != null) {
            s = shopService.getById(shopId);
        }
        if (s == null) {
            s = shopService.getOne(new QueryWrapper<Shop>().orderByAsc("id").last("LIMIT 1"));
        }
        if (s == null) {
            s = new Shop();
            s.setId(1);
            s.setName("默认门店");
            s.setSettle_time("04:00");
        }
        return s;
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

    private Date[] settlementWindow(Shop shop, String date, LocalDate settlementDay) {
        if (date == null || date.trim().isEmpty()) {
            return ShopBusinessWindowResolver.operationalWindow(shop);
        }
        return ShopBusinessWindowResolver.settlementWindowFor(shop, settlementDay);
    }

    private static class ParsedEntry {
        String channel;
        String channelTradeNo;
        String merchantOrderNo;
        String entryType;
        int amountFen;
        int feeFen;
        Date tradeTime;
        Long savedEntryId;
    }
}

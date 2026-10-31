package com.lanf.payment.admin;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.common.ApiException;
import com.lanf.payment.PaymentChannels;
import com.lanf.payment.entity.PaymentMerchantConfigEntity;
import com.lanf.payment.entity.PaymentTestTxnEntity;
import com.lanf.payment.mapper.PaymentMerchantConfigMapper;
import com.lanf.payment.mapper.PaymentTestTxnMapper;
import com.lanf.payment.support.PaymentChannelCatalog;
import com.lanf.payment.support.PaymentMerchantReadiness;
import com.lanf.util.StringUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 支付渠道运营扩展：停用影响判定 + 测试交易。
 * 渠道列表与启停由既有 GET/PUT /admin/payment/capabilities 承担（不在此重复）。
 *
 * 测试交易说明：既有支付链路（PaymentFacadeService.getPrepayId）依赖 C 端 openid 上下文，
 * 后端无法独立发起真实扣款。因此测试交易实现为「渠道就绪校验」：
 * - online_wechat：校验商户配置齐备性（PaymentMerchantReadiness）；
 * - 线下渠道（现金/收款码）：无资金动作，标记 OFFLINE_NO_MONEY_MOVEMENT；
 * - 未接入渠道：FAILED + 说明。全程不接触商户密钥，幂等键保证可重试。
 */
@Service
public class PaymentChannelOpsService {

    private static final Logger log = LoggerFactory.getLogger(PaymentChannelOpsService.class);

    public static final String ERROR_CHANNEL_UNKNOWN = "PAYMENT_CHANNEL_UNKNOWN";
    public static final String ERROR_IDEMPOTENCY_KEY_REQUIRED = "PAYMENT_IDEMPOTENCY_KEY_REQUIRED";
    public static final String ERROR_VALIDATION = "PAYMENT_VALIDATION_FAILED";

    private static final ZoneId ZONE = ZoneId.of("+08:00");
    private static final DateTimeFormatter ISO = DateTimeFormatter.ISO_OFFSET_DATE_TIME;

    private static final List<String> KNOWN_CHANNELS = Arrays.asList(
            PaymentChannelCatalog.CASH, PaymentChannelCatalog.ONLINE_WECHAT,
            PaymentChannelCatalog.ONLINE_ALIPAY, PaymentChannelCatalog.ONLINE_BALANCE,
            PaymentChannelCatalog.ONLINE_COMBINED, PaymentChannelCatalog.OFFLINE_WECHAT_QR,
            PaymentChannelCatalog.OFFLINE_ALIPAY_QR);

    @Autowired
    private PaymentTestTxnMapper testTxnMapper;
    @Autowired
    private PaymentMerchantConfigMapper merchantConfigMapper;
    @Autowired
    private JdbcTemplate jdbcTemplate;

    // ---------------- 停用影响判定 ----------------

    /**
     * 停用渠道的影响范围：未完成交易数 + 受影响入口（静态映射）。
     * 不返回商户号/密钥/证书等任何敏感信息。
     */
    public Map<String, Object> impact(int shopId, String channelCode, String targetStatus) {
        String code = normalizeChannel(channelCode);
        if (!"disabled".equalsIgnoreCase(targetStatus) && !"enabled".equalsIgnoreCase(targetStatus)) {
            throw new ApiException(400, ERROR_VALIDATION, "targetStatus 仅支持 enabled/disabled");
        }
        String methodName = PaymentChannelCatalog.normalizePaymentMethod(code);
        int pending = countPendingTransactions(shopId, methodName);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("channelCode", code);
        out.put("targetStatus", targetStatus);
        out.put("pendingTxCount", pending);
        out.put("affectedEntries", affectedEntries(code));
        out.put("blocking", "disabled".equalsIgnoreCase(targetStatus) && pending > 0);
        return out;
    }

    private List<String> affectedEntries(String code) {
        List<String> entries = new ArrayList<>();
        switch (code) {
            case PaymentChannelCatalog.ONLINE_WECHAT:
            case PaymentChannelCatalog.ONLINE_ALIPAY:
            case PaymentChannelCatalog.ONLINE_BALANCE:
            case PaymentChannelCatalog.ONLINE_COMBINED:
                entries.add("小程序扫码下单");
                entries.add("在线支付收银");
                break;
            case PaymentChannelCatalog.OFFLINE_WECHAT_QR:
            case PaymentChannelCatalog.OFFLINE_ALIPAY_QR:
                entries.add("线下收款码");
                break;
            default:
                entries.add("收银台现金记账");
        }
        return entries;
    }

    private int countPendingTransactions(int shopId, String methodName) {
        try {
            Integer count = jdbcTemplate.queryForObject(
                    "SELECT COUNT(*) FROM t_order WHERE shop_id=? AND payment_method=? AND transac_status='unsettled'",
                    Integer.class, shopId, methodName);
            return count != null ? count : 0;
        } catch (Exception e) {
            log.warn("[payment-ops] pending 统计失败，按 0 处理: {}", e.getMessage());
            return 0;
        }
    }

    // ---------------- 测试交易 ----------------

    /**
     * 幂等测试交易：同 (shop_id, idempotency_key) 重复请求返回首次记录。
     */
    public Map<String, Object> testTransaction(int shopId, String channelCode, BigDecimal amount,
                                               String terminal, String idempotencyKey, Integer adminId) {
        String code = normalizeChannel(channelCode);
        if (StringUtil.isEmpty(idempotencyKey)) {
            throw new ApiException(400, ERROR_IDEMPOTENCY_KEY_REQUIRED, "idempotencyKey 必填");
        }
        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new ApiException(400, ERROR_VALIDATION, "amount 必须为正数");
        }

        PaymentTestTxnEntity existing = findByIdemKey(shopId, idempotencyKey);
        if (existing != null) {
            Map<String, Object> dup = toView(existing);
            dup.put("duplicate", true);
            return dup;
        }

        PaymentTestTxnEntity txn = new PaymentTestTxnEntity();
        txn.setShop_id(shopId);
        txn.setChannel_code(code);
        txn.setAmount(amount);
        txn.setTerminal(terminal);
        txn.setIdempotency_key(idempotencyKey);
        txn.setCreated_by(adminId);
        txn.setCreated_at(LocalDateTime.now(ZONE));
        txn.setUpdated_at(LocalDateTime.now(ZONE));

        applyChannelTest(txn, shopId, code);
        try {
            testTxnMapper.insert(txn);
        } catch (DuplicateKeyException race) {
            // 并发下同幂等键撞库：返回已存在记录
            PaymentTestTxnEntity raced = findByIdemKey(shopId, idempotencyKey);
            if (raced != null) {
                Map<String, Object> dup = toView(raced);
                dup.put("duplicate", true);
                return dup;
            }
            throw race;
        }
        log.info("[payment-ops] test txn: shop_id={}, channel={}, status={}, by={}",
                shopId, code, txn.getStatus(), adminId);
        return toView(txn);
    }

    private void applyChannelTest(PaymentTestTxnEntity txn, int shopId, String code) {
        if (PaymentChannelCatalog.ONLINE_WECHAT.equals(code)) {
            List<PaymentMerchantConfigEntity> rows = merchantConfigMapper.selectList(
                    new QueryWrapper<PaymentMerchantConfigEntity>()
                            .eq("shop_id", shopId).eq("channel", PaymentChannels.WECHAT).eq("enabled", 1));
            if (rows.isEmpty()) {
                txn.setStatus("FAILED");
                txn.setCharge_status("FAILED");
                txn.setError("门店未配置或未启用微信支付商户号");
                return;
            }
            List<String> missing = PaymentMerchantReadiness.missingFields(rows.get(0));
            if (!missing.isEmpty()) {
                txn.setStatus("FAILED");
                txn.setCharge_status("FAILED");
                txn.setError("商户配置不齐，缺失: " + String.join(",", missing));
                return;
            }
            txn.setStatus("DONE");
            txn.setCharge_status("READINESS_OK");
            txn.setRefund_status("NOT_REQUIRED");
            return;
        }
        if (PaymentChannelCatalog.ONLINE_ALIPAY.equals(code)) {
            List<PaymentMerchantConfigEntity> rows = merchantConfigMapper.selectList(
                    new QueryWrapper<PaymentMerchantConfigEntity>()
                            .eq("shop_id", shopId).eq("channel", PaymentChannels.ALIPAY).eq("enabled", 1));
            txn.setStatus(rows.isEmpty() ? "FAILED" : "DONE");
            txn.setCharge_status(rows.isEmpty() ? "FAILED" : "READINESS_OK");
            if (rows.isEmpty()) {
                txn.setError("门店未配置或未启用支付宝商户号");
            } else {
                txn.setRefund_status("NOT_REQUIRED");
            }
            return;
        }
        // 现金/线下收款码/余额：无资金动作的就绪确认
        txn.setStatus("DONE");
        txn.setCharge_status("OFFLINE_NO_MONEY_MOVEMENT");
        txn.setRefund_status("NOT_REQUIRED");
    }

    private PaymentTestTxnEntity findByIdemKey(int shopId, String key) {
        List<PaymentTestTxnEntity> rows = testTxnMapper.selectList(new QueryWrapper<PaymentTestTxnEntity>()
                .eq("shop_id", shopId).eq("idempotency_key", key));
        return rows.isEmpty() ? null : rows.get(0);
    }

    private String normalizeChannel(String channelCode) {
        if (StringUtil.isEmpty(channelCode)) {
            throw new ApiException(400, ERROR_VALIDATION, "channel code 不能为空");
        }
        String code = channelCode.trim().toLowerCase();
        if (!KNOWN_CHANNELS.contains(code)) {
            throw new ApiException(404, ERROR_CHANNEL_UNKNOWN, "未知支付渠道: " + channelCode);
        }
        return code;
    }

    private Map<String, Object> toView(PaymentTestTxnEntity txn) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("paymentId", txn.getId());
        m.put("channelCode", txn.getChannel_code());
        m.put("amount", txn.getAmount());
        m.put("terminal", txn.getTerminal());
        m.put("status", txn.getStatus());
        m.put("chargeStatus", txn.getCharge_status());
        m.put("refundStatus", txn.getRefund_status());
        m.put("error", txn.getError());
        m.put("createdAt", txn.getCreated_at() == null ? null : txn.getCreated_at().atZone(ZONE).format(ISO));
        m.put("duplicate", false);
        return m;
    }
}

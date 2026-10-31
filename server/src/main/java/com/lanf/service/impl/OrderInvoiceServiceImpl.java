package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderInvoice;
import com.lanf.entity.Shop;
import com.lanf.entity.R;
import com.lanf.mapper.OrderInvoiceMapper;
import com.lanf.payment.channel.wechat.WechatMerchantKeyStore;
import com.lanf.payment.channel.wechat.WechatPayV3Crypto;
import com.lanf.service.IOrderInvoiceService;
import com.lanf.util.OrderNetRevenue;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestTemplate;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

@Slf4j
@Service
public class OrderInvoiceServiceImpl extends ServiceImpl<OrderInvoiceMapper, OrderInvoice>
        implements IOrderInvoiceService {

    @Autowired(required = false)
    private WechatMerchantKeyStore merchantKeyStore;

    @Autowired
    private RestTemplate restTemplate;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired(required = false)
    private com.lanf.service.IOrderService orderService;

    @Autowired(required = false)
    private com.lanf.service.IShopService shopService;

    @Override
    public R createInvoiceQrcode(Order order, Double invoiceAmountReq, Double taxRateReq, Integer operatorId) {
        if (order == null || !StringUtils.hasText(order.getOrder_no())) {
            return R.error(400, "订单不存在或订单号为空");
        }

        String orderNo = order.getOrder_no().trim();
        Integer shopId = order.getShop_id() != null ? order.getShop_id() : 1;

        // 1. 支付状态前置校验：仅已支付订单允许申请或开具发票
        boolean isPaid = ("success".equalsIgnoreCase(order.getTransac_status()) || "settled".equalsIgnoreCase(order.getTransac_status()))
                && order.getPay_time() != null;
        if (!isPaid) {
            return R.error(400, "未支付订单不可开具发票");
        }

        // 2. 严格计算可开票金额（扣除已退款及赠送金）
        double maxInvoiceable = OrderNetRevenue.netRevenueYuan(order);
        if (maxInvoiceable <= 0 && order.getSett_amount() != null) {
            maxInvoiceable = order.getSett_amount();
        }
        if (maxInvoiceable <= 0) {
            return R.error(400, "订单有效可开票金额不足或已全额退款");
        }

        // 3. 累计有效发票金额检查（排除已冲红或作废，统计 TITLE_SUBMITTED, ISSUING, SUCCESS）
        List<OrderInvoice> activeInvoices = list(new QueryWrapper<OrderInvoice>()
                .eq("order_no", orderNo)
                .in("invoice_status", Arrays.asList(
                        OrderInvoice.STATUS_TITLE_SUBMITTED,
                        OrderInvoice.STATUS_ISSUING,
                        OrderInvoice.STATUS_SUCCESS
                )));
        double usedAmount = 0.0;
        if (activeInvoices != null && !activeInvoices.isEmpty()) {
            for (OrderInvoice ai : activeInvoices) {
                if (ai.getInvoice_amount() != null) {
                    usedAmount += ai.getInvoice_amount().doubleValue();
                }
            }
        }

        double remainingAmount = Math.max(0.0, maxInvoiceable - usedAmount);
        if (remainingAmount <= 0.001) {
            return R.error(400, "该订单已足额开具或申请发票，无可开票余额");
        }

        double finalInvoiceAmount = (invoiceAmountReq != null && invoiceAmountReq > 0)
                ? invoiceAmountReq : remainingAmount;
        if (finalInvoiceAmount > remainingAmount + 0.001) {
            return R.error(400, "开票金额超出剩余可开票金额: " + String.format("%.2f", remainingAmount));
        }

        BigDecimal amountBd = BigDecimal.valueOf(finalInvoiceAmount).setScale(2, RoundingMode.HALF_UP);
        BigDecimal taxRateBd = BigDecimal.valueOf(taxRateReq != null ? taxRateReq : 0.06).setScale(4, RoundingMode.HALF_UP);

        // 4. 生成发票申请单号与安全令牌（单号商户下唯一，令牌使用高熵 UUID 且存储 SHA-256 哈希）
        String fapiaoApplyId = "INV" + System.currentTimeMillis() + (int) (Math.random() * 900 + 100);
        String token = "inv_" + UUID.randomUUID().toString().replace("-", "");
        String tokenHash = sha256Hex(token);
        Date tokenExpireAt = new Date(System.currentTimeMillis() + 86400000L); // 24小时有效

        // 普通商户安全闭环方案：使用受控的门店登记页面，杜绝调用微信服务商专属抬头收集接口
        String qrUrl = "https://www.laofei.com.cn/invoice/apply.html?orderNo=" + orderNo + "&applyId=" + fapiaoApplyId + "&token=" + token;
        String notice = "顾客微信扫码后可自主填写企业或个人抬头开具增值税电子发票";

        // 5. 持久化存储开票申请记录
        OrderInvoice invoice = OrderInvoice.builder()
                .order_no(orderNo)
                .shop_id(shopId)
                .fapiao_apply_id(fapiaoApplyId)
                .invoice_status(OrderInvoice.STATUS_PENDING_SCAN)
                .invoice_amount(amountBd)
                .tax_rate(taxRateBd)
                .invoice_qr_url(qrUrl)
                .token_hash(tokenHash)
                .token_expire_at(tokenExpireAt)
                .operator_id(operatorId)
                .error_msg(null)
                .created_at(new Date())
                .updated_at(new Date())
                .build();

        // 检查是否已有待扫码记录，更新或新建
        OrderInvoice exist = getOne(new QueryWrapper<OrderInvoice>()
                .eq("order_no", orderNo)
                .eq("invoice_status", OrderInvoice.STATUS_PENDING_SCAN)
                .last("LIMIT 1"));
        if (exist != null) {
            invoice.setId(exist.getId());
            updateById(invoice);
        } else {
            save(invoice);
        }

        // 6. 构造返回契约
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("orderNo", orderNo);
        data.put("fapiaoApplyId", fapiaoApplyId);
        data.put("invoiceStatus", OrderInvoice.STATUS_PENDING_SCAN);
        data.put("invoiceQrUrl", qrUrl);
        data.put("invoiceAmount", amountBd.doubleValue());
        data.put("taxRate", taxRateBd.doubleValue());
        data.put("expireMinutes", 1440);
        data.put("notice", notice);

        return R.ok("success").put("code", 200).put("data", data);
    }

    @Override
    public R getInvoiceStatus(Order order) {
        if (order == null || !StringUtils.hasText(order.getOrder_no())) {
            return R.error(400, "订单不存在");
        }

        String orderNo = order.getOrder_no().trim();
        List<OrderInvoice> list = list(new QueryWrapper<OrderInvoice>()
                .eq("order_no", orderNo)
                .orderByDesc("id"));

        if (list == null || list.isEmpty()) {
            Map<String, Object> data = new LinkedHashMap<>();
            data.put("orderNo", orderNo);
            data.put("hasInvoice", false);
            data.put("invoiceStatus", "NONE");
            return R.ok("success").put("code", 200).put("data", data);
        }

        OrderInvoice latest = list.get(0);
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("orderNo", orderNo);
        data.put("hasInvoice", true);
        data.put("fapiaoApplyId", latest.getFapiao_apply_id());
        data.put("invoiceStatus", latest.getInvoice_status());
        data.put("invoiceAmount", latest.getInvoice_amount() != null ? latest.getInvoice_amount().doubleValue() : 0.0);
        data.put("taxRate", latest.getTax_rate() != null ? latest.getTax_rate().doubleValue() : 0.06);
        data.put("titleType", StringUtils.hasText(latest.getBuyer_tax_no()) ? "COMPANY" : "PERSONAL");
        data.put("buyerTitle", latest.getBuyer_title());
        data.put("buyerTaxNo", latest.getBuyer_tax_no());
        data.put("buyerPhone", latest.getBuyer_phone());
        data.put("buyerEmail", latest.getBuyer_email());
        data.put("fapiaoNumber", latest.getFapiao_number());
        data.put("invoiceNo", latest.getFapiao_number());
        data.put("fapiaoCode", latest.getFapiao_code());
        data.put("invoiceCode", latest.getFapiao_code());
        data.put("fapiaoFileUrl", sanitizeFileUrl(latest.getFapiao_file_url()));
        data.put("downloadUrl", sanitizeFileUrl(latest.getFapiao_file_url()));
        data.put("invoiceQrUrl", latest.getInvoice_qr_url());
        data.put("failReason", latest.getError_msg());
        data.put("errorMsg", latest.getError_msg());
        data.put("createdAt", latest.getCreated_at());

        return R.ok("success").put("code", 200).put("data", data);
    }

    @Override
    public R getInvoiceInfoForPublic(String orderNo, String applyId, String token) {
        if (!StringUtils.hasText(orderNo)) {
            return R.error(400, "订单号不能为空");
        }
        if (!StringUtils.hasText(token)) {
            return R.error(401, "缺少安全令牌或令牌已失效");
        }

        String rawOrderKey = orderNo.trim();
        QueryWrapper<OrderInvoice> qw = new QueryWrapper<OrderInvoice>().eq("order_no", rawOrderKey);
        if (StringUtils.hasText(applyId)) {
            qw.eq("fapiao_apply_id", applyId.trim());
        }
        qw.orderByDesc("id").last("LIMIT 1");

        OrderInvoice invoice = getOne(qw);
        if (invoice == null) {
            return R.error(404, "未找到对应的开票记录");
        }

        // 校验安全令牌哈希与时效
        String incomingHash = sha256Hex(token.trim());
        if (invoice.getToken_hash() == null || !MessageDigest.isEqual(
                incomingHash.getBytes(StandardCharsets.UTF_8),
                invoice.getToken_hash().getBytes(StandardCharsets.UTF_8))) {
            return R.error(403, "开票令牌无效或已被重置");
        }
        if (invoice.getToken_expire_at() != null && invoice.getToken_expire_at().before(new Date())) {
            return R.error(403, "开票申请已过期，请联系收银员重新生成二维码");
        }

        Map<String, Object> data = new LinkedHashMap<>();
        data.put("orderNo", invoice.getOrder_no());
        data.put("applyId", invoice.getFapiao_apply_id());
        data.put("invoiceStatus", invoice.getInvoice_status());
        data.put("invoiceAmount", invoice.getInvoice_amount() != null ? invoice.getInvoice_amount().doubleValue() : 0.0);
        data.put("taxRate", invoice.getTax_rate() != null ? invoice.getTax_rate().doubleValue() : 0.06);
        data.put("buyerTitle", invoice.getBuyer_title());
        data.put("buyerTaxNo", maskTaxNo(invoice.getBuyer_tax_no()));
        data.put("buyerEmail", maskEmail(invoice.getBuyer_email()));
        data.put("buyerPhone", maskPhone(invoice.getBuyer_phone()));
        data.put("fapiaoNumber", invoice.getFapiao_number());
        data.put("fapiaoCode", invoice.getFapiao_code());
        data.put("fapiaoFileUrl", sanitizeFileUrl(invoice.getFapiao_file_url()));
        if (OrderInvoice.STATUS_REJECTED.equalsIgnoreCase(invoice.getInvoice_status())) {
            data.put("rejectReason", invoice.getError_msg());
        }

        return R.ok("success").put("code", 200).put("data", data);
    }

    @Override
    public R submitInvoiceTitleFromCustomer(String orderNo, String applyId, String token,
                                             String titleType, String buyerTitle, String buyerTaxNo,
                                             String buyerEmail, String buyerPhone) {
        if (!StringUtils.hasText(orderNo)) {
            return R.error(400, "订单号不能为空");
        }
        if (!StringUtils.hasText(token)) {
            return R.error(401, "缺少安全令牌或令牌已失效");
        }
        if (!StringUtils.hasText(buyerTitle)) {
            return R.error(400, "发票抬头名称不能为空");
        }
        if (buyerTitle.trim().length() > 100) {
            return R.error(400, "发票抬头名称过长");
        }

        // 清洗邮箱（全角字符转半角、去空格、转小写）
        String cleanEmail = null;
        if (StringUtils.hasText(buyerEmail)) {
            cleanEmail = buyerEmail.trim()
                    .replace(" ", "")
                    .replace("＠", "@")
                    .replace("。", ".")
                    .toLowerCase();
        }

        // 清洗手机号（去空格、短横线）
        String cleanPhone = null;
        if (StringUtils.hasText(buyerPhone)) {
            cleanPhone = buyerPhone.trim().replace(" ", "").replace("-", "");
        }

        // 联系方式有效性校验：邮箱与手机号至少提供一项有效联系方式
        boolean emailValid = StringUtils.hasText(cleanEmail) && cleanEmail.matches("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$");
        boolean phoneValid = StringUtils.hasText(cleanPhone) && cleanPhone.matches("^1[3-9]\\d{9}$");

        if (!emailValid && !phoneValid) {
            if (StringUtils.hasText(cleanEmail) && !emailValid) {
                return R.error(400, "电子邮箱格式不正确，请仔细核对（例如 user@example.com）或填写手机号码");
            }
            return R.error(400, "请提供有效的电子邮箱或11位手机号码，以便接收发票交付通知");
        }

        // 清洗税号（企业必填，去除空格短横线后大写，15-20位）
        String cleanTaxNo = null;
        if ("COMPANY".equalsIgnoreCase(titleType)) {
            if (!StringUtils.hasText(buyerTaxNo)) {
                return R.error(400, "企业抬头必须提供统一社会信用代码/纳税人识别号");
            }
            cleanTaxNo = buyerTaxNo.trim().replace(" ", "").replace("-", "").toUpperCase();
            if (!cleanTaxNo.matches("^[0-9A-Z]{15,20}$")) {
                return R.error(400, "纳税人识别号格式不正确（须为15-20位大写字母或数字）");
            }
        }

        String rawOrderKey = orderNo.trim();
        QueryWrapper<OrderInvoice> qw = new QueryWrapper<OrderInvoice>().eq("order_no", rawOrderKey);
        if (StringUtils.hasText(applyId)) {
            qw.eq("fapiao_apply_id", applyId.trim());
        }
        qw.orderByDesc("id").last("LIMIT 1");

        OrderInvoice invoice = getOne(qw);
        if (invoice == null) {
            return R.error(404, "未找到对应的开票记录");
        }

        // 校验安全令牌哈希与时效
        String incomingHash = sha256Hex(token.trim());
        if (invoice.getToken_hash() == null || !MessageDigest.isEqual(
                incomingHash.getBytes(StandardCharsets.UTF_8),
                invoice.getToken_hash().getBytes(StandardCharsets.UTF_8))) {
            return R.error(403, "开票令牌无效或已被重置");
        }
        if (invoice.getToken_expire_at() != null && invoice.getToken_expire_at().before(new Date())) {
            return R.error(403, "开票申请已过期，请联系收银员重新生成二维码");
        }

        if (OrderInvoice.STATUS_SUCCESS.equalsIgnoreCase(invoice.getInvoice_status())) {
            return R.error(400, "发票已开具完成，不可重复修改抬头");
        }

        invoice.setBuyer_title(buyerTitle.trim());
        invoice.setBuyer_tax_no(cleanTaxNo);
        if (StringUtils.hasText(cleanEmail)) {
            invoice.setBuyer_email(cleanEmail);
        }
        if (StringUtils.hasText(cleanPhone)) {
            invoice.setBuyer_phone(cleanPhone);
        }
        invoice.setInvoice_status(OrderInvoice.STATUS_TITLE_SUBMITTED);
        invoice.setError_msg(null); // 清除历史可能的驳回原因
        invoice.setToken_used_at(new Date());
        invoice.setUpdated_at(new Date());

        updateById(invoice);

        // 脱敏日志输出，防止敏感隐私信息泄露
        log.info("[invoice] customer submitted title successfully: orderNo={}, title={}, taxNo={}, email={}, phone={}",
                invoice.getOrder_no(), buyerTitle.trim(), maskTaxNo(cleanTaxNo), maskEmail(cleanEmail), maskPhone(cleanPhone));

        return R.ok("发票抬头提交成功").put("code", 200);
    }

    @Override
    public R issueInvoice(String orderNo, String fapiaoNumber, String fapiaoCode, String fapiaoFileUrl, Integer operatorId) {
        if (!StringUtils.hasText(orderNo)) {
            return R.error(400, "订单号不能为空");
        }
        if (!StringUtils.hasText(fapiaoNumber)) {
            return R.error(400, "发票号码不能为空");
        }

        OrderInvoice invoice = getOne(new QueryWrapper<OrderInvoice>()
                .eq("order_no", orderNo.trim())
                .orderByDesc("id")
                .last("LIMIT 1"));

        if (invoice == null) {
            return R.error(404, "开票记录不存在");
        }

        if (OrderInvoice.STATUS_SUCCESS.equalsIgnoreCase(invoice.getInvoice_status())) {
            return R.error(400, "发票已开具完成，不可重复开具");
        }
        if (OrderInvoice.STATUS_PENDING_SCAN.equalsIgnoreCase(invoice.getInvoice_status())) {
            return R.error(400, "顾客尚未提交发票抬头，无法开具发票");
        }
        if (OrderInvoice.STATUS_REJECTED.equalsIgnoreCase(invoice.getInvoice_status())) {
            return R.error(400, "开票申请已被驳回，需等待顾客修改重提后再开具");
        }

        invoice.setFapiao_number(fapiaoNumber.trim());
        if (StringUtils.hasText(fapiaoCode)) {
            invoice.setFapiao_code(fapiaoCode.trim());
        }
        if (StringUtils.hasText(fapiaoFileUrl)) {
            invoice.setFapiao_file_url(sanitizeFileUrl(fapiaoFileUrl.trim()));
        } else {
            invoice.setFapiao_file_url(null);
        }
        invoice.setInvoice_status(OrderInvoice.STATUS_SUCCESS);
        invoice.setError_msg(null);
        if (operatorId != null) {
            invoice.setOperator_id(operatorId);
        }
        invoice.setUpdated_at(new Date());

        // 执行插卡逻辑并写入发票实体
        doInsertWechatCard(invoice);

        updateById(invoice);

        log.info("[invoice] invoice issued successfully: orderNo={}, number={}, code={}, cardStatus={}",
                orderNo, fapiaoNumber, fapiaoCode, invoice.getCard_insert_status());

        return R.ok("发票开具成功")
                .put("code", 200)
                .put("cardStatus", invoice.getCard_insert_status())
                .put("cardMsg", invoice.getCard_insert_msg());
    }

    @Override
    public R rejectInvoice(String orderNo, String rejectReason, Integer operatorId) {
        if (!StringUtils.hasText(orderNo)) {
            return R.error(400, "订单号不能为空");
        }
        if (!StringUtils.hasText(rejectReason)) {
            return R.error(400, "驳回原因不能为空");
        }

        OrderInvoice invoice = getOne(new QueryWrapper<OrderInvoice>()
                .eq("order_no", orderNo.trim())
                .orderByDesc("id")
                .last("LIMIT 1"));

        if (invoice == null) {
            return R.error(404, "开票记录不存在");
        }

        if (OrderInvoice.STATUS_SUCCESS.equalsIgnoreCase(invoice.getInvoice_status())) {
            return R.error(400, "发票已开具完成，不可驳回");
        }
        if (OrderInvoice.STATUS_PENDING_SCAN.equalsIgnoreCase(invoice.getInvoice_status())) {
            return R.error(400, "顾客尚未提交发票抬头，无需驳回");
        }

        invoice.setInvoice_status(OrderInvoice.STATUS_REJECTED);
        invoice.setError_msg(rejectReason.trim());
        if (operatorId != null) {
            invoice.setOperator_id(operatorId);
        }
        invoice.setUpdated_at(new Date());

        updateById(invoice);

        log.info("[invoice] invoice rejected: orderNo={}, reason={}, operatorId={}",
                orderNo, rejectReason, operatorId);

        return R.ok("开票申请已驳回").put("code", 200);
    }

    @Override
    public R pageInvoiceForAdmin(Integer page, Integer limit, String status, String keyword, String startDate, String endDate, Integer shopId) {
        int curPage = (page != null && page > 0) ? page : 1;
        int pageSize = (limit != null && limit > 0) ? limit : 10;

        QueryWrapper<OrderInvoice> qw = new QueryWrapper<>();
        if (shopId != null) {
            qw.eq("shop_id", shopId);
        }
        if (StringUtils.hasText(status)) {
            qw.eq("invoice_status", status.trim().toUpperCase());
        }
        if (StringUtils.hasText(keyword)) {
            String kw = keyword.trim();
            qw.and(wrapper -> wrapper.like("order_no", kw)
                    .or().like("buyer_title", kw)
                    .or().like("buyer_phone", kw)
                    .or().like("fapiao_number", kw));
        }
        if (StringUtils.hasText(startDate)) {
            qw.ge("created_at", startDate.trim());
        }
        if (StringUtils.hasText(endDate)) {
            qw.le("created_at", endDate.trim());
        }
        qw.orderByDesc("id");

        com.baomidou.mybatisplus.extension.plugins.pagination.Page<OrderInvoice> mpPage =
                new com.baomidou.mybatisplus.extension.plugins.pagination.Page<>(curPage, pageSize);
        page(mpPage, qw);

        // 指标统计
        long countWaiting = count(new QueryWrapper<OrderInvoice>()
                .eq(shopId != null, "shop_id", shopId)
                .eq("invoice_status", OrderInvoice.STATUS_TITLE_SUBMITTED));
        long countSuccess = count(new QueryWrapper<OrderInvoice>()
                .eq(shopId != null, "shop_id", shopId)
                .eq("invoice_status", OrderInvoice.STATUS_SUCCESS));
        long countRejected = count(new QueryWrapper<OrderInvoice>()
                .eq(shopId != null, "shop_id", shopId)
                .eq("invoice_status", OrderInvoice.STATUS_REJECTED));
        long countPendingScan = count(new QueryWrapper<OrderInvoice>()
                .eq(shopId != null, "shop_id", shopId)
                .eq("invoice_status", OrderInvoice.STATUS_PENDING_SCAN));

        Map<String, Object> metrics = new LinkedHashMap<>();
        metrics.put("countWaiting", countWaiting);
        metrics.put("countSuccess", countSuccess);
        metrics.put("countRejected", countRejected);
        metrics.put("countPendingScan", countPendingScan);

        if (shopService != null && mpPage.getRecords() != null && !mpPage.getRecords().isEmpty()) {
            java.util.Set<Integer> sids = mpPage.getRecords().stream()
                    .map(OrderInvoice::getShop_id)
                    .filter(java.util.Objects::nonNull)
                    .collect(java.util.stream.Collectors.toSet());
            if (!sids.isEmpty()) {
                try {
                    java.util.List<Shop> shops = shopService.listByIds(sids);
                    if (shops != null) {
                        java.util.Map<Integer, Shop> shopMap = shops.stream()
                                .collect(java.util.stream.Collectors.toMap(Shop::getId, s -> s, (k1, k2) -> k1));
                        for (OrderInvoice inv : mpPage.getRecords()) {
                            if (inv.getShop_id() != null && shopMap.containsKey(inv.getShop_id())) {
                                Shop s = shopMap.get(inv.getShop_id());
                                inv.setShop_name(s.getName());
                                inv.setShop_code(s.getCode());
                                inv.setShop_address(s.getAddress());
                                com.lanf.util.TaxBureauResolver.TaxBureauInfo taxInfo =
                                        com.lanf.util.TaxBureauResolver.resolve(s.getAddress());
                                inv.setTax_bureau_name(taxInfo.getName());
                                inv.setTax_bureau_url(taxInfo.getUrl());
                            } else {
                                com.lanf.util.TaxBureauResolver.TaxBureauInfo taxInfo =
                                        com.lanf.util.TaxBureauResolver.getDefaultTaxBureau();
                                inv.setTax_bureau_name(taxInfo.getName());
                                inv.setTax_bureau_url(taxInfo.getUrl());
                            }
                        }
                    }
                } catch (Exception e) {
                    log.warn("[invoice] enrich shop tax entity info failed: {}", e.getMessage());
                }
            }
        }

        Map<String, Object> data = new LinkedHashMap<>();
        data.put("total", mpPage.getTotal());
        data.put("page", curPage);
        data.put("limit", pageSize);
        data.put("list", mpPage.getRecords());
        data.put("metrics", metrics);

        return R.ok("success").put("code", 200).put("data", data);
    }

    private void doInsertWechatCard(OrderInvoice invoice) {
        Integer shopId = invoice.getShop_id();
        if (shopId == null && orderService != null && StringUtils.hasText(invoice.getOrder_no())) {
            Order order = orderService.getOne(new QueryWrapper<Order>().eq("order_no", invoice.getOrder_no().trim()));
            if (order != null) {
                shopId = order.getShop_id();
            }
        }

        WechatMerchantKeyStore.ResolvedMerchant m = null;
        if (merchantKeyStore != null) {
            try {
                m = merchantKeyStore.resolveForPay(shopId, null, null);
            } catch (Exception e) {
                log.warn("[invoice] resolve merchant keystore failed for shopId={}: {}", shopId, e.getMessage());
            }
        }

        if (m == null || m.privateKey == null || !StringUtils.hasText(m.mchId) || !StringUtils.hasText(m.serialNo)) {
            String warnMsg = "微信支付商户私钥凭据未就绪，卡包插卡已跳过并标记待处理";
            log.warn("[invoice] {} for orderNo={}, shopId={}", warnMsg, invoice.getOrder_no(), shopId);
            invoice.setCard_insert_status(OrderInvoice.CARD_STATUS_FAILED);
            invoice.setCard_insert_msg(warnMsg);
            return;
        }

        String applyId = StringUtils.hasText(invoice.getFapiao_apply_id()) ? invoice.getFapiao_apply_id() : invoice.getOrder_no();
        String urlPath = "/v3/new-tax-control-fapiao/fapiao-applications/" + applyId + "/insert-cards";
        String fullUrl = "https://api.mch.weixin.qq.com" + urlPath;

        Map<String, Object> reqBody = new LinkedHashMap<>();
        reqBody.put("scene", "WITH_WECHATPAY");

        Map<String, Object> buyerInfo = new LinkedHashMap<>();
        buyerInfo.put("type", StringUtils.hasText(invoice.getBuyer_tax_no()) ? "ORGANIZATION" : "INDIVIDUAL");
        buyerInfo.put("name", StringUtils.hasText(invoice.getBuyer_title()) ? invoice.getBuyer_title() : "顾客");
        reqBody.put("buyer_information", buyerInfo);

        Map<String, Object> fapiaoItem = new LinkedHashMap<>();
        fapiaoItem.put("fapiao_number", invoice.getFapiao_number());
        if (StringUtils.hasText(invoice.getFapiao_code())) {
            fapiaoItem.put("fapiao_code", invoice.getFapiao_code());
        }
        if (StringUtils.hasText(invoice.getFapiao_media_id())) {
            fapiaoItem.put("fapiao_media_id", invoice.getFapiao_media_id());
        }
        if (invoice.getInvoice_amount() != null) {
            long amountFen = invoice.getInvoice_amount().multiply(BigDecimal.valueOf(100)).setScale(0, RoundingMode.HALF_UP).longValue();
            fapiaoItem.put("fapiao_amount", amountFen);
        }
        reqBody.put("fapiao_information", Collections.singletonList(fapiaoItem));

        try {
            String nonceStr = WechatPayV3Crypto.generateNonceStr();
            String timestamp = String.valueOf(System.currentTimeMillis() / 1000);
            String bodyJson = objectMapper != null ? objectMapper.writeValueAsString(reqBody) : "";

            String signature = WechatPayV3Crypto.signApiRequest("POST", urlPath, timestamp, nonceStr, bodyJson, m.privateKey);

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("Accept", "application/json");
            headers.set("Authorization", String.format(
                    "WECHATPAY2-SHA256-RSA2048 mchid=\"%s\",nonce_str=\"%s\",timestamp=\"%s\",signature=\"%s\",serial_no=\"%s\"",
                    m.mchId, nonceStr, timestamp, signature, m.serialNo));
            if (StringUtils.hasText(m.platformPubKeyId)) {
                headers.set("Wechatpay-Serial", m.platformPubKeyId);
            }

            HttpEntity<String> requestEntity = new HttpEntity<>(bodyJson, headers);
            if (restTemplate == null) {
                restTemplate = new RestTemplate();
            }

            ResponseEntity<String> response = restTemplate.exchange(fullUrl, HttpMethod.POST, requestEntity, String.class);

            if (response.getStatusCode().is2xxSuccessful()) {
                invoice.setCard_insert_status(OrderInvoice.CARD_STATUS_SUCCESS);
                invoice.setCard_insert_msg("已成功提交至微信卡包");
                invoice.setCard_inserted_at(new Date());
                log.info("[invoice] insert card success: orderNo={}, applyId={}", invoice.getOrder_no(), applyId);
            } else {
                String msg = "微信返回非200状态码: " + response.getStatusCodeValue();
                invoice.setCard_insert_status(OrderInvoice.CARD_STATUS_FAILED);
                invoice.setCard_insert_msg(msg);
            }
        } catch (org.springframework.web.client.HttpStatusCodeException e) {
            String errBody = e.getResponseBodyAsString();
            String errMsg = "微信卡包插卡失败: HTTP " + e.getRawStatusCode();
            if (StringUtils.hasText(errBody)) {
                errMsg += " (" + errBody + ")";
            }
            log.warn("[invoice] wechat insert card http error: orderNo={}, error={}", invoice.getOrder_no(), errMsg);
            invoice.setCard_insert_status(OrderInvoice.CARD_STATUS_FAILED);
            invoice.setCard_insert_msg(errMsg.length() > 500 ? errMsg.substring(0, 500) : errMsg);
        } catch (Exception e) {
            String errMsg = "插卡系统异常: " + (e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName());
            log.error("[invoice] wechat insert card exception: orderNo={}, error={}", invoice.getOrder_no(), errMsg, e);
            invoice.setCard_insert_status(OrderInvoice.CARD_STATUS_FAILED);
            invoice.setCard_insert_msg(errMsg.length() > 500 ? errMsg.substring(0, 500) : errMsg);
        }
    }

    @Override
    public R insertInvoiceToWechatCard(String orderNo, Integer operatorId) {
        if (!StringUtils.hasText(orderNo)) {
            return R.error(400, "订单号不能为空");
        }

        OrderInvoice invoice = getOne(new QueryWrapper<OrderInvoice>()
                .eq("order_no", orderNo.trim())
                .orderByDesc("id")
                .last("LIMIT 1"));

        if (invoice == null) {
            return R.error(404, "开票记录不存在");
        }

        if (!OrderInvoice.STATUS_SUCCESS.equalsIgnoreCase(invoice.getInvoice_status())) {
            return R.error(400, "发票尚未开具完成，不可插入微信卡包");
        }

        if (!StringUtils.hasText(invoice.getFapiao_number())) {
            return R.error(400, "发票号码为空，无法插卡");
        }

        doInsertWechatCard(invoice);
        invoice.setUpdated_at(new Date());
        updateById(invoice);

        if (OrderInvoice.CARD_STATUS_SUCCESS.equals(invoice.getCard_insert_status())) {
            return R.ok("已成功推送到微信卡包")
                    .put("code", 200)
                    .put("cardStatus", OrderInvoice.CARD_STATUS_SUCCESS)
                    .put("cardMsg", invoice.getCard_insert_msg());
        } else {
            return R.ok("发票已开具，但" + invoice.getCard_insert_msg())
                    .put("code", 200)
                    .put("cardStatus", OrderInvoice.CARD_STATUS_FAILED)
                    .put("cardMsg", invoice.getCard_insert_msg());
        }
    }

    @Override
    public R handleWechatInvoiceNotify(Map<String, String> headers, String requestBody) {
        log.info("[invoice] received wechat invoice notification: bodyLength={}",
                requestBody != null ? requestBody.length() : 0);
        if (!StringUtils.hasText(requestBody)) {
            return R.ok("SUCCESS");
        }
        try {
            if (objectMapper == null) {
                objectMapper = new ObjectMapper();
            }
            Map<String, Object> root = objectMapper.readValue(requestBody, Map.class);
            String eventType = (String) root.get("event_type");
            Map<String, Object> resource = (Map<String, Object>) root.get("resource");
            if (resource != null && merchantKeyStore != null) {
                String ciphertext = (String) resource.get("ciphertext");
                String associatedData = (String) resource.get("associated_data");
                String nonce = (String) resource.get("nonce");

                WechatMerchantKeyStore.ResolvedMerchant m = merchantKeyStore.resolveForPay(null, null, null);
                if (m != null && StringUtils.hasText(m.apiV3Key)) {
                    String plainText = WechatPayV3Crypto.decryptAesGcm(ciphertext, associatedData, nonce, m.apiV3Key);
                    Map<String, Object> plainMap = objectMapper.readValue(plainText, Map.class);
                    log.info("[invoice] decrypted notification: eventType={}, data={}", eventType, plainMap);

                    String applyId = (String) plainMap.get("fapiao_apply_id");
                    String cardId = (String) plainMap.get("card_id");
                    String cardCode = (String) plainMap.get("card_code");

                    if (StringUtils.hasText(applyId)) {
                        OrderInvoice invoice = getOne(new QueryWrapper<OrderInvoice>()
                                .eq("fapiao_apply_id", applyId)
                                .last("LIMIT 1"));
                        if (invoice != null) {
                            if (StringUtils.hasText(cardId)) invoice.setCard_id(cardId);
                            if (StringUtils.hasText(cardCode)) invoice.setCard_code(cardCode);
                            invoice.setCard_insert_status(OrderInvoice.CARD_STATUS_SUCCESS);
                            invoice.setCard_insert_msg("微信回调确认卡包插入成功");
                            invoice.setCard_inserted_at(new Date());
                            invoice.setUpdated_at(new Date());
                            updateById(invoice);
                        }
                    }
                }
            }
        } catch (Exception e) {
            log.warn("[invoice] parse wechat invoice notification exception: {}", e.getMessage());
        }
        return R.ok("SUCCESS");
    }

    // --- 安全工具与脱敏方法 ---

    public static String sha256Hex(String data) {
        if (data == null) {
            return null;
        }
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] hash = md.digest(data.getBytes(StandardCharsets.UTF_8));
            StringBuilder hexString = new StringBuilder();
            for (byte b : hash) {
                String hex = Integer.toHexString(0xff & b);
                if (hex.length() == 1) {
                    hexString.append('0');
                }
                hexString.append(hex);
            }
            return hexString.toString();
        } catch (Exception e) {
            throw new RuntimeException("SHA-256 calculation failed", e);
        }
    }

    public static String maskPhone(String phone) {
        if (!StringUtils.hasText(phone)) {
            return phone;
        }
        String p = phone.trim();
        if (p.length() == 11) {
            return p.substring(0, 3) + "****" + p.substring(7);
        }
        if (p.length() > 4) {
            return p.substring(0, 2) + "****" + p.substring(p.length() - 2);
        }
        return "****";
    }

    public static String maskTaxNo(String taxNo) {
        if (!StringUtils.hasText(taxNo)) {
            return taxNo;
        }
        String t = taxNo.trim();
        if (t.length() >= 15) {
            return t.substring(0, 4) + "********" + t.substring(t.length() - 4);
        }
        if (t.length() > 4) {
            return t.substring(0, 2) + "****" + t.substring(t.length() - 2);
        }
        return "****";
    }

    public static String maskEmail(String email) {
        if (!StringUtils.hasText(email)) {
            return email;
        }
        String e = email.trim();
        int atIndex = e.indexOf('@');
        if (atIndex <= 1) {
            return "*@" + (atIndex >= 0 ? e.substring(atIndex + 1) : "");
        }
        String prefix = e.substring(0, atIndex);
        String domain = e.substring(atIndex);
        if (prefix.length() <= 2) {
            return prefix.charAt(0) + "***" + domain;
        }
        return prefix.charAt(0) + "***" + prefix.charAt(prefix.length() - 1) + domain;
    }

    public static String sanitizeFileUrl(String url) {
        if (!StringUtils.hasText(url)) {
            return url;
        }
        String u = url.trim();
        if (u.startsWith("http://") || u.startsWith("https://") || u.startsWith("/")) {
            if (u.toLowerCase().contains("javascript:") || u.contains("<") || u.contains(">")) {
                return null;
            }
            return u;
        }
        return null;
    }
}

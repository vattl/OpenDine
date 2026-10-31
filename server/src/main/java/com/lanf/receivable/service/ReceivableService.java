package com.lanf.receivable.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.lanf.common.ApiException;
import com.lanf.entity.CashMovement;
import com.lanf.entity.Order;
import com.lanf.entity.Shop;
import com.lanf.payment.success.PaymentSuccessHandler;
import com.lanf.receivable.entity.ReceivableAccount;
import com.lanf.receivable.entity.ReceivableClaim;
import com.lanf.receivable.entity.ReceivableLedger;
import com.lanf.receivable.mapper.ReceivableAccountMapper;
import com.lanf.receivable.mapper.ReceivableClaimMapper;
import com.lanf.receivable.mapper.ReceivableLedgerMapper;
import com.lanf.receivable.model.ReceivableWindowSummary;
import com.lanf.service.DrawerSessionService;
import com.lanf.service.CashierCheckoutService;
import com.lanf.service.IOrderService;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IAdminShopAccessService;
import com.lanf.service.IShopService;
import com.lanf.util.AfterCommitExecutor;
import com.lanf.util.OrderNetRevenue;
import com.lanf.util.ShopBusinessWindowResolver;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.Set;

@Service
public class ReceivableService {
    public static final String PAYMENT_METHOD_RECEIVABLE = "挂账";
    private static final ZoneId BUSINESS_ZONE = ZoneId.of("Asia/Shanghai");

    @Autowired
    private ReceivableAccountMapper accountMapper;
    @Autowired
    private ReceivableClaimMapper claimMapper;
    @Autowired
    private ReceivableLedgerMapper ledgerMapper;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private PaymentSuccessHandler paymentSuccessHandler;
    @Autowired(required = false)
    private IShopService shopService;
    @Autowired(required = false)
    private IAdminPermissionService adminPermissionService;
    @Autowired(required = false)
    private IAdminShopAccessService adminShopAccessService;
    @Autowired(required = false)
    private DrawerSessionService drawerSessionService;
    @Autowired(required = false)
    private CashierCheckoutService cashierCheckoutService;

    private Clock clock = Clock.system(BUSINESS_ZONE);

    @Transactional(isolation = Isolation.READ_COMMITTED, rollbackFor = Exception.class)
    public ReceivableClaim charge(Integer shopId, Integer operatorId, String merchantId,
                                  String orderNo, Long accountId, String requestId, String note) {
        requireShop(shopId);
        merchantId = normalizeMerchant(merchantId);
        orderNo = required(orderNo, "订单号不能为空", 100);
        requestId = required(requestId, "requestId不能为空", 128);
        if (accountId == null || accountId <= 0) {
            throw invalid("挂账账户不能为空");
        }

        ReceivableClaim replay = claimMapper.selectOne(new QueryWrapper<ReceivableClaim>()
                .eq("merchant_id", merchantId).eq("request_id", requestId).last("LIMIT 1"));
        if (replay != null) {
            return validateChargeReplay(replay, orderNo, accountId);
        }

        Order order = orderService.getOne(new QueryWrapper<Order>()
                .eq("merchantId", merchantId).eq("shop_id", shopId).eq("order_no", orderNo)
                .last("LIMIT 1 FOR UPDATE"));
        if (order == null) throw new ApiException(404, "ORDER_NOT_FOUND", "订单不存在或不属于当前门店");

        // The first idempotency read happens before the order lock. A concurrent winner may
        // commit while this request waits, so re-read after acquiring the lock before judging
        // the now-successful order as non-chargeable.
        replay = claimMapper.selectOne(new QueryWrapper<ReceivableClaim>()
                .eq("merchant_id", merchantId).eq("request_id", requestId).last("LIMIT 1"));
        if (replay != null) {
            return validateChargeReplay(replay, orderNo, accountId);
        }
        ReceivableClaim existingOrder = claimMapper.selectOne(new QueryWrapper<ReceivableClaim>()
                .eq("merchant_id", merchantId).eq("shop_id", shopId).eq("order_no", orderNo)
                .ne("status", ReceivableClaim.STATUS_REVERSED).last("LIMIT 1"));
        if (existingOrder != null) {
            if (!Objects.equals(existingOrder.getAccountId(), accountId)) {
                throw new ApiException(409, "ORDER_ALREADY_RECEIVABLE", "订单已挂账到其他应收账户");
            }
            return existingOrder;
        }
        if (!"unsettled".equalsIgnoreCase(order.getTransac_status())) {
            throw new ApiException(409, "ORDER_NOT_UNSETTLED", "只有未结账订单可以挂账");
        }
        if (StringUtils.hasText(order.getMaster_order_no())) {
            throw new ApiException(409, "SLAVE_ORDER_NOT_ALLOWED", "并台从单不能单独挂账");
        }

        ReceivableAccount account = lockAccount(accountId, merchantId);
        assertAccountCanCharge(account, shopId);
        long amountFen = OrderNetRevenue.netRevenueFen(order);
        if (amountFen <= 0) throw new ApiException(422, "INVALID_ORDER_AMOUNT", "订单净应付金额必须大于0");
        long current = nz(account.getOutstandingFen());
        long limit = nz(account.getCreditLimitFen());
        if (amountFen > limit - current) {
            throw new ApiException(422, "RECEIVABLE_CREDIT_EXCEEDED", "挂账金额超过账户可用授信额度");
        }

        Date now = Date.from(clock.instant());
        ReceivableClaim claim = new ReceivableClaim();
        claim.setClaimNo(serial("AR"));
        claim.setRequestId(requestId);
        claim.setActiveKey(merchantId + ":" + shopId + ":" + orderNo);
        claim.setMerchantId(merchantId);
        claim.setShopId(shopId);
        claim.setAccountId(accountId);
        claim.setOrderId(order.getId() != null ? order.getId().longValue() : null);
        claim.setOrderNo(orderNo);
        claim.setOriginalAmountFen(amountFen);
        claim.setOutstandingFen(amountFen);
        claim.setDueDate(Date.from(currentBusinessDay(shopId).plusDays(Math.max(0, nz(account.getPaymentTermsDays())))
                .atStartOfDay(BUSINESS_ZONE).toInstant()));
        claim.setStatus(ReceivableClaim.STATUS_OPEN);
        claim.setNote(trim(note, 500));
        claim.setVersion(1);
        claim.setChargedBy(operatorId);
        claim.setChargedAt(now);
        claim.setUpdatedAt(now);
        requireRow(claimMapper.insert(claim), "应收单创建失败");

        ReceivableLedger ledger = ledger(claim, ReceivableLedger.TYPE_CHARGE, amountFen,
                null, requestId, operatorId, note, null, now);
        requireRow(ledgerMapper.insert(ledger), "应收挂账流水写入失败");

        account.setOutstandingFen(current + amountFen);
        account.setVersion(nz(account.getVersion()) + 1);
        account.setUpdatedBy(operatorId);
        account.setUpdatedAt(now);
        requireRow(accountMapper.updateById(account), "应收账户余额更新失败");

        order.setTransac_status("success");
        order.setPayment_method(PAYMENT_METHOD_RECEIVABLE);
        order.setPay_time(now);
        order.setPay_amount_cash(0d);
        order.setPay_amount_wechat(0d);
        order.setPay_amount_alipay(0d);
        order.setPay_amount_balance(0d);
        order.setPay_amount_gift(0d);
        order.setCheckout_cash_tender(0d);
        order.setCheckout_change_amount(0d);
        if (!orderService.updateById(order)) throw new IllegalStateException("挂账订单状态更新失败");

        Order committedOrder = order;
        AfterCommitExecutor.execute("receivable_charge_fulfillment:" + orderNo,
                () -> paymentSuccessHandler.run(committedOrder, 0d));
        return claim;
    }

    @Transactional(isolation = Isolation.READ_COMMITTED, rollbackFor = Exception.class)
    public ReceivableLedger collect(Integer shopId, Integer operatorId, String merchantId,
                                    Long claimId, Long amountFen, String channel,
                                    String requestId, String note, Long drawerSessionId) {
        requireShop(shopId);
        merchantId = normalizeMerchant(merchantId);
        requestId = required(requestId, "requestId不能为空", 128);
        if (claimId == null || claimId <= 0) throw invalid("应收单不能为空");
        if (amountFen == null || amountFen <= 0) throw invalid("回款金额必须大于0");
        channel = normalizeCollectionChannel(channel);

        ReceivableLedger replay = ledgerMapper.selectOne(new QueryWrapper<ReceivableLedger>()
                .eq("merchant_id", merchantId).eq("request_id", requestId).last("LIMIT 1"));
        if (replay != null) {
            if (!Objects.equals(replay.getClaimId(), claimId)
                    || !ReceivableLedger.TYPE_COLLECTION.equals(replay.getEntryType())
                    || !Objects.equals(-replay.getAmountFen(), amountFen)) {
                throw new ApiException(409, "RECEIVABLE_IDEMPOTENCY_CONFLICT", "requestId已用于其他应收操作");
            }
            return replay;
        }

        ReceivableClaim claim = lockClaim(claimId, merchantId, shopId);
        if (!isCollectable(claim.getStatus())) throw new ApiException(409, "CLAIM_NOT_COLLECTABLE", "当前应收状态不允许回款");
        long outstanding = nz(claim.getOutstandingFen());
        if (amountFen > outstanding) throw new ApiException(422, "COLLECTION_EXCEEDS_OUTSTANDING", "回款金额不能超过未清金额");
        ReceivableAccount account = lockAccount(claim.getAccountId(), merchantId);
        assertAccountVisible(account, shopId);
        Date now = Date.from(clock.instant());

        ReceivableLedger ledger = ledger(claim, ReceivableLedger.TYPE_COLLECTION, -amountFen,
                channel, requestId, operatorId, note, drawerSessionId, now);
        requireRow(ledgerMapper.insert(ledger), "应收回款流水写入失败");
        long remaining = outstanding - amountFen;
        claim.setOutstandingFen(remaining);
        claim.setStatus(remaining == 0 ? ReceivableClaim.STATUS_SETTLED : ReceivableClaim.STATUS_PARTIAL);
        claim.setSettledAt(remaining == 0 ? now : null);
        claim.setVersion(nz(claim.getVersion()) + 1);
        claim.setUpdatedAt(now);
        requireRow(claimMapper.updateById(claim), "应收单余额更新失败");
        account.setOutstandingFen(Math.max(0, nz(account.getOutstandingFen()) - amountFen));
        account.setVersion(nz(account.getVersion()) + 1);
        account.setUpdatedBy(operatorId);
        account.setUpdatedAt(now);
        requireRow(accountMapper.updateById(account), "应收账户余额更新失败");

        if ("CASH".equals(channel) && drawerSessionService != null) {
            if (drawerSessionId == null) throw new ApiException(422, "DRAWER_SESSION_REQUIRED", "现金回款必须指定钱箱会话");
            drawerSessionService.recordManualMovement(shopId, drawerSessionId, CashMovement.TYPE_CASH_IN,
                    amountFen.intValue(), "RECEIVABLE_COLLECTION", "应收回款: " + claim.getOrderNo(),
                    operatorId, null, "AR_" + requestId);
        }
        return ledger;
    }

    public ReceivableWindowSummary summarizeWindow(String merchantId, Integer shopId, Date start, Date end) {
        if (shopId == null || start == null || end == null) return ReceivableWindowSummary.empty();
        String normalizedMerchant = normalizeMerchant(merchantId);
        Map<String, Object> row = ledgerMapper.summarizeWindow(normalizedMerchant, shopId, start, end);
        // Merchant-scoped accounts may contain claims from several stores. Summing account balances
        // would duplicate the chain-wide amount in every store's Z report, so store outstanding is
        // derived from store-owned claims instead.
        Long outstanding = claimMapper.sumOutstandingByShop(normalizedMerchant, shopId);
        return new ReceivableWindowSummary(num(row, "charged_fen"), num(row, "collected_fen"),
                num(row, "writeoff_fen"), num(row, "reversed_fen"), nz(outstanding),
                num(row, "cutoff_ledger_id"));
    }

    public long currentLedgerId(String merchantId, Integer shopId) {
        if (shopId == null) return 0L;
        ReceivableLedger latest = ledgerMapper.selectOne(new QueryWrapper<ReceivableLedger>()
                .eq("merchant_id", normalizeMerchant(merchantId)).eq("shop_id", shopId)
                .orderByDesc("id").last("LIMIT 1"));
        return latest != null && latest.getId() != null ? latest.getId() : 0L;
    }

    @Transactional(rollbackFor = Exception.class)
    public ReceivableAccount createAccount(Integer shopId, Integer operatorId, String merchantId,
                                           String scopeType, String customerType, String customerName,
                                           String contactName, String contactPhone, String taxNo,
                                           Long creditLimitFen, Integer paymentTermsDays, String notes) {
        requireShop(shopId);
        merchantId = normalizeMerchant(merchantId);
        scopeType = normalizeScope(scopeType);
        requireMerchantScopePermission(scopeType, operatorId);
        customerType = normalizeCustomerType(customerType);
        customerName = required(customerName, "客户名称不能为空", 120);
        validateCredit(creditLimitFen, paymentTermsDays);
        Date now = Date.from(clock.instant());
        ReceivableAccount account = new ReceivableAccount();
        account.setAccountNo(serial("ARA"));
        account.setMerchantId(merchantId);
        account.setScopeType(scopeType);
        account.setShopId(ReceivableAccount.SCOPE_SHOP.equals(scopeType) ? shopId : null);
        account.setCustomerType(customerType);
        account.setCustomerName(customerName);
        account.setContactName(trim(contactName, 80));
        account.setContactPhone(trim(contactPhone, 32));
        account.setTaxNo(trim(taxNo, 64));
        account.setCreditLimitFen(creditLimitFen);
        account.setOutstandingFen(0L);
        account.setPaymentTermsDays(paymentTermsDays);
        account.setStatus(ReceivableAccount.STATUS_ACTIVE);
        account.setNotes(trim(notes, 500));
        account.setVersion(1);
        account.setCreatedBy(operatorId);
        account.setUpdatedBy(operatorId);
        account.setCreatedAt(now);
        account.setUpdatedAt(now);
        requireRow(accountMapper.insert(account), "应收账户创建失败");
        return account;
    }

    @Transactional(rollbackFor = Exception.class)
    public ReceivableAccount updateAccount(Integer shopId, Integer operatorId, String merchantId, Long accountId,
                                           String scopeType, String customerType, String customerName, String contactName,
                                           String contactPhone, String taxNo, Long creditLimitFen,
                                           Integer paymentTermsDays, String notes) {
        requireShop(shopId);
        ReceivableAccount account = lockAccount(accountId, normalizeMerchant(merchantId));
        assertAccountVisible(account, shopId);
        requireMerchantScopePermission(account.getScopeType(), operatorId);
        if (ReceivableAccount.STATUS_CLOSED.equals(account.getStatus()))
            throw new ApiException(409, "RECEIVABLE_ACCOUNT_CLOSED", "已关闭账户不能修改");
        if (StringUtils.hasText(scopeType) && !Objects.equals(account.getScopeType(), normalizeScope(scopeType))) {
            throw new ApiException(409, "RECEIVABLE_ACCOUNT_SCOPE_IMMUTABLE", "账户创建后不能修改适用范围");
        }
        validateCredit(creditLimitFen, paymentTermsDays);
        if (creditLimitFen < nz(account.getOutstandingFen()))
            throw new ApiException(422, "CREDIT_BELOW_OUTSTANDING", "授信额度不能低于当前未清余额");
        account.setCustomerType(normalizeCustomerType(customerType));
        account.setCustomerName(required(customerName, "客户名称不能为空", 120));
        account.setContactName(trim(contactName, 80));
        account.setContactPhone(trim(contactPhone, 32));
        account.setTaxNo(trim(taxNo, 64));
        account.setCreditLimitFen(creditLimitFen);
        account.setPaymentTermsDays(paymentTermsDays);
        account.setNotes(trim(notes, 500));
        account.setVersion(nz(account.getVersion()) + 1);
        account.setUpdatedBy(operatorId);
        account.setUpdatedAt(Date.from(clock.instant()));
        requireRow(accountMapper.updateById(account), "应收账户更新失败");
        return account;
    }

    @Transactional(rollbackFor = Exception.class)
    public ReceivableAccount changeAccountStatus(Integer shopId, Integer operatorId, String merchantId,
                                                  Long accountId, String status) {
        requireShop(shopId);
        ReceivableAccount account = lockAccount(accountId, normalizeMerchant(merchantId));
        assertAccountVisible(account, shopId);
        requireMerchantScopePermission(account.getScopeType(), operatorId);
        String target = required(status, "账户状态不能为空", 20).toUpperCase(Locale.ROOT);
        if (!ReceivableAccount.STATUS_ACTIVE.equals(target) && !ReceivableAccount.STATUS_SUSPENDED.equals(target))
            throw invalid("账户状态只允许ACTIVE或SUSPENDED");
        if (ReceivableAccount.STATUS_CLOSED.equals(account.getStatus()))
            throw new ApiException(409, "RECEIVABLE_ACCOUNT_CLOSED", "已关闭账户不能恢复");
        account.setStatus(target);
        account.setVersion(nz(account.getVersion()) + 1);
        account.setUpdatedBy(operatorId);
        account.setUpdatedAt(Date.from(clock.instant()));
        requireRow(accountMapper.updateById(account), "应收账户状态更新失败");
        return account;
    }

    @Transactional(rollbackFor = Exception.class)
    public ReceivableAccount closeAccount(Integer shopId, Integer operatorId, String merchantId, Long accountId) {
        requireShop(shopId);
        String normalizedMerchant = normalizeMerchant(merchantId);
        ReceivableAccount account = lockAccount(accountId, normalizedMerchant);
        assertAccountVisible(account, shopId);
        requireMerchantScopePermission(account.getScopeType(), operatorId);
        int activeClaims = claimMapper.selectCount(new QueryWrapper<ReceivableClaim>()
                .eq("merchant_id", normalizedMerchant).eq("account_id", accountId)
                .in("status", ReceivableClaim.STATUS_OPEN, ReceivableClaim.STATUS_PARTIAL,
                        ReceivableClaim.STATUS_OVERDUE));
        if (nz(account.getOutstandingFen()) != 0 || activeClaims > 0)
            throw new ApiException(409, "RECEIVABLE_ACCOUNT_HAS_BALANCE", "账户仍有未清余额，不能关闭");
        Date now = Date.from(clock.instant());
        account.setStatus(ReceivableAccount.STATUS_CLOSED);
        account.setClosedAt(now);
        account.setVersion(nz(account.getVersion()) + 1);
        account.setUpdatedBy(operatorId);
        account.setUpdatedAt(now);
        requireRow(accountMapper.updateById(account), "应收账户关闭失败");
        return account;
    }

    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> deleteAccount(Integer shopId, Integer operatorId, String merchantId, Long accountId) {
        requireShop(shopId);
        String normalizedMerchant = normalizeMerchant(merchantId);
        ReceivableAccount account = lockAccount(accountId, normalizedMerchant);
        assertAccountVisible(account, shopId);
        requireMerchantScopePermission(account.getScopeType(), operatorId);
        int activeClaims = claimMapper.selectCount(new QueryWrapper<ReceivableClaim>()
                .eq("merchant_id", normalizedMerchant).eq("account_id", accountId)
                .in("status", ReceivableClaim.STATUS_OPEN, ReceivableClaim.STATUS_PARTIAL,
                        ReceivableClaim.STATUS_OVERDUE));
        if (nz(account.getOutstandingFen()) != 0 || activeClaims > 0) {
            throw new ApiException(409, "RECEIVABLE_ACCOUNT_HAS_BALANCE", "账户仍有未清余额或未结应收，不能删除");
        }
        int totalClaims = claimMapper.selectCount(new QueryWrapper<ReceivableClaim>()
                .eq("merchant_id", normalizedMerchant).eq("account_id", accountId));
        Date now = Date.from(clock.instant());
        Map<String, Object> res = new LinkedHashMap<>();
        if (totalClaims == 0) {
            requireRow(accountMapper.deleteById(accountId), "应收账户删除失败");
            res.put("account", account);
            res.put("deleted", true);
            res.put("closed", false);
            return res;
        } else {
            account.setStatus(ReceivableAccount.STATUS_CLOSED);
            account.setClosedAt(now);
            account.setVersion(nz(account.getVersion()) + 1);
            account.setUpdatedBy(operatorId);
            account.setUpdatedAt(now);
            requireRow(accountMapper.updateById(account), "应收账户注销失败");
            res.put("account", account);
            res.put("deleted", false);
            res.put("closed", true);
            return res;
        }
    }

    @Transactional(isolation = Isolation.READ_COMMITTED, rollbackFor = Exception.class)
    public ReceivableLedger reverse(Integer shopId, Integer operatorId, String merchantId,
                                    Long claimId, String requestId, String reason) {
        requireShop(shopId);
        merchantId = normalizeMerchant(merchantId);
        requestId = required(requestId, "requestId不能为空", 128);
        reason = required(reason, "撤销原因不能为空", 500);
        ReceivableLedger replay = idempotentLedger(merchantId, requestId, claimId, ReceivableLedger.TYPE_REVERSAL);
        if (replay != null) return replay;
        ReceivableClaim claim = lockClaim(claimId, merchantId, shopId);
        if (!ReceivableClaim.STATUS_OPEN.equals(claim.getStatus())
                || !Objects.equals(claim.getOriginalAmountFen(), claim.getOutstandingFen()))
            throw new ApiException(409, "CLAIM_REVERSAL_NOT_ALLOWED", "只有从未回款的未清应收可以撤销");
        int collections = ledgerMapper.selectCount(new QueryWrapper<ReceivableLedger>()
                .eq("claim_id", claimId).eq("entry_type", ReceivableLedger.TYPE_COLLECTION));
        if (collections > 0) throw new ApiException(409, "CLAIM_HAS_COLLECTIONS", "已有回款的应收不能撤销");
        ReceivableAccount account = lockAccount(claim.getAccountId(), merchantId);
        assertAccountVisible(account, shopId);
        Date now = Date.from(clock.instant());
        long amount = nz(claim.getOutstandingFen());
        ReceivableLedger ledger = ledger(claim, ReceivableLedger.TYPE_REVERSAL, -amount,
                null, requestId, operatorId, reason, null, now);
        requireRow(ledgerMapper.insert(ledger), "应收撤销流水写入失败");
        claim.setOutstandingFen(0L);
        claim.setActiveKey(null);
        claim.setStatus(ReceivableClaim.STATUS_REVERSED);
        claim.setSettledAt(now);
        claim.setVersion(nz(claim.getVersion()) + 1);
        claim.setUpdatedAt(now);
        requireRow(claimMapper.updateById(claim), "应收撤销状态更新失败");
        account.setOutstandingFen(Math.max(0, nz(account.getOutstandingFen()) - amount));
        account.setVersion(nz(account.getVersion()) + 1);
        account.setUpdatedBy(operatorId);
        account.setUpdatedAt(now);
        requireRow(accountMapper.updateById(account), "应收账户余额释放失败");
        if (cashierCheckoutService != null) {
            Object code = cashierCheckoutService.unCheckout(shopId, claim.getOrderNo()).get("code");
            if (!Integer.valueOf(0).equals(code)) throw new IllegalStateException("挂账撤销后订单反结账失败");
        } else {
            Order order = orderService.getOne(new QueryWrapper<Order>()
                    .eq("merchantId", merchantId).eq("shop_id", shopId).eq("order_no", claim.getOrderNo())
                    .last("LIMIT 1 FOR UPDATE"));
            if (order != null) {
                order.setTransac_status("unsettled");
                order.setPayment_method(null);
                order.setPay_time(null);
                if (!orderService.updateById(order)) throw new IllegalStateException("挂账撤销后订单恢复失败");
            }
        }
        return ledger;
    }

    @Transactional(isolation = Isolation.READ_COMMITTED, rollbackFor = Exception.class)
    public ReceivableLedger writeOff(Integer shopId, Integer operatorId, String merchantId,
                                     Long claimId, String requestId, String reason) {
        requireShop(shopId);
        merchantId = normalizeMerchant(merchantId);
        requestId = required(requestId, "requestId不能为空", 128);
        reason = required(reason, "坏账核销原因不能为空", 500);
        ReceivableLedger replay = idempotentLedger(merchantId, requestId, claimId, ReceivableLedger.TYPE_WRITE_OFF);
        if (replay != null) return replay;
        ReceivableClaim claim = lockClaim(claimId, merchantId, shopId);
        if (!isCollectable(claim.getStatus()) || nz(claim.getOutstandingFen()) <= 0)
            throw new ApiException(409, "CLAIM_WRITE_OFF_NOT_ALLOWED", "当前应收状态不允许坏账核销");
        ReceivableAccount account = lockAccount(claim.getAccountId(), merchantId);
        assertAccountVisible(account, shopId);
        Date now = Date.from(clock.instant());
        long amount = nz(claim.getOutstandingFen());
        ReceivableLedger ledger = ledger(claim, ReceivableLedger.TYPE_WRITE_OFF, -amount,
                null, requestId, operatorId, reason, null, now);
        requireRow(ledgerMapper.insert(ledger), "坏账流水写入失败");
        claim.setOutstandingFen(0L);
        claim.setStatus(ReceivableClaim.STATUS_WRITTEN_OFF);
        claim.setSettledAt(now);
        claim.setVersion(nz(claim.getVersion()) + 1);
        claim.setUpdatedAt(now);
        requireRow(claimMapper.updateById(claim), "坏账状态更新失败");
        account.setOutstandingFen(Math.max(0, nz(account.getOutstandingFen()) - amount));
        account.setVersion(nz(account.getVersion()) + 1);
        account.setUpdatedBy(operatorId);
        account.setUpdatedAt(now);
        requireRow(accountMapper.updateById(account), "应收账户余额更新失败");
        return ledger;
    }

    public IPage<ReceivableAccount> listAccounts(String merchantId, Integer shopId, String status,
                                                  String keyword, long page, long pageSize) {
        requireShop(shopId);
        QueryWrapper<ReceivableAccount> q = new QueryWrapper<ReceivableAccount>()
                .eq("merchant_id", normalizeMerchant(merchantId))
                .and(w -> w.eq("shop_id", shopId).or().eq("scope_type", ReceivableAccount.SCOPE_MERCHANT))
                .eq(StringUtils.hasText(status), "status", status)
                .and(StringUtils.hasText(keyword), w -> w.like("customer_name", keyword.trim())
                        .or().like("contact_phone", keyword.trim()))
                .orderByDesc("id");
        return accountMapper.selectPage(new Page<>(Math.max(1, page), boundedPageSize(pageSize)), q);
    }

    public ReceivableAccount getAccount(String merchantId, Integer shopId, Long accountId) {
        requireShop(shopId);
        ReceivableAccount account = accountMapper.selectOne(new QueryWrapper<ReceivableAccount>()
                .eq("id", accountId).eq("merchant_id", normalizeMerchant(merchantId)).last("LIMIT 1"));
        assertAccountVisible(account, shopId);
        return account;
    }

    public List<ReceivableAccount> eligibleAccounts(String merchantId, Integer shopId) {
        requireShop(shopId);
        return accountMapper.selectList(new QueryWrapper<ReceivableAccount>()
                .eq("merchant_id", normalizeMerchant(merchantId))
                .eq("status", ReceivableAccount.STATUS_ACTIVE)
                .and(w -> w.eq("shop_id", shopId).or().eq("scope_type", ReceivableAccount.SCOPE_MERCHANT))
                .apply("credit_limit_fen > outstanding_fen").orderByAsc("customer_name").last("LIMIT 200"));
    }

    public IPage<ReceivableClaim> listClaims(String merchantId, Integer shopId, Long accountId,
                                              String status, long page, long pageSize) {
        requireShop(shopId);
        Date businessDayStart = businessDayStart(shopId);
        String normalizedStatus = StringUtils.hasText(status) ? status.trim().toUpperCase(Locale.ROOT) : null;
        QueryWrapper<ReceivableClaim> query = new QueryWrapper<ReceivableClaim>()
                .eq("merchant_id", normalizeMerchant(merchantId)).eq("shop_id", shopId)
                .eq(accountId != null, "account_id", accountId);
        if (ReceivableClaim.STATUS_OVERDUE.equals(normalizedStatus)) {
            query.in("status", ReceivableClaim.STATUS_OPEN, ReceivableClaim.STATUS_PARTIAL,
                    ReceivableClaim.STATUS_OVERDUE).lt("due_date", businessDayStart);
        } else if (ReceivableClaim.STATUS_OPEN.equals(normalizedStatus)
                || ReceivableClaim.STATUS_PARTIAL.equals(normalizedStatus)) {
            query.eq("status", normalizedStatus).ge("due_date", businessDayStart);
        } else if (StringUtils.hasText(normalizedStatus)) {
            query.eq("status", normalizedStatus);
        }
        IPage<ReceivableClaim> result = claimMapper.selectPage(
                new Page<>(Math.max(1, page), boundedPageSize(pageSize)), query.orderByDesc("id"));
        if (result != null && result.getRecords() != null) {
            result.getRecords().forEach(claim -> markOverdueForRead(claim, businessDayStart));
        }
        return result;
    }

    public ReceivableClaim getClaim(String merchantId, Integer shopId, Long claimId) {
        requireShop(shopId);
        ReceivableClaim claim = claimMapper.selectOne(new QueryWrapper<ReceivableClaim>()
                .eq("id", claimId).eq("merchant_id", normalizeMerchant(merchantId))
                .eq("shop_id", shopId).last("LIMIT 1"));
        if (claim == null) throw new ApiException(404, "RECEIVABLE_CLAIM_NOT_FOUND", "应收单不存在或不属于当前门店");
        markOverdueForRead(claim, businessDayStart(shopId));
        return claim;
    }

    public List<ReceivableLedger> statement(String merchantId, Integer shopId, Long accountId, int limit) {
        requireShop(shopId);
        if (accountId == null) throw invalid("账户ID不能为空");
        ReceivableAccount account = accountMapper.selectOne(new QueryWrapper<ReceivableAccount>()
                .eq("id", accountId).eq("merchant_id", normalizeMerchant(merchantId)).last("LIMIT 1"));
        assertAccountVisible(account, shopId);
        return ledgerMapper.selectList(new QueryWrapper<ReceivableLedger>()
                .eq("merchant_id", normalizeMerchant(merchantId)).eq("account_id", accountId)
                .eq("shop_id", shopId)
                .orderByDesc("id").last("LIMIT " + Math.min(500, Math.max(1, limit))));
    }

    public Map<String, Object> aging(String merchantId, Integer shopId) {
        requireShop(shopId);
        LocalDate businessDay = currentBusinessDay(shopId);
        List<ReceivableClaim> claims = claimMapper.selectList(new QueryWrapper<ReceivableClaim>()
                .eq("merchant_id", normalizeMerchant(merchantId)).eq("shop_id", shopId)
                .in("status", ReceivableClaim.STATUS_OPEN, ReceivableClaim.STATUS_PARTIAL, ReceivableClaim.STATUS_OVERDUE));
        long current = 0, d1 = 0, d31 = 0, d61 = 0, d91 = 0;
        for (ReceivableClaim claim : claims != null ? claims : java.util.Collections.<ReceivableClaim>emptyList()) {
            long amount = nz(claim.getOutstandingFen());
            LocalDate dueDay = claim.getDueDate() == null ? null
                    : claim.getDueDate().toInstant().atZone(BUSINESS_ZONE).toLocalDate();
            long days = dueDay == null ? 0 : Math.max(0, ChronoUnit.DAYS.between(dueDay, businessDay));
            if (dueDay == null || !dueDay.isBefore(businessDay)) current += amount;
            else if (days <= 30) d1 += amount;
            else if (days <= 60) d31 += amount;
            else if (days <= 90) d61 += amount;
            else d91 += amount;
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("current_fen", current);
        result.put("days_1_30_fen", d1);
        result.put("days_31_60_fen", d31);
        result.put("days_61_90_fen", d61);
        result.put("days_91_plus_fen", d91);
        result.put("total_outstanding_fen", current + d1 + d31 + d61 + d91);
        result.put("claim_count", claims != null ? claims.size() : 0);
        return result;
    }

    private ReceivableAccount lockAccount(Long id, String merchantId) {
        ReceivableAccount account = accountMapper.selectOne(new QueryWrapper<ReceivableAccount>()
                .eq("id", id).eq("merchant_id", merchantId).last("LIMIT 1 FOR UPDATE"));
        if (account == null) throw new ApiException(404, "RECEIVABLE_ACCOUNT_NOT_FOUND", "挂账账户不存在");
        return account;
    }

    private ReceivableClaim lockClaim(Long id, String merchantId, Integer shopId) {
        ReceivableClaim claim = claimMapper.selectOne(new QueryWrapper<ReceivableClaim>()
                .eq("id", id).eq("merchant_id", merchantId).eq("shop_id", shopId).last("LIMIT 1 FOR UPDATE"));
        if (claim == null) throw new ApiException(404, "RECEIVABLE_CLAIM_NOT_FOUND", "应收单不存在或不属于当前门店");
        return claim;
    }

    private static void assertAccountCanCharge(ReceivableAccount account, Integer shopId) {
        assertAccountVisible(account, shopId);
        if (!ReceivableAccount.STATUS_ACTIVE.equals(account.getStatus()))
            throw new ApiException(409, "RECEIVABLE_ACCOUNT_INACTIVE", "挂账账户未启用");
    }

    private static void assertAccountVisible(ReceivableAccount account, Integer shopId) {
        if (account == null) throw new ApiException(404, "RECEIVABLE_ACCOUNT_NOT_FOUND", "挂账账户不存在");
        boolean allowed = ReceivableAccount.SCOPE_MERCHANT.equals(account.getScopeType())
                || Objects.equals(account.getShopId(), shopId);
        if (!allowed) throw new ApiException(403, "RECEIVABLE_ACCOUNT_SHOP_MISMATCH", "挂账账户不属于当前门店");
    }

    private ReceivableLedger ledger(ReceivableClaim claim, String type, long amountFen, String channel,
                                     String requestId, Integer operatorId, String note,
                                     Long drawerSessionId, Date now) {
        ReceivableLedger ledger = new ReceivableLedger();
        ledger.setLedgerNo(serial("ARL"));
        ledger.setRequestId(requestId);
        ledger.setMerchantId(claim.getMerchantId());
        ledger.setShopId(claim.getShopId());
        ledger.setAccountId(claim.getAccountId());
        ledger.setClaimId(claim.getId());
        ledger.setOrderId(claim.getOrderId());
        ledger.setOrderNo(claim.getOrderNo());
        ledger.setEntryType(type);
        ledger.setAmountFen(amountFen);
        ledger.setChannel(channel);
        ledger.setDrawerSessionId(drawerSessionId);
        ledger.setOperatorId(operatorId);
        ledger.setBusinessDay(currentBusinessDay(claim.getShopId()).toString());
        ledger.setNote(trim(note, 500));
        ledger.setOccurredAt(now);
        ledger.setCreatedAt(now);
        return ledger;
    }

    private LocalDate currentBusinessDay(Integer shopId) {
        LocalDateTime now = LocalDateTime.ofInstant(clock.instant(), BUSINESS_ZONE);
        Shop shop = shopService != null ? shopService.getById(shopId) : null;
        java.time.LocalTime settle = ShopBusinessWindowResolver.resolveSettleTimeOrDefault(shop);
        return now.toLocalTime().isBefore(settle) ? now.toLocalDate().minusDays(1) : now.toLocalDate();
    }

    private Date businessDayStart(Integer shopId) {
        return Date.from(currentBusinessDay(shopId).atStartOfDay(BUSINESS_ZONE).toInstant());
    }

    private static void markOverdueForRead(ReceivableClaim claim, Date businessDayStart) {
        if (claim != null && claim.getDueDate() != null && claim.getDueDate().before(businessDayStart)
                && (ReceivableClaim.STATUS_OPEN.equals(claim.getStatus())
                || ReceivableClaim.STATUS_PARTIAL.equals(claim.getStatus()))) {
            claim.setStatus(ReceivableClaim.STATUS_OVERDUE);
        }
    }

    private ReceivableLedger idempotentLedger(String merchantId, String requestId, Long claimId, String type) {
        ReceivableLedger replay = ledgerMapper.selectOne(new QueryWrapper<ReceivableLedger>()
                .eq("merchant_id", merchantId).eq("request_id", requestId).last("LIMIT 1"));
        if (replay == null) return null;
        if (!Objects.equals(replay.getClaimId(), claimId) || !type.equals(replay.getEntryType()))
            throw new ApiException(409, "RECEIVABLE_IDEMPOTENCY_CONFLICT", "requestId已用于其他应收操作");
        return replay;
    }

    private static ReceivableClaim validateChargeReplay(ReceivableClaim replay, String orderNo, Long accountId) {
        if (!Objects.equals(replay.getOrderNo(), orderNo) || !Objects.equals(replay.getAccountId(), accountId)) {
            throw new ApiException(409, "RECEIVABLE_IDEMPOTENCY_CONFLICT", "requestId已用于其他挂账请求");
        }
        return replay;
    }

    private static boolean isCollectable(String status) {
        return ReceivableClaim.STATUS_OPEN.equals(status) || ReceivableClaim.STATUS_PARTIAL.equals(status)
                || ReceivableClaim.STATUS_OVERDUE.equals(status);
    }

    private static String normalizeCollectionChannel(String value) {
        String v = required(value, "回款渠道不能为空", 32).toUpperCase(Locale.ROOT);
        if (!v.matches("CASH|BANK_TRANSFER|WECHAT|ALIPAY|OTHER"))
            throw invalid("不支持的回款渠道");
        return v;
    }

    private static String normalizeMerchant(String merchantId) {
        return StringUtils.hasText(merchantId) ? merchantId.trim() : "1";
    }

    private static String normalizeScope(String scopeType) {
        String scope = StringUtils.hasText(scopeType) ? scopeType.trim().toUpperCase(Locale.ROOT) : ReceivableAccount.SCOPE_SHOP;
        if (!ReceivableAccount.SCOPE_SHOP.equals(scope) && !ReceivableAccount.SCOPE_MERCHANT.equals(scope))
            throw invalid("账户范围只允许SHOP或MERCHANT");
        return scope;
    }

    private static String normalizeCustomerType(String customerType) {
        String type = StringUtils.hasText(customerType) ? customerType.trim().toUpperCase(Locale.ROOT) : "PERSON";
        if (!"PERSON".equals(type) && !"COMPANY".equals(type))
            throw invalid("客户类型只允许PERSON或COMPANY");
        return type;
    }

    private static void validateCredit(Long creditLimitFen, Integer paymentTermsDays) {
        if (creditLimitFen == null || creditLimitFen < 0 || creditLimitFen > 100_000_000_000L)
            throw invalid("授信额度无效");
        if (paymentTermsDays == null || paymentTermsDays < 0 || paymentTermsDays > 3650)
            throw invalid("账期天数无效");
    }

    private static String required(String value, String message, int max) {
        if (!StringUtils.hasText(value)) throw invalid(message);
        String v = value.trim();
        if (v.length() > max) throw invalid(message.replace("不能为空", "长度超限"));
        return v;
    }

    private static ApiException invalid(String message) {
        return new ApiException(400, "RECEIVABLE_REQUEST_INVALID", message);
    }

    private static String trim(String value, int max) {
        if (!StringUtils.hasText(value)) return null;
        String v = value.trim();
        return v.length() <= max ? v : v.substring(0, max);
    }

    private static void requireShop(Integer shopId) {
        if (shopId == null || shopId <= 0) throw new ApiException(400, "SHOP_CONTEXT_REQUIRED", "缺少门店上下文");
    }

    private static void requireRow(int rows, String message) {
        if (rows != 1) throw new IllegalStateException(message);
    }

    private void requireMerchantScopePermission(String scopeType, Integer operatorId) {
        if (!ReceivableAccount.SCOPE_MERCHANT.equals(scopeType)) return;
        boolean superAdmin = operatorId != null && adminShopAccessService != null
                && adminShopAccessService.isSuperAdmin(operatorId);
        Set<String> permissions = operatorId != null && adminPermissionService != null
                ? adminPermissionService.getPermissionCodesByAdminId(operatorId) : java.util.Collections.emptySet();
        if (!superAdmin && (permissions == null || !permissions.contains("receivable:merchant_manage"))) {
            throw new ApiException(403, "RECEIVABLE_MERCHANT_SCOPE_FORBIDDEN", "仅总部应收管理员可管理商户共享授信账户");
        }
    }

    private String serial(String prefix) {
        return prefix + LocalDate.now(clock).toString().replace("-", "") + "_"
                + UUID.randomUUID().toString().replace("-", "").substring(0, 20).toUpperCase(Locale.ROOT);
    }

    private static long boundedPageSize(long size) { return Math.min(100, Math.max(1, size)); }
    private static long nz(Long value) { return value != null ? value : 0L; }
    private static int nz(Integer value) { return value != null ? value : 0; }
    private static long num(Map<String, Object> row, String key) {
        if (row == null || row.get(key) == null) return 0L;
        Object value = row.get(key);
        return value instanceof Number ? ((Number) value).longValue() : Long.parseLong(String.valueOf(value));
    }
}

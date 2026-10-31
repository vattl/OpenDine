package com.lanf.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.Table;
import com.lanf.entity.User;
import com.lanf.entity.UserCoupon;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.payment.service.PaymentCapabilityService;
import com.lanf.payment.service.PaymentRefundLedger;
import com.lanf.payment.service.CashierCollectionIntentService;
import com.lanf.payment.service.WechatJsapiPaymentService;
import com.lanf.payment.success.PaymentSuccessHandler;
import com.lanf.payment.support.PaymentChannelCatalog;
import com.lanf.payment.support.PaymentDiningTypeUtil;
import com.lanf.util.OrderCheckoutChangeHelper;
import com.lanf.util.OrderNetRevenue;
import com.lanf.util.OrderPayChannelAmounts;
import com.lanf.util.UserWalletSplitUtil;
import com.lanf.util.AfterCommitExecutor;
import com.lanf.entity.PaymentLedger;
import com.lanf.entity.DrawerSession;
import com.lanf.entity.Shop;
import com.lanf.util.ShopBusinessWindowResolver;
import com.lanf.access.model.AccessContext;
import com.lanf.access.service.ApprovalService;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.security.SecurityAuditService;
import com.lanf.security.SensitiveOperationAuthorizationService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import javax.servlet.http.HttpServletRequest;
import java.util.Set;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/**
 * Owns cashier settlement as one database transaction. The order row lock is the
 * idempotency/concurrency boundary; wallet and order mutations commit or roll back together.
 */
@Service
public class CashierCheckoutService {

    private static final String CASHIER_OPENID = "cashier_system";
    private static final String DINE_IN = "堂食";
    private static final String TAKE_OUT = "打包";
    private static final String LEGACY_DINE_IN = "\u936B\u509E\uE5E4";
    private static final String LEGACY_TAKE_OUT = "\u93B5\u64B3\u5BD8";
    private static final String LEGACY_TAKE_AWAY = "\u6FB6\u6827\u752B";

    @Autowired
    private IOrderService orderService;
    @Autowired
    private ITableService tableService;
    @Autowired
    private IUserService userService;
    @Autowired
    private UserCouponMapper userCouponMapper;
    @Autowired
    private PaymentCapabilityService paymentCapabilityService;
    @Autowired
    private PaymentRefundLedger paymentRefundLedger;
    @Autowired
    private CashierCollectionIntentService collectionIntentService;
    @Autowired
    private WechatJsapiPaymentService wechatJsapiPaymentService;
    @Autowired
    private PaymentSuccessHandler paymentSuccessHandler;
    @Autowired
    private PaymentLedgerService paymentLedgerService;
    @Autowired(required = false)
    private DrawerSessionService drawerSessionService;
    @Autowired(required = false)
    private IShopService shopService;
    @Autowired(required = false)
    private IAdminPermissionService adminPermissionService;
    @Autowired(required = false)
    private IAdminShopAccessService adminShopAccessService;
    @Autowired(required = false)
    private SensitiveOperationAuthorizationService sensitiveOperationAuthorizationService;
    @Autowired(required = false)
    private ApprovalService approvalService;
    @Autowired(required = false)
    private SecurityAuditService securityAuditService;
    @Autowired(required = false)
    private HttpServletRequest httpServletRequest;
    @Autowired(required = false)
    private com.lanf.service.IShopMemberWalletService shopMemberWalletService;
    @Autowired(required = false)
    private com.lanf.payment.mapper.WechatNativePaymentAttemptMapper nativeAttemptMapper;
    @Autowired(required = false)
    private com.lanf.mapper.DailyCloseSnapshotMapper dailyCloseSnapshotMapper;
    @Autowired(required = false)
    private IDailyStatService dailyStatService;

    public static final String PERMISSION_ADMIN_MANAGE = "admin:manage";

    public boolean isForceCheckout(Map<String, Object> body) {
        if (body == null) return false;
        Object val = body.get("force");
        if (val == null) val = body.get("force_checkout");
        if (val == null) val = body.get("forceCheckout");
        if (val instanceof Boolean) return (Boolean) val;
        if (val instanceof Number) return ((Number) val).intValue() == 1;
        if (val != null) {
            String s = val.toString().trim().toLowerCase();
            return "true".equals(s) || "1".equals(s);
        }
        return false;
    }

    /**
     * 校验强制结账所需的 admin:manage 权限。
     * 返回 null 表示校验通过（返回已授权管理员 ID）；返回非空 R 表示权限不足被拦截。
     */
    public R checkForceCheckoutPermission(Integer shopId, Map<String, Object> body, Integer[] authorizedAdminIdOut) {
        if (body != null && Boolean.TRUE.equals(body.get("_forcePreAuthorized"))) {
            if (authorizedAdminIdOut != null && authorizedAdminIdOut.length > 0) {
                Object adminIdObj = body.get("_authorizedAdminId");
                if (adminIdObj instanceof Integer) {
                    authorizedAdminIdOut[0] = (Integer) adminIdObj;
                } else if (adminIdObj instanceof Number) {
                    authorizedAdminIdOut[0] = ((Number) adminIdObj).intValue();
                }
            }
            return null;
        }

        Integer operatorId = intVal(body, "operator_id", "operatorId", "admin_id", "adminId");
        if (operatorId == null && httpServletRequest != null) {
            Object attr = httpServletRequest.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
            if (attr instanceof Integer) {
                operatorId = (Integer) attr;
            }
        }

        // 1. 操作人自身具备超管身份或拥有 admin:manage 权限
        if (operatorId != null) {
            if (adminShopAccessService != null && adminShopAccessService.isSuperAdmin(operatorId)) {
                if (authorizedAdminIdOut != null && authorizedAdminIdOut.length > 0) {
                    authorizedAdminIdOut[0] = operatorId;
                }
                return null;
            }
            if (adminPermissionService != null) {
                Set<String> codes = adminPermissionService.getPermissionCodesByAdminId(operatorId);
                if (codes != null && codes.contains(PERMISSION_ADMIN_MANAGE)) {
                    if (authorizedAdminIdOut != null && authorizedAdminIdOut.length > 0) {
                        authorizedAdminIdOut[0] = operatorId;
                    }
                    return null;
                }
            }
        }

        // 2. 尝试审批令牌授权
        String approvalToken = text(body, "approvalToken", "approval_token");
        if (StringUtils.hasText(approvalToken) && approvalService != null && operatorId != null) {
            String orderNo = text(body, "order_no", "orderNo");
            AccessContext ctx = AccessContext.builder()
                    .adminId(operatorId)
                    .shopId(shopId)
                    .permissionCode(PERMISSION_ADMIN_MANAGE)
                    .resourceType("ORDER")
                    .resourceId(orderNo != null ? orderNo : "N/A")
                    .terminalId(text(body, "terminalId", "terminal_id"))
                    .build();
            if (approvalService.validateAndConsume(approvalToken, ctx)) {
                if (authorizedAdminIdOut != null && authorizedAdminIdOut.length > 0) {
                    authorizedAdminIdOut[0] = operatorId;
                }
                return null;
            }
            return R.error(40321, "授权令牌无效、已过期或不匹配当前业务");
        }

        // 3. 尝试主管现场密码授权
        if (sensitiveOperationAuthorizationService != null) {
            SensitiveOperationAuthorizationService.Decision decision =
                    sensitiveOperationAuthorizationService.authorize(
                            body, PERMISSION_ADMIN_MANAGE, shopId, false);
            if (decision.isAllowed()) {
                if (authorizedAdminIdOut != null && authorizedAdminIdOut.length > 0) {
                    authorizedAdminIdOut[0] = decision.getAdmin().getId();
                }
                return null;
            }
        }

        return R.error(403, "强制结账需要具备 " + PERMISSION_ADMIN_MANAGE + " 权限");
    }

    @Transactional(isolation = Isolation.READ_COMMITTED, rollbackFor = Exception.class)
    public R checkout(Integer shopId, Map<String, Object> body) {
        return checkoutInternal(shopId, body, true);
    }

    /**
     * 结账但保留订单原有 merchantId（个人收款回调专用）。
     * 正常收银结账请使用 {@link #checkout(Integer, Map)}，本方法不会把 merchantId 覆盖为 1。
     */
    @Transactional(isolation = Isolation.READ_COMMITTED, rollbackFor = Exception.class)
    public R checkoutKeepMerchantId(Integer shopId, Map<String, Object> body) {
        return checkoutInternal(shopId, body, false);
    }

    private R checkoutInternal(Integer shopId, Map<String, Object> body, boolean writeMerchantId) {
        if (shopId == null || shopId <= 0) {
            return R.error(4001, "缺少门店上下文");
        }
        String orderNo = text(body, "order_no", "orderNo");
        if (!StringUtils.hasText(orderNo)) {
            return R.error("订单号不能为空");
        }
        Order order = lockOrder(orderNo, shopId);
        if (order == null) {
            return R.error("订单不存在或不属于当前门店");
        }
        normalizeLegacyDiningType(order);

        String requestedMethod = PaymentChannelCatalog.normalizePaymentMethod(
                defaultText(text(body, "payment_method", "paymentMethod"), "cash"));
        String requestedCode = PaymentChannelCatalog.codeFromPaymentMethod(requestedMethod);
        if (requestedCode == null) {
            return R.error("不支持的支付渠道：" + requestedMethod);
        }
        if ("success".equalsIgnoreCase(order.getTransac_status())) {
            if (!Objects.equals(requestedMethod,
                    PaymentChannelCatalog.normalizePaymentMethod(order.getPayment_method()))) {
                return R.error("订单已使用其他支付方式结账");
            }
            return success(order, true, findPayer(order));
        }
        if (!"unsettled".equalsIgnoreCase(order.getTransac_status())) {
            return R.error("订单状态不允许结账");
        }
        if (StringUtils.hasText(order.getMaster_order_no())) {
            boolean allowSlave = Boolean.TRUE.equals(body.get("allowSlaveOrderCheckout"))
                    || Boolean.TRUE.equals(body.get("table_checkout"));
            if (!allowSlave) {
                return R.error("该订单为并台从单，不支持单独结账，请通过主桌统一结账");
            }
        }
        if (!Boolean.TRUE.equals(body.get("allowSlaveOrderCheckout"))
                && !Boolean.TRUE.equals(body.get("table_checkout"))) {
            long slaveCount = orderService.count(new QueryWrapper<Order>()
                    .eq("shop_id", shopId)
                    .eq("master_order_no", order.getOrder_no())
                    .eq("transac_status", "unsettled"));
            if (slaveCount > 0) {
                return R.error("该桌台存在并台从单，不支持单笔结账，请通过主桌统一结账");
            }
        }
        if (!paymentCapabilityService.isCashierPaymentMethodEnabled(
                shopId, requestedCode)) {
            return R.error("当前门店未启用支付渠道：" + requestedMethod);
        }

        // 手工结账属于另一种资金事实。必须先收敛可能已拉起的 JSAPI 支付：
        // 已成功则阻止手工结账，未支付则关单，未知状态则 fail closed。
        wechatJsapiPaymentService.prepareForAmountMutation(order);

        double payable = OrderNetRevenue.netRevenueYuan(order);
        if (!Double.isFinite(payable) || payable < 0d) {
            return R.error("订单应付金额无效");
        }
        Order request = paymentRequest(body);
        order.setPayment_method(requestedMethod);

        int requestedBalanceFen;
        try {
            if (PaymentChannelCatalog.NAME_COMBINED_PAY.equals(requestedMethod)) {
                validateCombinedCapabilities(shopId, request);
                OrderPayChannelAmounts.applyOnlineCombined(order, request, payable);
                requestedBalanceFen = fen(order.getPay_amount_balance());
            } else {
                Double cashAmount = number(body, "cash_amount", "cashAmount",
                        "checkout_cash_amount", "checkoutCashAmount",
                        "pay_cash_amount", "payCashAmount");
                if (cashAmount == null) {
                    cashAmount = request.getPay_amount_cash();
                }
                if (cashAmount != null && cashAmount > 0d) {
                    OrderPayChannelAmounts.applyFromPaymentMethodLabelWithOptionalCash(
                            order, requestedMethod, payable, cashAmount);
                } else {
                    OrderPayChannelAmounts.applyFromPaymentMethodLabel(order, requestedMethod, payable);
                }
                requestedBalanceFen = PaymentChannelCatalog.NAME_BALANCE_PAY.equals(requestedMethod)
                        ? (int) Math.round(payable * 100d) : 0;
            }
        } catch (IllegalArgumentException ex) {
            return R.error(ex.getMessage());
        }

        OrderCheckoutChangeHelper.fillFromMap(order, body);
        OrderCheckoutChangeHelper.ResolvedChange change =
                new OrderCheckoutChangeHelper.ResolvedChange();
        String changeError = OrderCheckoutChangeHelper.validateAndResolve(
                order, nz(order.getPay_amount_cash()), change);
        if (changeError != null) {
            return R.error(changeError);
        }

        boolean force = isForceCheckout(body);
        Integer[] authorizedAdminIdOut = new Integer[1];
        if (force) {
            R permError = checkForceCheckoutPermission(shopId, body, authorizedAdminIdOut);
            if (permError != null) {
                return permError;
            }
        }

        if (nativeAttemptMapper != null) {
            com.lanf.payment.entity.WechatNativePaymentAttemptEntity activeAttempt = nativeAttemptMapper.selectOne(
                    new QueryWrapper<com.lanf.payment.entity.WechatNativePaymentAttemptEntity>()
                            .eq("shop_id", shopId)
                            .eq("order_no", orderNo)
                            .eq("status", "ACTIVE")
                            .gt("expires_at", new Date())
                            .last("LIMIT 1"));
            if (activeAttempt != null && !force) {
                return R.error(40935, "该订单正在进行微信扫码支付中，请先在收银端关闭支付二维码或确认顾客未付款");
            }
        }

        int cashFen = fen(order.getPay_amount_cash());
        if (cashFen > 0) {
            Shop shop = shopService != null ? shopService.getById(shopId) : null;
            if (shop != null && Integer.valueOf(1).equals(shop.getShift_required())) {
                String terminalId = text(body, "terminal_id", "terminalId");
                Long drawerSessionId = longVal(body, "drawer_session_id", "drawerSessionId");
                DrawerSession activeSession = null;
                if (drawerSessionId != null && drawerSessionService != null) {
                    activeSession = drawerSessionService.getById(drawerSessionId);
                    if (activeSession != null && !DrawerSession.STATE_OPEN.equals(activeSession.getState())
                            && !DrawerSession.STATE_CLOSING.equals(activeSession.getState())) {
                        activeSession = null;
                    }
                }
                if (activeSession == null && drawerSessionService != null) {
                    try {
                        activeSession = drawerSessionService.getActiveSession(shopId, terminalId, null);
                    } catch (Exception ignored) {}
                }
                if (activeSession == null && !force) {
                    return R.error(4002, "当前钱箱未开班，请先完成开班后再进行现金收银");
                }
            }
        }

        String collectionSessionId = text(
                body, "collection_session_id", "collectionSessionId", "session_id");
        try {
            collectionIntentService.validateCheckout(
                    shopId,
                    orderNo,
                    collectionSessionId,
                    fen(order.getPay_amount_wechat()),
                    fen(order.getPay_amount_alipay()),
                    force);
        } catch (IllegalArgumentException | IllegalStateException ex) {
            return R.error(ex.getMessage());
        }

        User payer = null;
        int principalFen = 0;
        int giftFen = 0;
        if (requestedBalanceFen > 0) {
            int payableFen = (int) Math.round(payable * 100d);
            if (requestedBalanceFen == payableFen && hasDiscountOrCoupon(order)) {
                return R.error("当前订单已使用优惠或优惠券，不能使用全额余额支付");
            }
            R identityError = resolveAndValidatePayer(order, body);
            if (!Integer.valueOf(0).equals(identityError.get("code"))) {
                return identityError;
            }
            payer = (User) identityError.get("payer");
            BigDecimal requestedBalanceBd = UserWalletSplitUtil.fenToYuanBd(requestedBalanceFen);
            if (shopMemberWalletService != null && !shopMemberWalletService.isCrossShopBalanceEnabled(shopId)) {
                BigDecimal storeBal = shopMemberWalletService.getAvailableBalanceForShop(payer.getId(), shopId);
                if (storeBal.compareTo(requestedBalanceBd) < 0) {
                    return R.error("本店会员储值余额不足（您在其他门店的充值余额不可跨店使用）");
                }
            }
            int availablePrincipalFen = UserWalletSplitUtil.yuanToFen(nz(payer.getPrincipal_balance()));
            int availableGiftFen = UserWalletSplitUtil.yuanToFen(nz(payer.getGift_balance()));
            int[] split;
            try {
                split = UserWalletSplitUtil.splitConsumptionFen(
                        requestedBalanceFen, availablePrincipalFen, availableGiftFen);
            } catch (IllegalArgumentException | IllegalStateException ex) {
                return R.error("余额不足");
            }
            principalFen = split[0];
            giftFen = split[1];
            if (!userService.subtractBalanceSplitIfEnough(
                    payer.getId(), UserWalletSplitUtil.fenToYuanBd(principalFen),
                    UserWalletSplitUtil.fenToYuanBd(giftFen))) {
                return R.error("余额不足");
            }
            if (shopMemberWalletService != null) {
                shopMemberWalletService.deductAndClearBalance(
                        payer.getId(), shopId, UserWalletSplitUtil.fenToYuanBd(principalFen),
                        UserWalletSplitUtil.fenToYuanBd(giftFen), orderNo);
            }
            order.setPay_openid(payer.getOpenid());
            order.setBalance_pay_principal(yuan(principalFen));
            order.setBalance_pay_gift_wallet(yuan(giftFen));
            order.setPay_amount_balance(yuan(principalFen));
            order.setPay_amount_gift(yuan(giftFen));
            order.setTransaction_id((PaymentChannelCatalog.NAME_COMBINED_PAY.equals(requestedMethod)
                    ? "CASHIER_COMBINED_" : "BAL_CASHIER_") + orderNo);
        }

        OrderCheckoutChangeHelper.applyToOrder(order, change);

        order.setTransac_status("success");
        order.setPay_time(new Date());
        order.setHang_status(0);
        order.setHang_time(null);
        order.setHang_reason(null);
        order.setHang_admin_id(null);
        Integer checkoutCashierId = intVal(body, "cashier_id", "cashierId", "operator_id", "operatorId", "admin_id", "adminId");
        if (checkoutCashierId == null && httpServletRequest != null) {
            Object attr = httpServletRequest.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
            if (attr instanceof Integer) {
                checkoutCashierId = (Integer) attr;
            } else if (attr instanceof Number) {
                checkoutCashierId = ((Number) attr).intValue();
            } else if (attr != null) {
                try {
                    checkoutCashierId = Integer.parseInt(attr.toString().trim());
                } catch (NumberFormatException ignored) {}
            }
        }
        if (checkoutCashierId != null) {
            order.setCashier_id(checkoutCashierId);
        }
        if (writeMerchantId) {
            order.setMerchantId("1");
        }
        // 不可变资金流水是结算权威：先落流水，再更新订单成功状态；同一事务内任一步失败全部回滚。
        recordPaymentLedger(order, shopId, body, requestedMethod);
        if (!orderService.updateById(order)) {
            throw new IllegalStateException("订单结账状态更新失败");
        }
        markCouponUsed(order);
        updateTableAfterCheckout(order, shopId);
        if (force) {
            collectionIntentService.completeAllForOrder(shopId, orderNo);
            if (securityAuditService != null) {
                Integer adminId = authorizedAdminIdOut[0];
                Map<String, Object> auditDetails = new LinkedHashMap<>();
                auditDetails.put("orderNo", orderNo);
                auditDetails.put("shopId", shopId);
                auditDetails.put("paymentMethod", requestedMethod);
                auditDetails.put("payableYuan", payable);
                auditDetails.put("action", "FORCE_CHECKOUT");
                securityAuditService.recordPrivilegedAction(
                        httpServletRequest,
                        shopId,
                        "cashier",
                        "FORCE_CHECKOUT",
                        orderNo,
                        adminId,
                        auditDetails,
                        "强制结账放行意向并完成入账");
            }
        } else {
            collectionIntentService.complete(shopId, orderNo, collectionSessionId);
        }
        if (PaymentDiningTypeUtil.isPackOrDeliveryType(order.getDineInOrTakeOut())) {
            double paidYuan = payable;
            AfterCommitExecutor.execute("cashier_checkout_fulfillment:" + orderNo,
                    () -> paymentSuccessHandler.run(order, paidYuan));
        } else if ("堂食".equals(order.getDineInOrTakeOut())) {
            // 堂食收银/个人收款结账：补打结账单（核销/清台已在上方完成；下单时已打前台小票，此为结账凭证）
            AfterCommitExecutor.execute("cashier_checkout_print:" + orderNo,
                    () -> paymentSuccessHandler.printDineInTicket(order));
        }
        R res = success(order, false, payer);
        if (force) {
            res.put("forced", true);
        }
        return res;
    }

    @Transactional(isolation = Isolation.READ_COMMITTED, rollbackFor = Exception.class)
    public R unCheckout(Integer shopId, String orderNo) {
        if (shopId == null || shopId <= 0) {
            return R.error(4001, "缺少门店上下文");
        }
        if (!StringUtils.hasText(orderNo)) {
            return R.error("订单号不能为空");
        }
        Order order = lockOrder(orderNo.trim(), shopId);
        if (order == null) {
            return R.error("订单不存在或不属于当前门店");
        }
        normalizeLegacyDiningType(order);
        if (!"success".equalsIgnoreCase(order.getTransac_status())) {
            return R.ok().put("alreadyUnChecked", true);
        }

        // 已日结营业日不可变：禁止反结账
        Shop shop = shopService != null ? shopService.getById(shopId) : null;
        Date refDate = order.getPay_time() != null ? order.getPay_time() : order.getOrder_time();
        if (refDate != null && shop != null) {
            LocalDate bizDay;
            try {
                LocalDateTime ldt = refDate.toInstant().atZone(ZoneId.of("Asia/Shanghai")).toLocalDateTime();
                bizDay = ShopBusinessWindowResolver.operationalBusinessDay(shop, ldt);
            } catch (Exception ignored) {
                java.time.LocalTime settle = ShopBusinessWindowResolver.resolveSettleTimeOrDefault(shop);
                LocalDateTime ldt = refDate.toInstant().atZone(ZoneId.of("Asia/Shanghai")).toLocalDateTime();
                bizDay = ldt.toLocalTime().isBefore(settle) ? ldt.toLocalDate().minusDays(1) : ldt.toLocalDate();
            }

            boolean isDaySettled = (dailyCloseSnapshotMapper != null && dailyCloseSnapshotMapper.selectCount(
                    new QueryWrapper<com.lanf.entity.DailyCloseSnapshot>()
                            .eq("shop_id", shopId)
                            .eq("business_day", bizDay)
                            .eq("state", com.lanf.entity.DailyCloseSnapshot.STATE_CLOSED)) > 0)
                    || (dailyStatService != null && dailyStatService.count(
                    new QueryWrapper<com.lanf.entity.DailyStat>()
                            .eq("stat_date", bizDay)
                            .and(w -> w.eq("shop_id", shopId).or().isNull("shop_id"))) > 0);

            if (isDaySettled) {
                return R.error(40936, "该订单所属营业日已完成日结封账，禁止反结账");
            }
        }

        int principalFen = fen(order.getBalance_pay_principal());
        int giftFen = fen(order.getBalance_pay_gift_wallet());
        int externalFen = fen(order.getPay_amount_cash())
                + fen(order.getPay_amount_wechat())
                + fen(order.getPay_amount_alipay());
        if (externalFen > 0) {
            return R.error("订单包含现金或人工扫码实收，须先完成线下退款与账务核对，不能直接反结账");
        }
        List<PaymentLedger> reversals = paymentLedgerService.recordReversal(
                order,
                null,
                "REV_" + orderNo + "_" + System.currentTimeMillis(),
                null,
                "反结账全额冲正"
        );
        if (principalFen + giftFen > 0) {
            User payer = findPayer(order);
            if (payer == null || payer.getId() == null) {
                throw new IllegalStateException("余额付款用户不存在，无法反结账");
            }
            if (!userService.addBalanceAndGift(payer.getId(),
                    UserWalletSplitUtil.fenToYuanBd(principalFen),
                    UserWalletSplitUtil.fenToYuanBd(giftFen))) {
                throw new IllegalStateException("余额退回失败");
            }
        }

        order.setTransac_status("unsettled");
        order.setPay_time(null);
        order.setPayment_method(null);
        order.setPay_openid(null);
        order.setTransaction_id(null);
        OrderPayChannelAmounts.clear(order);
        OrderCheckoutChangeHelper.clear(order);
        if (!orderService.updateById(order)) {
            throw new IllegalStateException("订单反结账状态更新失败");
        }
        if (drawerSessionService != null && reversals != null) {
            for (PaymentLedger rev : reversals) {
                if (PaymentLedger.CHANNEL_CASH.equals(rev.getChannel())) {
                    drawerSessionService.recordCashRefund(
                            shopId,
                            null,
                            null,
                            order,
                            rev,
                            Math.abs(rev.getAmount_fen()),
                            null,
                            "反结账现金冲正"
                    );
                }
            }
        }
        restoreTable(order, shopId);
        return R.ok().put("restored_balance", yuan(principalFen + giftFen));
    }

    /**
     * Restores the still-unrefunded wallet component of a balance/combined cashier payment.
     * The order lock makes duplicate and concurrent refund attempts credit at most once.
     */
    @Transactional(rollbackFor = Exception.class)
    public R refundWalletComponent(String orderNo, Map<String, Object> params) {
        return refundWalletComponent(orderNo, params, null);
    }

    @Transactional(rollbackFor = Exception.class)
    public R refundWalletComponent(
            String orderNo, Map<String, Object> params, Integer requiredShopId) {
        if (!StringUtils.hasText(orderNo)) {
            return R.error("订单号不能为空");
        }
        QueryWrapper<Order> query = new QueryWrapper<Order>().eq("order_no", orderNo.trim());
        if (requiredShopId != null) {
            query.eq("shop_id", requiredShopId);
        }
        Order order = orderService.getOne(query.last("LIMIT 1 FOR UPDATE"));
        if (order == null || !"success".equalsIgnoreCase(order.getTransac_status())) {
            return R.error("仅已支付订单可退款");
        }
        int principalRemainingFen = fen(order.getBalance_pay_principal());
        int giftRemainingFen = fen(order.getBalance_pay_gift_wallet());
        int walletRemainingFen = principalRemainingFen + giftRemainingFen;
        if (walletRemainingFen <= 0) {
            return R.ok().put("alreadyRefunded", true).put("refund_amount", 0d);
        }
        int requestedFen = walletRemainingFen;
        Double requested = number(params, "refundAmount", "refund_amount");
        if (requested != null) {
            if (!Double.isFinite(requested) || requested <= 0d) {
                return R.error("退款金额必须大于 0");
            }
            requestedFen = (int) Math.round(requested * 100d);
        }
        if (requestedFen > walletRemainingFen) {
            return R.error("退款金额超过剩余余额支付部分");
        }
        int[] restore = UserWalletSplitUtil.splitRefundFen(
                requestedFen, principalRemainingFen, giftRemainingFen);
        User payer = findPayer(order);
        if (payer == null || payer.getId() == null) {
            throw new IllegalStateException("余额付款用户不存在，无法退款");
        }
        int previousRefundedFen = fen(order.getRefund_amount());
        String requestId = text(params, "request_id", "requestId", "client_request_id", "clientRequestId");
        if (!StringUtils.hasText(requestId)) {
            requestId = "WALLET_REF_" + order.getOrder_no() + "_" + (previousRefundedFen + requestedFen);
        }
        String businessDay = resolveBusinessDay(order.getShop_id());
        if (restore[0] > 0) {
            paymentLedgerService.recordRefund(order, PaymentLedger.CHANNEL_BALANCE_PRINCIPAL,
                    restore[0], null, requestId, businessDay,
                    findOriginalPaymentId(order, PaymentLedger.CHANNEL_BALANCE_PRINCIPAL), null);
        }
        if (restore[1] > 0) {
            paymentLedgerService.recordRefund(order, PaymentLedger.CHANNEL_GIFT,
                    restore[1], null, requestId, businessDay,
                    findOriginalPaymentId(order, PaymentLedger.CHANNEL_GIFT), null);
        }
        if (!userService.addBalanceAndGift(payer.getId(),
                UserWalletSplitUtil.fenToYuanBd(restore[0]),
                UserWalletSplitUtil.fenToYuanBd(restore[1]))) {
            throw new IllegalStateException("余额退款入账失败");
        }
        order.setRefund_amount(yuan(previousRefundedFen + requestedFen));
        OrderPayChannelAmounts.applyBalanceRefundFromSplitFen(order, restore);
        if (!orderService.updateById(order)) {
            throw new IllegalStateException("余额退款订单更新失败");
        }
        User remaining = userService.getById(payer.getId());
        return R.ok().put("order_no", orderNo)
                .put("refund_amount", yuan(requestedFen))
                .put("refund_balance_principal", yuan(restore[0]))
                .put("refund_balance_gift", yuan(restore[1]))
                .put("remaining_balance", remaining != null ? nz(remaining.getBalance()) : null);
    }

    /**
     * Persists WeChat refund notification idempotency on the locked order row.
     * The marker survives restarts and works across application instances.
     */
    @Transactional(rollbackFor = Exception.class)
    public R applyWechatRefundNotification(
            String orderNo, String refundKey, int refundFen) {
        if (!StringUtils.hasText(orderNo)
                || !StringUtils.hasText(refundKey)
                || refundFen <= 0) {
            return R.error("退款通知参数无效");
        }
        Order order = orderService.getOne(new QueryWrapper<Order>()
                .eq("order_no", orderNo.trim()).last("LIMIT 1 FOR UPDATE"));
        if (order == null) {
            return R.error("订单不存在");
        }
        if (!paymentRefundLedger.beginCallback(
                order.getShop_id(), order.getOrder_no(), refundKey.trim(), refundFen)) {
            return R.ok().put("idempotent", true).put("order", order).put("applied_fen", 0);
        }

        double paidYuan = nz(order.getSett_amount())
                + nz(order.getService_fee())
                - nz(order.getDiscount_amount());
        int totalPaidFen = (int) Math.round(paidYuan * 100d);
        int previousRefundedFen = fen(order.getRefund_amount());
        int remainingFen = Math.max(0, totalPaidFen - previousRefundedFen);
        int channelFen = OrderPayChannelAmounts.totalPayChannelAmountFen(order);
        int applyFen = Math.min(refundFen, remainingFen);
        if (channelFen > 0) {
            applyFen = Math.min(applyFen, channelFen);
        }

        if (applyFen > 0) {
            paymentLedgerService.recordRefund(
                    order, PaymentLedger.CHANNEL_WECHAT, applyFen, null,
                    "REF_" + refundKey.trim(), resolveBusinessDay(order.getShop_id()),
                    findOriginalPaymentId(order, PaymentLedger.CHANNEL_WECHAT), refundKey.trim());
            order.setRefund_amount(yuan(previousRefundedFen + applyFen));
            OrderPayChannelAmounts.applyRefundDeltaProportional(order, yuan(applyFen));
        }
        if (!orderService.updateById(order)) {
            throw new IllegalStateException("退款通知订单更新失败");
        }
        paymentRefundLedger.markSuccess(refundKey.trim(), applyFen);
        return R.ok()
                .put("idempotent", false)
                .put("order", order)
                .put("applied_fen", applyFen)
                .put("full_refund", previousRefundedFen + applyFen >= totalPaidFen);
    }

    @Transactional(rollbackFor = Exception.class)
    public R refundCashComponent(Integer shopId, Map<String, Object> body) {
        if (shopId == null || shopId <= 0) {
            return R.error(4001, "缺少门店上下文");
        }
        String orderNo = text(body, "order_no", "orderNo");
        if (!StringUtils.hasText(orderNo)) {
            return R.error("订单号不能为空");
        }
        Order order = lockOrder(orderNo, shopId);
        if (order == null) {
            return R.error("订单不存在或不属于当前门店");
        }
        if (!"success".equalsIgnoreCase(order.getTransac_status())) {
            return R.error("仅已支付订单可人工退款");
        }
        int totalFen = fen(nz(order.getSett_amount()) + nz(order.getService_fee()) - nz(order.getDiscount_amount()));
        int alreadyRefundedFen = fen(order.getRefund_amount());
        int remainingFen = Math.max(0, totalFen - alreadyRefundedFen);
        int cashRemainingFen = fen(order.getPay_amount_cash());
        if (remainingFen <= 0) return R.error("无可退金额");
        if (cashRemainingFen <= 0) return R.error("订单无现金渠道可退（现金列已清零），请核对实收");

        int refundFen = Math.min(remainingFen, cashRemainingFen);
        Double requested = number(body, "refundAmount", "refund_amount");
        if (requested != null) {
            if (!Double.isFinite(requested)) return R.error("退款金额格式错误");
            refundFen = fen(requested);
        }
        if (refundFen <= 0 || refundFen > remainingFen) {
            return R.error("退款金额不合法（需大于0且不超过剩余可退金额）");
        }
        if (refundFen > cashRemainingFen) {
            return R.error("退款金额超过订单现金渠道剩余，请核对实收");
        }

        String requestId = text(body, "request_id", "requestId", "client_request_id", "clientRequestId");
        if (!StringUtils.hasText(requestId)) {
            requestId = "CASH_REF_" + orderNo + "_" + (alreadyRefundedFen + refundFen);
        }
        Integer operatorId = intVal(body, "operator_id", "operatorId", "admin_id", "adminId");
        paymentLedgerService.recordRefund(
                order, PaymentLedger.CHANNEL_CASH, refundFen, operatorId,
                requestId, resolveBusinessDay(shopId),
                findOriginalPaymentId(order, PaymentLedger.CHANNEL_CASH), null);

        order.setRefund_amount(yuan(alreadyRefundedFen + refundFen));
        order.setPay_amount_cash(yuan(cashRemainingFen - refundFen));
        String reason = text(body, "reason", "remark");
        String oldRemark = order.getRemark() != null ? order.getRemark() : "";
        String refundTag = "【人工退款·现金】" + yuan(refundFen) + "元"
                + (StringUtils.hasText(reason) ? "（" + reason.trim() + "）" : "")
                + "，累计退款" + order.getRefund_amount() + "元";
        if (!oldRemark.contains(refundTag)) {
            order.setRemark(oldRemark + (oldRemark.isEmpty() ? "" : "；") + refundTag);
        }
        if (!orderService.updateById(order)) {
            throw new IllegalStateException("人工退款订单更新失败");
        }
        return R.ok().put("order_no", orderNo)
                .put("refund_amount", yuan(refundFen))
                .put("refund_total", order.getRefund_amount())
                .put("cash_remaining", order.getPay_amount_cash())
                .put("message", "人工退款已入账");
    }

    private Order lockOrder(String orderNo, Integer shopId) {
        return orderService.getOne(new QueryWrapper<Order>()
                .eq("order_no", orderNo.trim())
                .eq("shop_id", shopId)
                .last("LIMIT 1 FOR UPDATE"));
    }

    private Long findOriginalPaymentId(Order order, String channel) {
        List<PaymentLedger> ledgers = paymentLedgerService.listByOrder(order.getShop_id(), order.getOrder_no());
        PaymentLedger latest = null;
        if (ledgers != null) {
            for (PaymentLedger ledger : ledgers) {
                if (!PaymentLedger.ENTRY_TYPE_PAYMENT.equals(ledger.getEntry_type())
                        || !PaymentLedger.STATUS_SUCCEEDED.equals(ledger.getStatus())
                        || !Objects.equals(channel, ledger.getChannel())) {
                    continue;
                }
                if (StringUtils.hasText(order.getTransaction_id())
                        && order.getTransaction_id().equals(ledger.getProvider_transaction_id())) {
                    return ledger.getId();
                }
                if (latest == null || (ledger.getId() != null
                        && (latest.getId() == null || ledger.getId() > latest.getId()))) {
                    latest = ledger;
                }
            }
        }
        return latest != null ? latest.getId() : null;
    }

    private String resolveBusinessDay(Integer shopId) {
        try {
            Shop shop = shopService != null && shopId != null ? shopService.getById(shopId) : null;
            if (shop != null) {
                return ShopBusinessWindowResolver.operationalBusinessDay(shop).toString();
            }
        } catch (Exception ignored) {
        }
        return java.time.LocalDate.now().toString();
    }

    private R resolveAndValidatePayer(Order order, Map<String, Object> body) {
        String submittedOpenid = text(
                body, "openid", "pay_openid", "payOpenid", "member_openid", "memberOpenid");
        String phone = text(body, "member_phone", "memberPhone", "phone");
        String orderOpenid = memberOpenid(order.getOpenid());
        String payOpenid = memberOpenid(order.getPay_openid());
        if (StringUtils.hasText(orderOpenid) && StringUtils.hasText(payOpenid)
                && !Objects.equals(orderOpenid, payOpenid)) {
            return R.error("订单会员与付款会员不匹配");
        }
        String lockedOpenid = StringUtils.hasText(payOpenid) ? payOpenid : orderOpenid;
        if (StringUtils.hasText(submittedOpenid) && StringUtils.hasText(lockedOpenid)
                && !Objects.equals(submittedOpenid.trim(), lockedOpenid)) {
            return R.error("提交的会员 openid 与订单不匹配");
        }
        String resolvedOpenid = StringUtils.hasText(submittedOpenid)
                ? submittedOpenid.trim() : lockedOpenid;
        if (!StringUtils.hasText(resolvedOpenid)) {
            return R.error("余额支付缺少可识别的会员 openid");
        }
        User payer = userService.getUserByOpenid(resolvedOpenid);
        if (payer == null || payer.getId() == null) {
            return R.error("会员不存在");
        }
        if (!StringUtils.hasText(payer.getOpenid())
                || !Objects.equals(resolvedOpenid, payer.getOpenid().trim())) {
            return R.error("会员 openid 绑定异常");
        }
        if (!StringUtils.hasText(payer.getPhone())) {
            return R.error("会员账户未绑定手机号，无法使用余额支付");
        }
        if (StringUtils.hasText(phone) && !Objects.equals(phone.trim(), trim(payer.getPhone()))) {
            return R.error("会员手机号与 openid 不匹配");
        }
        if (StringUtils.hasText(order.getMember_phone())
                && !Objects.equals(trim(order.getMember_phone()), trim(payer.getPhone()))) {
            return R.error("订单会员手机号与付款会员不匹配");
        }
        return R.ok().put("payer", payer);
    }

    private static String memberOpenid(String value) {
        if (!StringUtils.hasText(value)) {
            return null;
        }
        String normalized = value.trim();
        return CASHIER_OPENID.equals(normalized) ? null : normalized;
    }

    private void validateCombinedCapabilities(Integer shopId, Order request) {
        if (fen(request.getPay_amount_cash()) > 0
                && !paymentCapabilityService.isCashierPaymentMethodEnabled(
                shopId, PaymentChannelCatalog.CASH)) {
            throw new IllegalArgumentException("当前门店未启用组合支付中的现金支付");
        }
        if (fen(request.getPay_amount_wechat()) > 0
                && !paymentCapabilityService.isCashierPaymentMethodEnabled(
                shopId, PaymentChannelCatalog.ONLINE_WECHAT)) {
            throw new IllegalArgumentException("当前门店未启用组合支付中的微信支付");
        }
        if (fen(request.getPay_amount_alipay()) > 0
                && !paymentCapabilityService.isCashierPaymentMethodEnabled(
                shopId, PaymentChannelCatalog.ONLINE_ALIPAY)) {
            throw new IllegalArgumentException("当前门店未启用组合支付中的支付宝支付");
        }
        if (fen(request.getPay_amount_balance()) > 0
                && !paymentCapabilityService.isCashierPaymentMethodEnabled(
                shopId, PaymentChannelCatalog.ONLINE_BALANCE)) {
            throw new IllegalArgumentException("当前门店未启用组合支付中的余额支付");
        }
    }

    private boolean hasDiscountOrCoupon(Order order) {
        if (nz(order.getDiscount_amount()) > 0d) {
            return true;
        }
        return userCouponMapper != null && userCouponMapper.selectCount(new QueryWrapper<UserCoupon>()
                .eq("order_no", order.getOrder_no())) > 0;
    }

    private void markCouponUsed(Order order) {
        UserCoupon coupon = userCouponMapper.selectOne(new QueryWrapper<UserCoupon>()
                .eq("order_no", order.getOrder_no()).last("LIMIT 1"));
        if (coupon != null && !Integer.valueOf(1).equals(coupon.getStatus())) {
            coupon.setStatus(1);
            coupon.setUse_time(new Date());
            if (userCouponMapper.updateById(coupon) != 1) {
                throw new IllegalStateException("优惠券核销失败");
            }
        }
    }

    private void updateTableAfterCheckout(Order order, Integer shopId) {
        if (!Objects.equals(order.getDineInOrTakeOut(), DINE_IN)) {
            return;
        }
        Table table = tableService.getOne(new QueryWrapper<Table>()
                .eq("number", order.getTable_number()).eq("shop_id", shopId).last("LIMIT 1 FOR UPDATE"));
        if (table == null) {
            throw new IllegalStateException("堂食订单桌台不存在");
        }
        List<Order> remaining = orderService.list(new QueryWrapper<Order>()
                .eq("shop_id", shopId).eq("table_number", order.getTable_number())
                .eq("transac_status", "unsettled").orderByAsc("id"));
        if (remaining.isEmpty()) {
            table.setStatus(2);
            table.setOut_time(new Date());
            table.setOrder_no(order.getOrder_no());
            table.setAmount(OrderNetRevenue.netRevenueYuan(order));
        } else {
            table.setStatus(1);
            table.setOut_time(null);
            table.setOrder_no(remaining.get(0).getOrder_no());
            table.setAmount(outstanding(remaining));
        }
        if (!tableService.updateById(table)) {
            throw new IllegalStateException("桌台结账状态更新失败");
        }
    }

    private void restoreTable(Order order, Integer shopId) {
        if (!Objects.equals(order.getDineInOrTakeOut(), DINE_IN)) {
            return;
        }
        Table table = tableService.getOne(new QueryWrapper<Table>()
                .eq("number", order.getTable_number()).eq("shop_id", shopId).last("LIMIT 1 FOR UPDATE"));
        if (table == null) {
            throw new IllegalStateException("堂食订单桌台不存在");
        }
        List<Order> unsettled = orderService.list(new QueryWrapper<Order>()
                .eq("shop_id", shopId).eq("table_number", order.getTable_number())
                .eq("transac_status", "unsettled").orderByAsc("id"));
        table.setStatus(1);
        table.setOut_time(null);
        table.setOrder_no(unsettled.isEmpty() ? order.getOrder_no() : unsettled.get(0).getOrder_no());
        table.setAmount(outstanding(unsettled));
        if (!tableService.updateById(table)) {
            throw new IllegalStateException("桌台反结账状态更新失败");
        }
    }

    private static void normalizeLegacyDiningType(Order order) {
        String diningType = order.getDineInOrTakeOut();
        if (diningType == null) {
            return;
        }
        String normalized = diningType.trim();
        if (DINE_IN.equals(normalized) || LEGACY_DINE_IN.equals(normalized)) {
            order.setDineInOrTakeOut(DINE_IN);
        } else if (TAKE_OUT.equals(normalized)
                || LEGACY_TAKE_OUT.equals(normalized)
                || LEGACY_TAKE_AWAY.equals(normalized)
                || "自提".equals(normalized)
                || "打包自提".equals(normalized)
                || "pickup".equalsIgnoreCase(normalized)
                || "pack".equalsIgnoreCase(normalized)) {
            order.setDineInOrTakeOut(TAKE_OUT);
        }
    }

    private R success(Order order, boolean idempotent, User payer) {
        Map<String, Object> split = new LinkedHashMap<>();
        split.put("wechat", nz(order.getPay_amount_wechat()));
        split.put("alipay", nz(order.getPay_amount_alipay()));
        split.put("cash", nz(order.getPay_amount_cash()));
        split.put("balance", yuan(fen(order.getPay_amount_balance()) + fen(order.getPay_amount_gift())));
        split.put("balance_principal", nz(order.getBalance_pay_principal()));
        split.put("balance_gift", nz(order.getBalance_pay_gift_wallet()));
        R result = R.ok().put("order_no", order.getOrder_no())
                .put("idempotent", idempotent)
                .put("payment_method", order.getPayment_method())
                .put("payment_channel_code", PaymentChannelCatalog.codeFromPaymentMethod(order.getPayment_method()))
                .put("payableYuan", OrderNetRevenue.netRevenueYuan(order))
                .put("split", split);
        User fresh = payer != null ? userService.getById(payer.getId()) : findPayer(order);
        if (fresh != null) {
            result.put("remaining_balance", nz(fresh.getBalance()))
                    .put("remaining_principal_balance", nz(fresh.getPrincipal_balance()))
                    .put("remaining_gift_balance", nz(fresh.getGift_balance()));
        }
        return result;
    }

    private User findPayer(Order order) {
        String openid = StringUtils.hasText(order.getPay_openid())
                ? order.getPay_openid().trim() : null;
        return openid == null ? null : userService.getUserByOpenid(openid);
    }

    private static Order paymentRequest(Map<String, Object> body) {
        Order request = new Order();
        request.setPay_amount_wechat(number(body, "pay_amount_wechat", "payAmountWechat"));
        request.setPay_amount_alipay(number(body, "pay_amount_alipay", "payAmountAlipay"));
        request.setPay_amount_balance(number(body, "pay_amount_balance", "payAmountBalance"));
        request.setPay_amount_cash(number(body, "pay_amount_cash", "payAmountCash"));
        return request;
    }

    private static double outstanding(List<Order> orders) {
        double total = 0d;
        for (Order order : orders) {
            total += OrderNetRevenue.netRevenueYuan(order);
        }
        return Math.round(total * 100d) / 100d;
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
            double parsed = Double.parseDouble(value);
            return Double.isFinite(parsed) ? parsed : Double.NaN;
        } catch (NumberFormatException ex) {
            return Double.NaN;
        }
    }

    private static int fen(Double value) {
        if (value == null || !Double.isFinite(value)) return 0;
        return (int) Math.round(value * 100d);
    }

    private static double yuan(int fen) {
        return BigDecimal.valueOf(fen, 2).doubleValue();
    }

    private static double nz(Double value) {
        return value == null ? 0d : value;
    }

    private static BigDecimal nz(BigDecimal value) {
        return value == null ? BigDecimal.ZERO.setScale(2) : value.setScale(2, RoundingMode.HALF_UP);
    }

    private static String trim(String value) {
        return value == null ? "" : value.trim();
    }

    private static String defaultText(String value, String fallback) {
        return StringUtils.hasText(value) ? value : fallback;
    }

    private void recordPaymentLedger(Order order, Integer shopId, Map<String, Object> body, String requestedMethod) {
        int cashFen = fen(order.getPay_amount_cash());
        int wechatFen = fen(order.getPay_amount_wechat());
        int alipayFen = fen(order.getPay_amount_alipay());
        int balanceFen = fen(order.getPay_amount_balance());
        int giftFen = fen(order.getPay_amount_gift());

        Map<String, Integer> channelAmountsFen = new LinkedHashMap<>();
        if (cashFen > 0) channelAmountsFen.put(PaymentLedger.CHANNEL_CASH, cashFen);
        if (wechatFen > 0) {
            channelAmountsFen.put(
                    PaymentChannelCatalog.ledgerChannel(requestedMethod, PaymentLedger.CHANNEL_WECHAT),
                    wechatFen);
        }
        if (alipayFen > 0) {
            channelAmountsFen.put(
                    PaymentChannelCatalog.ledgerChannel(requestedMethod, PaymentLedger.CHANNEL_ALIPAY),
                    alipayFen);
        }
        if (balanceFen > 0) channelAmountsFen.put(PaymentLedger.CHANNEL_BALANCE_PRINCIPAL, balanceFen);
        if (giftFen > 0) channelAmountsFen.put(PaymentLedger.CHANNEL_GIFT, giftFen);

        int payableFen = OrderNetRevenue.netRevenueFen(order);
        if (channelAmountsFen.isEmpty() && payableFen == 0) {
            channelAmountsFen.put(PaymentLedger.CHANNEL_OTHER, 0);
        } else if (channelAmountsFen.isEmpty() && payableFen > 0) {
            String ch = mapMethodToChannel(requestedMethod);
            channelAmountsFen.put(ch, payableFen);
        }

        String requestId = text(body, "request_id", "requestId");
        if (!StringUtils.hasText(requestId)) {
            requestId = "REQ_" + order.getOrder_no() + "_" + (order.getPay_time() != null ? order.getPay_time().getTime() : System.currentTimeMillis());
        }
        Integer operatorId = intVal(body, "operator_id", "operatorId", "admin_id", "adminId");
        String terminalId = text(body, "terminal_id", "terminalId");
        Long drawerSessionId = longVal(body, "drawer_session_id", "drawerSessionId");
        Long employeeShiftId = longVal(body, "employee_shift_id", "employeeShiftId");

        if (drawerSessionId == null && drawerSessionService != null) {
            try {
                DrawerSession activeSession = drawerSessionService.getActiveSession(shopId, terminalId, null);
                if (activeSession != null) {
                    drawerSessionId = activeSession.getId();
                }
            } catch (Exception ignored) {
            }
        }

        String businessDay = text(body, "business_day", "businessDay", "stat_date", "statDate");
        if (!StringUtils.hasText(businessDay)) {
            try {
                Shop shop = shopService != null ? shopService.getById(shopId) : null;
                if (shop != null) {
                    businessDay = ShopBusinessWindowResolver.operationalBusinessDay(shop).toString();
                }
            } catch (Exception ignored) {
            }
        }
        if (!StringUtils.hasText(businessDay)) {
            businessDay = java.time.LocalDate.now().toString();
        }

        List<PaymentLedger> ledgers = paymentLedgerService.recordSettlement(
                order,
                operatorId,
                requestId,
                terminalId,
                drawerSessionId,
                employeeShiftId,
                businessDay,
                channelAmountsFen,
                order.getTransaction_id()
        );

        if (drawerSessionService != null && channelAmountsFen.containsKey(PaymentLedger.CHANNEL_CASH)) {
            int cashAmtFen = channelAmountsFen.get(PaymentLedger.CHANNEL_CASH);
            if (cashAmtFen > 0) {
                PaymentLedger cashLedger = null;
                if (ledgers != null) {
                    for (PaymentLedger pl : ledgers) {
                        if (PaymentLedger.CHANNEL_CASH.equals(pl.getChannel())) {
                            cashLedger = pl;
                            break;
                        }
                    }
                }
                drawerSessionService.recordCashSale(shopId, terminalId, null, order, cashLedger, cashAmtFen, operatorId);
            }
        }
    }

    private static String mapMethodToChannel(String method) {
        if (method == null) return PaymentLedger.CHANNEL_OTHER;
        String explicitQrChannel = PaymentChannelCatalog.ledgerChannel(method, null);
        if (explicitQrChannel != null) return explicitQrChannel;
        String m = method.trim().toLowerCase();
        if (m.contains("cash") || m.contains("现金")) return PaymentLedger.CHANNEL_CASH;
        if (m.contains("wechat") || m.contains("wx") || m.contains("微信")) return PaymentLedger.CHANNEL_WECHAT;
        if (m.contains("alipay") || m.contains("ali") || m.contains("支付宝")) return PaymentLedger.CHANNEL_ALIPAY;
        if (m.contains("balance") || m.contains("余额")) return PaymentLedger.CHANNEL_BALANCE_PRINCIPAL;
        if (m.contains("gift") || m.contains("赠送")) return PaymentLedger.CHANNEL_GIFT;
        return PaymentLedger.CHANNEL_OTHER;
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
}

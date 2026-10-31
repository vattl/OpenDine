package com.lanf.payment.facade;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.constant.MiniProgramAuthCodes;
import com.lanf.entity.*;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.payment.channel.wechat.WechatJsapiChannel;
import com.lanf.payment.service.PaymentOnlineGuardService;
import com.lanf.payment.service.WechatJsapiPaymentService;
import com.lanf.payment.settlement.PayableAmountContext;
import com.lanf.payment.settlement.PaymentSettlementService;
import com.lanf.payment.support.OrderPaymentBridge;
import com.lanf.payment.support.PaymentMerchantNoUtil;
import com.lanf.payment.support.PaymentNotifyState;
import com.lanf.payment.support.PaymentSettlementLedgerHelper;
import com.lanf.payment.support.WxRechargeGiftTierValidator;
import com.lanf.service.IMemberRechargeService;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.service.IUserService;
import com.lanf.service.WechatMiniProgramAuthService;
import com.lanf.util.OrderPayChannelAmounts;
import com.lanf.util.ShopChainSupport;
import com.lanf.util.UserWalletSplitUtil;
import com.lanf.util.AfterCommitExecutor;
import com.lanf.payment.service.PaymentNinefoldService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;
import javax.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Date;
import java.util.Map;

/**
 * C 端支付统一入口（P2）：getPrepayId / payByBalance / recharge。
 */
@Service
public class PaymentFacadeService {

    private static final Logger log = LoggerFactory.getLogger(PaymentFacadeService.class);
    private static final String PAYMENT_METHOD_BALANCE = "余额支付";
    private static final String BALANCE_TX_ID_PREFIX = "BAL_";

    @Autowired
    private PaymentOnlineGuardService paymentOnlineGuardService;
    @Autowired
    private PaymentSettlementService paymentSettlementService;
    @Autowired
    private OrderPaymentBridge orderPaymentBridge;
    @Autowired
    private WechatJsapiChannel wechatJsapiChannel;
    @Autowired
    private WechatJsapiPaymentService wechatJsapiPaymentService;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private IShopService shopService;
    @Autowired
    private IUserService userService;
    @Autowired
    private IMemberRechargeService memberRechargeService;
    @Autowired
    private UserCouponMapper userCouponMapper;
    @Autowired
    private PaymentNinefoldService paymentNinefoldService;
    @Autowired(required = false)
    private com.lanf.service.IShopMemberWalletService shopMemberWalletService;
    @Autowired
    private PaymentNotifyState paymentNotifyState;
    @Autowired
    private PaymentSettlementLedgerHelper paymentSettlementLedgerHelper;

    public R getPrepayId(Map<String, String> params) {
        String orderNo = params.get("orderNo");
        String openid = params.get("openid");
        String takeOut = params.get("takeOut");
        Long couponId = null;
        String couponIdStr = params.get("coupon_id");
        if (couponIdStr != null && !couponIdStr.trim().isEmpty()) {
            try {
                couponId = Long.parseLong(couponIdStr.trim());
            } catch (NumberFormatException ex) {
                return R.error("优惠券ID格式错误：" + couponIdStr);
            }
        }
        if (orderNo == null || orderNo.isEmpty()) {
            return R.error("订单号不能为空");
        }
        if (openid == null || openid.isEmpty()) {
            return R.error(MiniProgramAuthCodes.LOGIN_EXPIRED, "登录已过期，请重新登录");
        }
        orderNo = orderNo.trim();
        openid = openid.trim();
        Order order = orderService.getOne(new QueryWrapper<Order>().eq("order_no", orderNo));
        if (order != null) {
            R prepayGuard = paymentOnlineGuardService.checkWechatPay(order.getShop_id());
            if (prepayGuard != null) {
                return prepayGuard;
            }
        }
        if (order == null) {
            if (!PaymentMerchantNoUtil.isWxRechargeMerchantNo(orderNo)) {
                return R.error("订单不存在，无法支付");
            }
            MemberRecharge mr = memberRechargeService.getOne(new QueryWrapper<MemberRecharge>()
                    .eq("order_no", orderNo).eq("channel", "wechat").eq("status", "pending").last("LIMIT 1"));
            if (mr == null) {
                return R.error("充值记录不存在或已失效，无法支付");
            }
            R rechargePrepayGuard = paymentOnlineGuardService.checkWechatRecharge(mr.getShop_id());
            if (rechargePrepayGuard != null) {
                return rechargePrepayGuard;
            }
            String mrOpenid = mr.getOpenid() != null ? mr.getOpenid().trim() : "";
            if (!openid.equals(mrOpenid)) {
                return R.error("支付用户与充值记录不一致");
            }
            double paidYuan = mr.getRecharge_amount() != null ? mr.getRecharge_amount().doubleValue() : 0d;
            paidYuan = UserWalletSplitUtil.roundYuan(UserWalletSplitUtil.decimal(paidYuan));
            if (paidYuan <= 0d) {
                return R.error("充值金额异常，无法支付");
            }
            return wechatJsapiChannel.createPrepay(null, mr.getShop_id(), orderNo, openid, takeOut,
                    paidYuan, "1", "会员账户充值");
        }
        if ("success".equals(order.getTransac_status())) {
            return R.error("订单已支付");
        }
        if (!"unsettled".equals(order.getTransac_status())) {
            return R.error("订单状态异常，无法支付");
        }
        if (StringUtils.hasText(order.getMaster_order_no())) {
            return R.error("该订单为并台从单，不支持单独结账，请通过主桌统一结账");
        }
        long slaveCount = orderService.count(new QueryWrapper<Order>()
                .eq(order.getShop_id() != null, "shop_id", order.getShop_id())
                .eq("master_order_no", order.getOrder_no())
                .eq("transac_status", "unsettled"));
        if (slaveCount > 0) {
            return R.error("该桌台存在并台从单，不支持单笔结账，请通过主桌统一结账");
        }
        if (StringUtils.hasText(order.getOpenid()) && !order.getOpenid().trim().equals(openid)) {
            return R.error(403, "支付用户与订单绑定用户不一致");
        }
        return wechatJsapiPaymentService.create(orderNo, openid, couponId);
    }

    @Transactional(rollbackFor = Exception.class)
    public R payByBalance(Map<String, String> params) {
        String orderNo = params != null ? params.get("orderNo") : null;
        String openid = params != null ? params.get("openid") : null;
        Long couponId = null;
        if (params != null) {
            String couponIdStr = params.get("coupon_id");
            if (couponIdStr != null && !couponIdStr.trim().isEmpty()) {
                try {
                    couponId = Long.parseLong(couponIdStr.trim());
                } catch (NumberFormatException ex) {
                    return R.error("优惠券ID格式错误：" + couponIdStr);
                }
            }
        }
        if (!StringUtils.hasText(orderNo) || !StringUtils.hasText(openid)) {
            return R.error("订单号和openid不能为空");
        }
        orderNo = orderNo.trim();
        openid = openid.trim();
        synchronized (paymentNotifyState.lockFor(orderNo)) {
            Order order = orderService.getOne(new QueryWrapper<Order>()
                    .eq("order_no", orderNo).last("LIMIT 1 FOR UPDATE"));
            if (order == null) {
                return R.error("订单不存在");
            }
            R balanceGuard = paymentOnlineGuardService.checkBalancePay(order.getShop_id());
            if (balanceGuard != null) {
                return balanceGuard;
            }
            if ("success".equals(order.getTransac_status())) {
                return R.ok("订单已支付").put("alreadyPaid", true);
            }
            if (!"unsettled".equals(order.getTransac_status())) {
                return R.error("订单状态异常，无法支付");
            }
            if (StringUtils.hasText(order.getMaster_order_no())) {
                return R.error("该订单为并台从单，不支持单独结账，请通过主桌统一结账");
            }
            long slaveCount = orderService.count(new QueryWrapper<Order>()
                    .eq(order.getShop_id() != null, "shop_id", order.getShop_id())
                    .eq("master_order_no", order.getOrder_no())
                    .eq("transac_status", "unsettled"));
            if (slaveCount > 0) {
                return R.error("该桌台存在并台从单，不支持单笔结账，请通过主桌统一结账");
            }
            if (StringUtils.hasText(order.getOpenid()) && !order.getOpenid().trim().equals(openid)) {
                // 收银台下单（order_channel=cashier，openid 为 cashier_system 占位）放行：可由任意 C 端用户余额代付；
                // 小程序/外卖/AI 下单仅限本人余额支付，非本人提示咨询服务员
                boolean cashierOrder = "cashier".equalsIgnoreCase(order.getOrder_channel());
                if (!cashierOrder) {
                    return R.error("订单不一致，请咨询服务员");
                }
            }
            if (couponId != null && couponId > 0L) {
                return R.error("使用优惠券的订单不能使用余额支付，请改用微信支付");
            }
            long couponBoundToOrder = userCouponMapper.selectCount(
                    new QueryWrapper<UserCoupon>().eq("order_no", orderNo));
            if (couponBoundToOrder > 0L) {
                return R.error("使用优惠券的订单不能使用余额支付，请改用微信支付");
            }
            PayableAmountContext balanceCtx = new PayableAmountContext();
            R balancePrep = orderPaymentBridge.fillPayableAmountContext(order, couponId, openid, balanceCtx);
            Object balancePrepCode = balancePrep.get("code");
            if (balancePrepCode != null && !Integer.valueOf(0).equals(balancePrepCode)) {
                return balancePrep;
            }
            if (!balanceCtx.usesCouponForSettlement
                    && paymentNinefoldService.qualifiesForNineFold(
                    PaymentNinefoldService.resolveOrderShopId(order),
                    false, balanceCtx.nineFoldTimeRef, balanceCtx.basePaidYuan, balanceCtx.dineInOrTakeOut)) {
                return R.error("夜间九折优惠订单请使用微信支付，不可使用余额支付");
            }
            R settled = paymentSettlementService.settle(order, couponId, openid, false);
            Object codeObj = settled.get("code");
            if (codeObj != null && !Integer.valueOf(0).equals(codeObj)) {
                return settled;
            }
            Object py = settled.get("paidYuan");
            double paidYuan = py instanceof Number ? ((Number) py).doubleValue() : 0d;
            if (paidYuan <= 0d) {
                return R.error("折后实付金额异常，无法支付");
            }
            User payer = userService.getUserByOpenid(openid);
            if (payer == null || payer.getId() == null) {
                return R.error("用户不存在");
            }
            BigDecimal payAmt = BigDecimal.valueOf(paidYuan).setScale(2, RoundingMode.HALF_UP);
            BigDecimal principalAvail = payer.getPrincipal_balance() != null ? payer.getPrincipal_balance() : BigDecimal.ZERO;
            BigDecimal giftAvail = payer.getGift_balance() != null ? payer.getGift_balance() : BigDecimal.ZERO;
            BigDecimal totalAvail = principalAvail.add(giftAvail).setScale(2, RoundingMode.HALF_UP);
            if (totalAvail.compareTo(payAmt) < 0) {
                return R.error("余额不足");
            }
            Integer orderShopId = order.getShop_id() != null ? order.getShop_id() : 1;
            if (shopMemberWalletService != null && !shopMemberWalletService.isCrossShopBalanceEnabled(orderShopId)) {
                BigDecimal storeBal = shopMemberWalletService.getAvailableBalanceForShop(payer.getId(), orderShopId);
                if (storeBal.compareTo(payAmt) < 0) {
                    return R.error("本店会员储值余额不足（您在其他门店的充值余额不可跨店使用）");
                }
            }
            int payFen = UserWalletSplitUtil.yuanToFen(payAmt);
            int pFen = UserWalletSplitUtil.yuanToFen(principalAvail);
            int gFen = UserWalletSplitUtil.yuanToFen(giftAvail);
            int[] splitFen;
            try {
                splitFen = UserWalletSplitUtil.splitConsumptionFen(payFen, pFen, gFen);
            } catch (IllegalArgumentException | IllegalStateException ex) {
                return R.error("余额不足");
            }
            BigDecimal deductPrincipal = UserWalletSplitUtil.fenToYuanBd(splitFen[0]);
            BigDecimal deductGift = UserWalletSplitUtil.fenToYuanBd(splitFen[1]);
            if (!userService.subtractBalanceSplitIfEnough(payer.getId(), deductPrincipal, deductGift)) {
                return R.error("余额不足");
            }
            Order latest = orderService.getOne(new QueryWrapper<Order>()
                    .eq("order_no", orderNo).last("LIMIT 1 FOR UPDATE"));
            if (latest == null) {
                userService.addBalanceAndGift(payer.getId(), deductPrincipal, deductGift);
                return R.error("订单不存在");
            }
            if ("success".equals(latest.getTransac_status())) {
                userService.addBalanceAndGift(payer.getId(), deductPrincipal, deductGift);
                return R.error("订单状态已变更，请重试");
            }
            latest.setTransac_status("success");
            latest.setTransaction_id(BALANCE_TX_ID_PREFIX + orderNo);
            latest.setPayment_method(PAYMENT_METHOD_BALANCE);
            latest.setPay_openid(openid);
            latest.setPay_time(new Date());
            OrderPayChannelAmounts.applyBalanceWalletSplit(latest,
                    deductPrincipal.doubleValue(), deductGift.doubleValue());
            if (!StringUtils.hasText(latest.getOpenid())) {
                latest.setOpenid(openid);
            }
            if (!StringUtils.hasText(latest.getMerchantId())) {
                latest.setMerchantId("1");
            }
            paymentSettlementLedgerHelper.recordAuthoritativePayment(
                    latest, null, null, BALANCE_TX_ID_PREFIX + orderNo);
            if (!orderService.updateById(latest)) {
                throw new IllegalStateException("余额支付订单状态更新失败");
            }
            if (shopMemberWalletService != null) {
                shopMemberWalletService.deductAndClearBalance(
                        payer.getId(), orderShopId, deductPrincipal, deductGift, orderNo);
            }
            log.info("余额支付成功: orderNo={} openid={} paidYuan={}", orderNo, openid, paidYuan);
            Order committedOrder = latest;
            AfterCommitExecutor.execute("balance_payment_fulfillment:" + orderNo,
                    () -> orderPaymentBridge.runPostPaymentSuccessSideEffects(committedOrder, paidYuan));
            return R.ok().put("paidYuan", paidYuan).put("payment_method", PAYMENT_METHOD_BALANCE);
        }
    }

    public R memberRechargeWechat(Map<String, String> params, HttpServletRequest request) {
        String openid = params != null ? params.get("openid") : null;
        if (!StringUtils.hasText(openid)) {
            return R.error("openid不能为空");
        }
        openid = openid.trim();
        User user = userService.getUserByOpenid(openid);
        if (user == null || user.getId() == null) {
            return R.error("用户未注册");
        }
        String amtStr = null;
        if (params != null) {
            amtStr = params.get("amount");
            if (!StringUtils.hasText(amtStr)) {
                amtStr = params.get("totalAmount");
            }
        }
        if (!StringUtils.hasText(amtStr)) {
            return R.error("充值金额不能为空（amount 或 totalAmount，单位：元）");
        }
        double amountYuan;
        try {
            amountYuan = Double.parseDouble(amtStr.trim());
        } catch (NumberFormatException ex) {
            return R.error("金额格式错误：" + amtStr);
        }
        if (amountYuan < WxRechargeGiftTierValidator.MIN_YUAN || amountYuan > WxRechargeGiftTierValidator.MAX_YUAN) {
            return R.error(String.format("会员充值单笔不得低于%.0f元，且不超过%.0f元",
                    WxRechargeGiftTierValidator.MIN_YUAN, WxRechargeGiftTierValidator.MAX_YUAN));
        }
        double rounded = UserWalletSplitUtil.roundYuan(UserWalletSplitUtil.decimal(amountYuan));
        String giftStr = null;
        if (params != null) {
            giftStr = params.get("gift_amount");
            if (!StringUtils.hasText(giftStr)) {
                giftStr = params.get("giftAmount");
            }
            if (!StringUtils.hasText(giftStr)) {
                giftStr = params.get("gift");
            }
        }
        double giftYuan = 0d;
        if (StringUtils.hasText(giftStr)) {
            try {
                giftYuan = Double.parseDouble(giftStr.trim());
            } catch (NumberFormatException ex) {
                return R.error("赠送金额格式错误：" + giftStr);
            }
            if (giftYuan < 0d || giftYuan > 9999.99d) {
                return R.error("赠送金额须在 0～9999.99 元之间");
            }
        }
        double giftRounded = UserWalletSplitUtil.roundYuan(UserWalletSplitUtil.decimal(giftYuan));
        String takeOut = params != null ? params.get("takeOut") : null;
        Integer shopId = ShopChainSupport.resolveShopChain(request,
                ShopChainSupport.parseBodyShopId(params != null ? params.get("shop_id") : null),
                ShopChainSupport.parseBodyShopCode(params != null ? params.get("shop_code") : null),
                shopService::requireActiveShopIdByCode);
        R rechargeGuard = paymentOnlineGuardService.checkWechatRecharge(shopId);
        if (rechargeGuard != null) {
            return rechargeGuard;
        }
        String rechargeNo = orderPaymentBridge.generateRechargeOrderNo();
        BigDecimal rechargeBd = BigDecimal.valueOf(rounded).setScale(2, RoundingMode.HALF_UP);
        BigDecimal giftBd = BigDecimal.valueOf(giftRounded).setScale(2, RoundingMode.HALF_UP);
        R giftRuleErr = WxRechargeGiftTierValidator.validate(rechargeBd, giftBd);
        if (giftRuleErr != null) {
            return giftRuleErr;
        }
        Long rechargeLogId = memberRechargeService.createPendingWechat(
                user.getId(), openid, rechargeNo, shopId, rechargeBd, giftBd);
        try {
            R prepay = wechatJsapiChannel.createPrepay(
                    null, shopId, rechargeNo, openid, takeOut, rounded, "1", "会员账户充值");
            boolean ok = prepay.get("code") != null && Integer.valueOf(0).equals(prepay.get("code"));
            if (!ok) {
                memberRechargeService.markCancelledById(rechargeLogId);
                return prepay;
            }
            if (prepay.get("newOrderNo") != null) {
                return prepay;
            }
            prepay.put("orderNo", rechargeNo);
            if (giftRounded > 0d) {
                prepay.put("giftAmount", giftRounded);
                prepay.put("expectedCreditTotal", rechargeBd.add(giftBd).doubleValue());
            }
            return prepay;
        } catch (RuntimeException ex) {
            memberRechargeService.markCancelledById(rechargeLogId);
            throw ex;
        }
    }
}

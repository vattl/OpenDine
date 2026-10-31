package com.lanf.util;

import com.lanf.entity.Order;

import java.util.Locale;

/**
 * 订单支付渠道金额（元）：与 {@code t_order.pay_amount_*} 列对应，便于统计与对账。
 * <p>
 * 与 {@code payment_method} 的常见关系：小程序微信回调写「微信支付」且仅 {@code pay_amount_wechat}；
 * 余额支付写「余额支付」且 {@code transaction_id} 以 {@code BAL_} 开头，
 * {@code pay_amount_balance}/{@code pay_amount_gift} 对应本金/赠送金钱包扣款（见 {@link #applyBalanceWalletSplit}）；
 * 运营后台人工结账见 {@link #applyFromPaymentMethodLabel}，一般只落单一渠道列。
 */
public final class OrderPayChannelAmounts {

    private static final String BALANCE_TX_ID_PREFIX = "BAL_";

    private OrderPayChannelAmounts() {
    }

    public static void clear(Order order) {
        if (order == null) {
            return;
        }
        order.setPay_amount_wechat(0d);
        order.setPay_amount_alipay(0d);
        order.setPay_amount_balance(0d);
        order.setPay_amount_gift(0d);
        order.setPay_amount_cash(0d);
        order.setBalance_pay_principal(0d);
        order.setBalance_pay_gift_wallet(0d);
    }

    /**
     * 余额支付（用户钱包）：按从本金账户、赠送金账户实际扣款金额，分别写入 {@code pay_amount_balance}、{@code pay_amount_gift}，
     * 并同步 {@code balance_pay_principal}、{@code balance_pay_gift_wallet}；其它渠道金额清零。
     */
    public static void applyBalanceWalletSplit(Order order, double principalPaidYuan, double giftWalletPaidYuan) {
        if (order == null) {
            return;
        }
        clear(order);
        double p = principalPaidYuan > 0d && !Double.isNaN(principalPaidYuan)
                ? Math.round(principalPaidYuan * 100) / 100.0 : 0d;
        double g = giftWalletPaidYuan > 0d && !Double.isNaN(giftWalletPaidYuan)
                ? Math.round(giftWalletPaidYuan * 100) / 100.0 : 0d;
        order.setPay_amount_balance(p);
        order.setPay_amount_gift(g);
        order.setBalance_pay_principal(p);
        order.setBalance_pay_gift_wallet(g);
    }

    /**
     * 将整单实付记到单一渠道（微信 / 支付宝 / 余额 / 赠送金 / 现金）。
     *
     * @param channel wechat | alipay | balance | gift | cash
     */
    public static void applySingleChannel(Order order, String channel, double paidYuan) {
        if (order == null || paidYuan <= 0d || Double.isNaN(paidYuan)) {
            return;
        }
        clear(order);
        double v = Math.round(paidYuan * 100) / 100.0;
        if (channel == null) {
            return;
        }
        switch (channel.trim().toLowerCase()) {
            case "wechat":
                order.setPay_amount_wechat(v);
                break;
            case "alipay":
                order.setPay_amount_alipay(v);
                break;
            case "balance":
                order.setPay_amount_balance(v);
                break;
            case "gift":
                order.setPay_amount_gift(v);
                break;
            case "cash":
                order.setPay_amount_cash(v);
                break;
            default:
                break;
        }
    }

    /**
     * 根据 {@code payment_method} 展示文案推断渠道（与看板 categoryCode 规则相近）。
     */
    public static void applyFromPaymentMethodLabel(Order order, String paymentMethodLabel, double paidYuan) {
        if (order == null || paidYuan <= 0d || Double.isNaN(paidYuan)) {
            return;
        }
        clear(order);
        double v = Math.round(paidYuan * 100) / 100.0;
        if (paymentMethodLabel == null || paymentMethodLabel.trim().isEmpty()) {
            order.setPay_amount_cash(v);
            return;
        }
        String s = paymentMethodLabel.trim();
        if (s.contains("微信")) {
            order.setPay_amount_wechat(v);
            return;
        }
        if (s.contains("支付宝") || "alipay".equalsIgnoreCase(s)) {
            order.setPay_amount_alipay(v);
            return;
        }
        if (s.contains("赠送") || s.contains("赠送金")) {
            order.setPay_amount_gift(v);
            return;
        }
        if (s.contains("余额")) {
            order.setPay_amount_balance(v);
            return;
        }
        if (s.contains("现金") || "cash".equalsIgnoreCase(s)) {
            order.setPay_amount_cash(v);
            return;
        }
        order.setPay_amount_cash(v);
    }

    /**
     * 与 {@link #applyFromPaymentMethodLabel} 相同净额口径，但可指定部分为现金：先写入 {@code pay_amount_cash}，
     * 剩余再按 {@code payment_method} 推断的<strong>非现金</strong>主渠道入账；若主渠道本身为现金，则剩余并入现金列。
     *
     * @param optionalCashYuan 现金部分（元），null 或 ≤0 时等价于 {@link #applyFromPaymentMethodLabel}
     */
    public static void applyFromPaymentMethodLabelWithOptionalCash(Order order, String paymentMethodLabel, double paidYuan, Double optionalCashYuan) {
        if (order == null || paidYuan <= 0d || Double.isNaN(paidYuan)) {
            return;
        }
        if (optionalCashYuan == null || optionalCashYuan <= 0d || Double.isNaN(optionalCashYuan)) {
            applyFromPaymentMethodLabel(order, paymentMethodLabel, paidYuan);
            return;
        }
        double total = Math.round(paidYuan * 100) / 100.0;
        double cashPart = Math.min(Math.round(optionalCashYuan * 100) / 100.0, total);
        double remainder = Math.round((total - cashPart) * 100) / 100.0;
        clear(order);
        order.setPay_amount_cash(cashPart);
        if (remainder <= 0d) {
            return;
        }
        String primary = primaryChannelCodeFromPaymentMethodLabel(paymentMethodLabel);
        if ("cash".equals(primary)) {
            order.setPay_amount_cash(Math.round((cashPart + remainder) * 100) / 100.0);
            return;
        }
        switch (primary) {
            case "wechat":
                order.setPay_amount_wechat(remainder);
                break;
            case "alipay":
                order.setPay_amount_alipay(remainder);
                break;
            case "balance":
                order.setPay_amount_balance(remainder);
                break;
            case "gift":
                order.setPay_amount_gift(remainder);
                break;
            default:
                order.setPay_amount_cash(Math.round((cashPart + remainder) * 100) / 100.0);
                break;
        }
    }

    /**
     * 组合支付按请求中的微信、支付宝、余额、现金四列入账；至少两个渠道有金额，且分合计须等于应付金额。
     */
    public static void applyOnlineCombined(Order target, Order request, double paidYuan) {
        if (target == null || request == null || paidYuan <= 0d || Double.isNaN(paidYuan)) {
            throw new IllegalArgumentException("组合支付参数无效");
        }
        int wechatFen = requestAmountFen(request.getPay_amount_wechat(), "微信支付金额");
        int alipayFen = requestAmountFen(request.getPay_amount_alipay(), "支付宝支付金额");
        int balanceFen = requestAmountFen(request.getPay_amount_balance(), "余额支付金额");
        int cashFen = requestAmountFen(request.getPay_amount_cash(), "现金支付金额");
        int channelCount = (wechatFen > 0 ? 1 : 0)
                + (alipayFen > 0 ? 1 : 0)
                + (balanceFen > 0 ? 1 : 0)
                + (cashFen > 0 ? 1 : 0);
        if (channelCount < 2) {
            throw new IllegalArgumentException("组合支付至少需要两个渠道金额");
        }
        int paidFen = (int) Math.round(paidYuan * 100d);
        if (wechatFen + alipayFen + balanceFen + cashFen != paidFen) {
            throw new IllegalArgumentException("组合支付各渠道金额合计必须等于应付金额");
        }
        clear(target);
        target.setPay_amount_wechat(fromFen(wechatFen));
        target.setPay_amount_alipay(fromFen(alipayFen));
        target.setPay_amount_balance(fromFen(balanceFen));
        target.setPay_amount_cash(fromFen(cashFen));
    }

    private static int requestAmountFen(Double value, String fieldLabel) {
        if (value == null) {
            return 0;
        }
        if (Double.isNaN(value) || Double.isInfinite(value) || value < 0d) {
            throw new IllegalArgumentException(fieldLabel + "无效");
        }
        return (int) Math.round(value * 100d);
    }

    /** wechat | alipay | balance | gift | cash */
    private static String primaryChannelCodeFromPaymentMethodLabel(String paymentMethodLabel) {
        if (paymentMethodLabel == null || paymentMethodLabel.trim().isEmpty()) {
            return "cash";
        }
        String s = paymentMethodLabel.trim();
        if (s.contains("微信")) {
            return "wechat";
        }
        if (s.contains("支付宝") || "alipay".equalsIgnoreCase(s)) {
            return "alipay";
        }
        if (s.contains("赠送") || s.contains("赠送金")) {
            return "gift";
        }
        if (s.contains("余额")) {
            return "balance";
        }
        if (s.contains("现金") || "cash".equalsIgnoreCase(s)) {
            return "cash";
        }
        return "cash";
    }

    /**
     * 五渠道实付列当前合计（分），用于与「sett+service−discount」可退口径交叉校验。
     */
    public static int totalPayChannelAmountFen(Order order) {
        if (order == null) {
            return 0;
        }
        int[] o = readFiveFen(order);
        return o[0] + o[1] + o[2] + o[3] + o[4];
    }

    /**
     * 将本次拟退款分截断为不超过「合同剩余可退」与「渠道列剩余」（当渠道合计 &gt; 0 时）的最小值。
     */
    public static int capRefundFenWithChannelTotal(int requestedFen, int remainingContractualFen, int channelSumFen) {
        if (requestedFen <= 0) {
            return 0;
        }
        int cap = Math.min(requestedFen, Math.max(0, remainingContractualFen));
        if (channelSumFen > 0) {
            cap = Math.min(cap, channelSumFen);
        }
        return cap;
    }

    /**
     * 渠道列合计与理论实付（分）差异是否超过阈值（供调用方打日志）。
     */
    public static boolean payChannelsDriftFromTheoryFen(Order order, int theoryPaidFen, int toleranceFen) {
        if (order == null || theoryPaidFen <= 0 || toleranceFen < 0) {
            return false;
        }
        int sum = totalPayChannelAmountFen(order);
        if (sum <= 0) {
            return false;
        }
        return Math.abs(sum - theoryPaidFen) > toleranceFen;
    }

    /**
     * 累计退款增加 {@code deltaRefundYuan}（元，正数）时，按 {@code payment_method} / {@code transaction_id} 做<strong>原路扣减</strong>：
     * <ul>
     *   <li>微信支付：先扣 {@code pay_amount_wechat}，不足部分再在其余有额渠道按比例分摊</li>
     *   <li>支付宝 / 现金 / 纯赠送金文案：同上，分别优先扣对应单列</li>
     *   <li>余额支付（{@code BAL_} 占位或文案为余额类且不含微信/支付宝）：仅在 {@code pay_amount_balance} 与 {@code pay_amount_gift} 间按比例扣减；
     *       并同步同额扣减 {@code balance_pay_principal}、{@code balance_pay_gift_wallet}（与钱包扣款列对齐）</li>
     *   <li>无法识别时：五列合计按比例扣减（与旧逻辑一致）</li>
     * </ul>
     */
    public static void applyRefundDeltaProportional(Order order, double deltaRefundYuan) {
        if (order == null || deltaRefundYuan <= 0d || Double.isNaN(deltaRefundYuan)) {
            return;
        }
        int deltaFen = (int) Math.round(deltaRefundYuan * 100d);
        if (deltaFen <= 0) {
            return;
        }
        int[] orig = readFiveFen(order);
        int sumAll = orig[0] + orig[1] + orig[2] + orig[3] + orig[4];
        if (sumAll <= 0) {
            return;
        }
        int cap = Math.min(deltaFen, sumAll);

        RefundRoute route = detectRefundRoute(order);
        int[] reduce;
        if (route == RefundRoute.BALANCE_WALLET) {
            reduce = reduceBalanceWalletRoute(order, orig, cap);
        } else if (route == RefundRoute.WECHAT) {
            reduce = reducePrimaryThenOthers(orig, cap, 0);
        } else if (route == RefundRoute.ALIPAY) {
            reduce = reducePrimaryThenOthers(orig, cap, 1);
        } else if (route == RefundRoute.CASH) {
            reduce = reducePrimaryThenOthers(orig, cap, 3);
        } else if (route == RefundRoute.GIFT) {
            reduce = reducePrimaryThenOthers(orig, cap, 4);
        } else {
            reduce = reduceProportionalAll(orig, cap);
        }
        applyReduction(order, orig, reduce);
    }

    private enum RefundRoute {
        BALANCE_WALLET,
        WECHAT,
        ALIPAY,
        CASH,
        GIFT,
        UNKNOWN
    }

    private static RefundRoute detectRefundRoute(Order order) {
        String tid = order.getTransaction_id() != null ? order.getTransaction_id().trim() : "";
        if (tid.startsWith(BALANCE_TX_ID_PREFIX)) {
            return RefundRoute.BALANCE_WALLET;
        }
        String pm = order.getPayment_method() != null ? order.getPayment_method().trim() : "";
        if (pm.isEmpty()) {
            return RefundRoute.UNKNOWN;
        }
        boolean hasWx = pm.contains("微信");
        boolean hasAli = pm.contains("支付宝") || pm.toLowerCase(Locale.ROOT).contains("alipay");
        if (hasWx || hasAli) {
            return hasWx ? RefundRoute.WECHAT : RefundRoute.ALIPAY;
        }
        if (pm.contains("赠送") || pm.contains("赠送金")) {
            return RefundRoute.GIFT;
        }
        if (pm.contains("现金") || "cash".equalsIgnoreCase(pm)) {
            return RefundRoute.CASH;
        }
        if (pm.contains("余额")) {
            return RefundRoute.BALANCE_WALLET;
        }
        return RefundRoute.UNKNOWN;
    }

    /**
     * 仅动 balance(2)、gift(4) 两列及对应 wallet 字段；按比例分摊 cap，总额不超过两列之和。
     */
    private static int[] reduceBalanceWalletRoute(Order order, int[] orig, int cap) {
        boolean[] mask = {false, false, true, false, true};
        int[] red = reduceMaskedProportional(orig, mask, cap);
        int rb = red[2];
        int rg = red[4];
        int pFen = toFen(order.getBalance_pay_principal());
        int gFen = toFen(order.getBalance_pay_gift_wallet());
        order.setBalance_pay_principal(fromFen(Math.max(0, pFen - rb)));
        order.setBalance_pay_gift_wallet(fromFen(Math.max(0, gFen - rg)));
        return red;
    }

    /** 先尽可能扣 primaryIndex，剩余在其余有额下标上按比例分摊 */
    private static int[] reducePrimaryThenOthers(int[] orig, int cap, int primaryIndex) {
        int[] red = new int[5];
        int primaryAvail = orig[primaryIndex];
        int takePrimary = Math.min(cap, primaryAvail);
        red[primaryIndex] = takePrimary;
        int rem = cap - takePrimary;
        if (rem <= 0) {
            return red;
        }
        boolean[] mask = new boolean[5];
        int othersSum = 0;
        for (int i = 0; i < 5; i++) {
            if (i != primaryIndex) {
                mask[i] = true;
                othersSum += orig[i];
            }
        }
        if (othersSum <= 0) {
            return red;
        }
        int[] subRed = reduceMaskedProportional(orig, mask, Math.min(rem, othersSum));
        for (int i = 0; i < 5; i++) {
            red[i] += subRed[i];
        }
        return red;
    }

    private static int[] reduceProportionalAll(int[] orig, int cap) {
        boolean[] mask = {true, true, true, true, true};
        return reduceMaskedProportional(orig, mask, cap);
    }

    private static int[] reduceMaskedProportional(int[] orig, boolean[] mask, int cap) {
        int sum = 0;
        for (int i = 0; i < 5; i++) {
            if (mask[i]) {
                sum += orig[i];
            }
        }
        if (sum <= 0) {
            return new int[5];
        }
        int use = Math.min(cap, sum);
        int[] red = new int[5];
        for (int i = 0; i < 5; i++) {
            if (mask[i]) {
                red[i] = (int) ((long) orig[i] * use / sum);
            }
        }
        int allocated = red[0] + red[1] + red[2] + red[3] + red[4];
        int remainder = use - allocated;
        while (remainder > 0) {
            int pick = -1;
            int bestSlack = -1;
            for (int i = 0; i < 5; i++) {
                if (!mask[i]) {
                    continue;
                }
                int slack = orig[i] - red[i];
                if (slack > bestSlack) {
                    bestSlack = slack;
                    pick = i;
                }
            }
            if (pick < 0 || bestSlack <= 0) {
                break;
            }
            red[pick]++;
            remainder--;
        }
        return red;
    }

    private static void applyReduction(Order order, int[] orig, int[] reduce) {
        for (int i = 0; i < 5; i++) {
            if (reduce[i] < 0) {
                reduce[i] = 0;
            }
            if (reduce[i] > orig[i]) {
                reduce[i] = orig[i];
            }
        }
        order.setPay_amount_wechat(fromFen(orig[0] - reduce[0]));
        order.setPay_amount_alipay(fromFen(orig[1] - reduce[1]));
        order.setPay_amount_balance(fromFen(orig[2] - reduce[2]));
        order.setPay_amount_cash(fromFen(orig[3] - reduce[3]));
        order.setPay_amount_gift(fromFen(orig[4] - reduce[4]));
    }

    /**
     * 余额支付订单本地退款：在已按分拆分 {@code rf[0]}/{@code rf[1]}（本金/赠送金退回额）后，同步扣减订单上
     * {@code pay_amount_balance}/{@code pay_amount_gift} 与 {@code balance_pay_principal}/{@code balance_pay_gift_wallet}，
     * 与入账拆分一致，避免与 {@link #applyRefundDeltaProportional} 按列比例再次拆分产生偏差。
     */
    public static void applyBalanceRefundFromSplitFen(Order order, int[] rf) {
        if (order == null || rf == null || rf.length < 2) {
            return;
        }
        int r0 = Math.max(0, rf[0]);
        int r1 = Math.max(0, rf[1]);
        if (r0 == 0 && r1 == 0) {
            return;
        }
        int pb = toFen(order.getPay_amount_balance());
        int pg = toFen(order.getPay_amount_gift());
        int bpf = toFen(order.getBalance_pay_principal());
        int bgf = toFen(order.getBalance_pay_gift_wallet());
        int db = Math.min(r0, pb);
        int dg = Math.min(r1, pg);
        int wb = Math.min(r0, bpf);
        int wg = Math.min(r1, bgf);
        if (pb + pg > 0) {
            order.setPay_amount_balance(fromFen(pb - db));
            order.setPay_amount_gift(fromFen(pg - dg));
        }
        order.setBalance_pay_principal(fromFen(Math.max(0, bpf - wb)));
        order.setBalance_pay_gift_wallet(fromFen(Math.max(0, bgf - wg)));
    }

    private static int[] readFiveFen(Order order) {
        return new int[]{
                toFen(order.getPay_amount_wechat()),
                toFen(order.getPay_amount_alipay()),
                toFen(order.getPay_amount_balance()),
                toFen(order.getPay_amount_cash()),
                toFen(order.getPay_amount_gift())
        };
    }

    private static int toFen(Double yuan) {
        if (yuan == null || yuan <= 0d || Double.isNaN(yuan)) {
            return 0;
        }
        return (int) Math.round(yuan * 100d);
    }

    private static double fromFen(int fen) {
        if (fen <= 0) {
            return 0d;
        }
        return Math.round(fen) / 100.0;
    }
}

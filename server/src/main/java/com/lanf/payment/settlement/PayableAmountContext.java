package com.lanf.payment.settlement;

import java.util.Date;

public class PayableAmountContext {
    public String merchantId;
    public double orderOriginalYuan;
    public double couponDiscount;
    public double basePaidYuan;
    public boolean hasPersistedPositiveDiscount;
    public boolean usesCouponForSettlement;
    public Date nineFoldTimeRef;
    public String dineInOrTakeOut;
    public java.util.List<com.lanf.payment.routing.PaymentRoutingContext.RoutingGoodsItem> goodsItems;
}

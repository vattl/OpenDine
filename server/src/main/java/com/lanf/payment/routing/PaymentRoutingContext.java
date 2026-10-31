package com.lanf.payment.routing;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;

/**
 * 支付商户路由评估上下文（全渠道统一，包含订单金额、就餐方式、下单时间及商品行项）。
 */
public class PaymentRoutingContext {

    public Integer shopId;
    public double paidYuan;
    public String diningType;
    public Date orderTime;
    public String currentMerchantId;
    public List<RoutingGoodsItem> goodsItems = new ArrayList<>();

    public PaymentRoutingContext() {
    }

    public PaymentRoutingContext(Integer shopId, double paidYuan, String diningType, String currentMerchantId) {
        this.shopId = shopId;
        this.paidYuan = paidYuan;
        this.diningType = diningType;
        this.currentMerchantId = currentMerchantId;
        this.orderTime = new Date();
    }

    public static class RoutingGoodsItem {
        public Long goodsId;
        public String goodsName;
        public Long categoryId;
        public BigDecimal price;
        public Integer quantity;

        public RoutingGoodsItem() {
        }

        public RoutingGoodsItem(Long goodsId, String goodsName, Long categoryId, BigDecimal price, Integer quantity) {
            this.goodsId = goodsId;
            this.goodsName = goodsName;
            this.categoryId = categoryId;
            this.price = price;
            this.quantity = quantity;
        }
    }
}

package com.lanf.service;

import com.lanf.entity.OrderDetail;
import com.lanf.order.RefundStockAction;

import java.util.List;

/**
 * 门店菜品可售库存（t_dish_shop）扣减与回退，与下单/加菜/退菜对称。
 */
public interface IDishShopStockService {

    void validateCanDeduct(List<OrderDetail> lines, Integer shopId);

    void deductForDetails(List<OrderDetail> lines, Integer shopId);

    /** 回退指定明细的全部有效数量（退菜整行或取消单）。默认 RESTORE 动作。 */
    void restoreForDetail(OrderDetail detail, Integer shopId);

    /** 回退指定份数（部分退菜或减数量）。默认 RESTORE 动作。 */
    void restoreQuantity(OrderDetail detail, Integer shopId, int quantity);

    /** 扣减指定份数（加数量）。 */
    void deductQuantity(OrderDetail detail, Integer shopId, int quantity);

    /**
     * 处理退菜时的库存动作（支持 RESTORE / NO_RESTORE / OUT_OF_STOCK）。
     *
     * @param detail 订单明细
     * @param shopId 门店 ID
     * @param quantity 退菜数量
     * @param stockAction 退菜库存动作
     * @param operator 操作人/操作端
     * @param remark 备注/原因
     */
    void handleRefundStock(OrderDetail detail, Integer shopId, int quantity,
                           RefundStockAction stockAction, String operator, String remark);
}

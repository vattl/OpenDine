package com.lanf.service;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.Order;
import com.lanf.entity.TakeoutDelivery;

import java.util.Collection;
import java.util.Date;

public interface ITakeoutDeliveryService extends IService<TakeoutDelivery> {

    void insertForNewOrder(TakeoutDelivery row);

    void markPaidIfPresent(String orderNo);

    /** 商家接单后：submitted/paid → accepted */
    void markAcceptedIfPresent(String orderNo, Integer orderId);

    void markCancelledIfPresent(String orderNo);

    /**
     * 运营端将配送置为已取消：同步写入 dispatch / zsq 状态，供列表与详情立即回显。
     */
    boolean markDeliveryCancelled(Integer orderId, Integer shopId, String reason);

    /**
     * 运营端更新履约状态；shopId 与订单归属不一致时不更新。
     */
    boolean updateDispatchStatus(Integer orderId, String newStatus, Integer shopId);

    TakeoutDelivery getByOrderId(Integer orderId);

    IPage<TakeoutDelivery> pageByShop(Integer shopId, int pageNum, int pageSize, String dispatchStatus);

    IPage<TakeoutDelivery> pageByShop(Integer shopId, int pageNum, int pageSize, String dispatchStatus, Date startTime, Date endTime);

    /**
     * 将当前订单对应的外卖配送扩展摘要写入订单非持久化字段（JSON 与列表接口统一带出）。
     */
    void enrichOrder(Order order);

    void enrichOrders(Collection<Order> orders);

    /**
     * 删除订单前校验外卖配送是否可删：配送进行中返回错误说明，可删则返回 null。
     */
    String getOrderDeleteBlockReason(TakeoutDelivery delivery);

    /**
     * 删除订单关联的 {@code t_takeout_delivery} 行（无记录或非外卖时 no-op）。
     */
    void deleteByOrderId(Integer orderId);

    /**
     * 外卖退款前置校验：已发配送须 {@code dispatch_status=completed}；非外卖返回 null。
     *
     * @return null 表示允许退款，否则为错误说明
     */
    String getRefundBlockReason(Order order);
}

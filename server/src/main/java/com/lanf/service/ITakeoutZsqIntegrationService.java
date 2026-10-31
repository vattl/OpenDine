package com.lanf.service;

import com.lanf.entity.Order;
import com.lanf.entity.ShopTakeoutConfig;
import com.lanf.entity.TakeoutDelivery;
import com.lanf.entity.UserAddress;
import com.lanf.integration.web.dto.ZsqRiderTrackingResponse;

/**
 * 本系统外卖订单与真省钱（ZSQ）聚合配送的桥接服务。
 */
public interface ITakeoutZsqIntegrationService {

    /** 商家接单后尝试自动发真省钱配送（受 {@code zsq.auto_api.enabled} 按门店控制；关闭时仅手动发单） */
    void tryAutoDispatchAfterAccepted(Integer orderId);

    /** KDS 厨显整单出餐制作完成（ALL_DONE）后自动叫骑手发真省钱配送（外卖订单专属，具备幂等防重与容错隔离） */
    void tryAutoDispatchOnKdsCompleted(Integer orderId);

    /** 手动或重发：已有有效 openOrderId 时沿用原订单重新发配送，仅远端订单不存在时重新创单 */
    TakeoutDelivery dispatchToZsq(Integer orderId, boolean forceRedispatch);

    /** 从真省钱拉取骑手/状态并回写 dispatch_status、zsq_* 字段 */
    TakeoutDelivery syncFromZsq(Integer orderId);

    /**
     * 取消关联的真省钱订单；返回责任扣费（元），退款时应从可退金额中扣除。
     *
     * @param strict true=真省钱取消失败则抛异常；false=尽力取消，失败仅记日志
     */
    com.lanf.integration.remote.dto.ZsqCancelResult cancelZsqForOrder(Integer orderId, String reason, boolean strict);

    /** C 端：校验 openid 后返回骑手追踪（含 ETA） */
    ZsqRiderTrackingResponse getTrackingForUser(String openid, String orderNo);

    /** 运营端：按订单 id 拉取真省钱追踪并回写配送扩展 */
    ZsqRiderTrackingResponse getTrackingForOrder(Integer orderId);

    /** 批量同步进行中的 ZSQ 配送单（定时任务用） */
    int syncActiveDeliveries();

    /**
     * Processes one cursor-bounded delivery batch.  The cursor is an opaque local
     * scheduler checkpoint; callers resume from {@link DeliverySyncBatch#lastId}.
     */
    DeliverySyncBatch syncActiveDeliveriesAfter(long afterId, int limit, long deadlineNanos);

    final class DeliverySyncBatch {
        public final int processed;
        public final long lastId;
        public final boolean exhausted;
        public DeliverySyncBatch(int processed, long lastId, boolean exhausted) {
            this.processed = processed; this.lastId = lastId; this.exhausted = exhausted;
        }
    }
}

package com.lanf.printing.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.payment.support.PaymentDiningTypeUtil;
import com.lanf.printing.model.PrintContext;
import com.lanf.printing.model.PrintScenario;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.util.AfterCommitExecutor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import javax.annotation.PreDestroy;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.stream.Collectors;

/**
 * KDS 模式下的附加物理打印通道。
 *
 * <p>KDS 投影是接单主链路，网络打印不得阻塞订单事务提交和 KDS 事件发布。
 * 任务只在事务提交后进入有界线程池，并重新读取已提交订单数据，避免跨线程
 * 使用事务内实体。</p>
 */
@Service
public class KdsSupplementalPrintService {
    private static final Logger log = LoggerFactory.getLogger(KdsSupplementalPrintService.class);

    private final IOrderService orderService;
    private final IOrderDetailService orderDetailService;
    private final ITakeoutDeliveryService takeoutDeliveryService;
    private final PrintDispatcherService printDispatcherService;
    private final ThreadPoolExecutor workers;
    private final AtomicLong rejected = new AtomicLong();

    public KdsSupplementalPrintService(IOrderService orderService,
                                       IOrderDetailService orderDetailService,
                                       ITakeoutDeliveryService takeoutDeliveryService,
                                       PrintDispatcherService printDispatcherService) {
        this.orderService = orderService;
        this.orderDetailService = orderDetailService;
        this.takeoutDeliveryService = takeoutDeliveryService;
        this.printDispatcherService = printDispatcherService;
        this.workers = new ThreadPoolExecutor(2, 2, 0L, TimeUnit.MILLISECONDS,
                new ArrayBlockingQueue<>(256), task -> {
            Thread thread = new Thread(task, "kds-supplemental-print");
            thread.setDaemon(true);
            return thread;
        }, new ThreadPoolExecutor.AbortPolicy());
    }

    public void scheduleAfterCommit(int shopId, int orderId,
                                    Collection<Integer> detailIds,
                                    Set<String> cidFilter) {
        List<Integer> immutableDetailIds = detailIds == null
                ? Collections.emptyList()
                : Collections.unmodifiableList(new ArrayList<>(detailIds));
        Set<String> immutableCidFilter = cidFilter == null
                ? Collections.emptySet()
                : Collections.unmodifiableSet(new HashSet<>(cidFilter));
        AfterCommitExecutor.execute("kds_supplemental_print:" + orderId,
                () -> submit(shopId, orderId, immutableDetailIds, immutableCidFilter));
    }

    private void submit(int shopId, int orderId, List<Integer> detailIds, Set<String> cidFilter) {
        try {
            workers.execute(() -> dispatch(shopId, orderId, detailIds, cidFilter));
        } catch (RejectedExecutionException ex) {
            long count = rejected.incrementAndGet();
            log.error("[kds-print] 附加打印队列已满或关闭: shopId={}, orderId={}, rejected={}",
                    shopId, orderId, count, ex);
        }
    }

    private void dispatch(int shopId, int orderId, List<Integer> detailIds, Set<String> cidFilter) {
        try {
            Order order = orderService.getById(orderId);
            if (order == null) {
                log.warn("[kds-print] 附加打印跳过，订单不存在: shopId={}, orderId={}", shopId, orderId);
                return;
            }
            List<OrderDetail> details = orderDetailService.list(
                    new QueryWrapper<OrderDetail>().eq("mId", orderId));
            if (!detailIds.isEmpty()) {
                Set<Integer> targets = new HashSet<>(detailIds);
                details = details == null ? Collections.emptyList() : details.stream()
                        .filter(detail -> detail != null && targets.contains(detail.getId()))
                        .collect(Collectors.toList());
            }
            if (details == null || details.isEmpty()) {
                log.warn("[kds-print] 附加打印跳过，无目标明细: shopId={}, orderId={}", shopId, orderId);
                return;
            }
            order.setGoods_list(details);
            takeoutDeliveryService.enrichOrder(order);
            printDispatcherService.dispatch(shopId, PrintScenario.KITCHEN,
                    PrintContext.ofKitchen(order, cidFilter));
            String frontScenario = PaymentDiningTypeUtil.isWaimaiType(order.getDineInOrTakeOut())
                    ? PrintScenario.TAKEOUT : PrintScenario.ORDER;
            printDispatcherService.dispatch(shopId, frontScenario, PrintContext.ofOrder(order, true));
            if (PaymentDiningTypeUtil.isTakeOutType(order.getDineInOrTakeOut())) {
                printDispatcherService.dispatch(shopId, PrintScenario.PACKING, PrintContext.ofOrder(order, true));
            }
            log.info("[kds-print] 附加打印派发完成: shopId={}, orderId={}, detailCount={}",
                    shopId, orderId, details.size());
        } catch (Exception ex) {
            log.error("[kds-print] 附加打印失败，不影响已提交的 KDS 订单: shopId={}, orderId={}",
                    shopId, orderId, ex);
        }
    }

    long rejectedCount() {
        return rejected.get();
    }

    @PreDestroy
    public void close() {
        workers.shutdownNow();
    }
}

package com.lanf.schedule;

import com.lanf.controller.OrderController;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Lazy;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** Retries paid/dine-in orders that remain unaccepted after a printer or KDS failure. */
@Component
public class OrderFulfillmentRetryScheduler {

    private static final Logger log = LoggerFactory.getLogger(OrderFulfillmentRetryScheduler.class);

    private final OrderController orderController;

    public OrderFulfillmentRetryScheduler(@Lazy OrderController orderController) {
        this.orderController = orderController;
    }

    @Scheduled(fixedDelayString = "${order.fulfillment-retry-ms:30000}")
    public void retryPendingOrders() {
        try {
            orderController.processPendingOrdersForAutoAccept();
            orderController.repairAcceptedKdsTickets();
        } catch (RuntimeException ex) {
            log.error("待接单订单补偿任务失败: {}", ex.getMessage(), ex);
        }
    }
}

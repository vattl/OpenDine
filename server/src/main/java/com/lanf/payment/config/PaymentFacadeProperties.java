package com.lanf.payment.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * 支付 Facade 灰度：false 时仍走 {@code OrderController} 内联实现（回滚用）。
 */
@Component
public class PaymentFacadeProperties {

    @Value("${payment.use-facade:true}")
    private boolean useFacade;

    public boolean isUseFacade() {
        return useFacade;
    }
}

package com.lanf.access.policy;

import com.lanf.access.model.AccessContext;
import com.lanf.entity.AccessPolicy;

/**
 * 策略处理器接口
 */
public interface AccessPolicyHandler {

    /**
     * 支持的策略类型编码，例如 MAX_AMOUNT, MIN_DISCOUNT_RATE 等
     */
    String type();

    /**
     * 评估上下文是否满足策略
     */
    PolicyResult evaluate(AccessPolicy policy, AccessContext ctx);
}

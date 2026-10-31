package com.lanf.integration.web.dto;

import javax.validation.Valid;
import javax.validation.constraints.NotNull;

/**
 * 创建外卖订单并立即发起配送（保存并发单）。
 */
public class CreateTakeawayDispatchRequest {

    @NotNull
    @Valid
    private CreateTakeawayOrderRequest order;

  /** 配送选项，可省略（使用默认：同时叫单、选 1 个最便宜渠道） */
    private ZsqDispatchOptionsRequest dispatch;

    public CreateTakeawayOrderRequest getOrder() {
        return order;
    }

    public void setOrder(CreateTakeawayOrderRequest order) {
        this.order = order;
    }

    public ZsqDispatchOptionsRequest getDispatch() {
        return dispatch;
    }

    public void setDispatch(ZsqDispatchOptionsRequest dispatch) {
        this.dispatch = dispatch;
    }
}

package com.lanf.integration.web.dto;

import com.lanf.integration.remote.dto.ZsqCreateOrderResult;
import com.lanf.integration.remote.dto.ZsqDeliveryBillingChannel;

import java.util.List;
import java.util.Map;

/** 保存外卖订单 + 发起配送的结果。 */
public class ZsqTakeawayDispatchResult {

    private ZsqCreateOrderResult order;
    private Map<String, Object> dispatch;
    private List<ZsqDeliveryBillingChannel> quotedChannels;
    private List<Integer> selectedDeliveryCodes;

    public ZsqCreateOrderResult getOrder() {
        return order;
    }

    public void setOrder(ZsqCreateOrderResult order) {
        this.order = order;
    }

    public Map<String, Object> getDispatch() {
        return dispatch;
    }

    public void setDispatch(Map<String, Object> dispatch) {
        this.dispatch = dispatch;
    }

    public List<ZsqDeliveryBillingChannel> getQuotedChannels() {
        return quotedChannels;
    }

    public void setQuotedChannels(List<ZsqDeliveryBillingChannel> quotedChannels) {
        this.quotedChannels = quotedChannels;
    }

    public List<Integer> getSelectedDeliveryCodes() {
        return selectedDeliveryCodes;
    }

    public void setSelectedDeliveryCodes(List<Integer> selectedDeliveryCodes) {
        this.selectedDeliveryCodes = selectedDeliveryCodes;
    }
}

package com.lanf.integration.remote.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

import java.math.BigDecimal;
import java.util.Map;

/** 真省钱取消订单结果（含责任费解析）。 */
@JsonIgnoreProperties(ignoreUnknown = true)
public class ZsqCancelResult {

    private boolean success;
    private String message;
    private String cancelPrompt;
    private BigDecimal liabilityFeeYuan;
    private Map<String, Object> rawPrompt;
    private Map<String, Object> rawCancel;

    public boolean isSuccess() {
        return success;
    }

    public void setSuccess(boolean success) {
        this.success = success;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }

    public String getCancelPrompt() {
        return cancelPrompt;
    }

    public void setCancelPrompt(String cancelPrompt) {
        this.cancelPrompt = cancelPrompt;
    }

    public BigDecimal getLiabilityFeeYuan() {
        return liabilityFeeYuan;
    }

    public void setLiabilityFeeYuan(BigDecimal liabilityFeeYuan) {
        this.liabilityFeeYuan = liabilityFeeYuan;
    }

    public Map<String, Object> getRawPrompt() {
        return rawPrompt;
    }

    public void setRawPrompt(Map<String, Object> rawPrompt) {
        this.rawPrompt = rawPrompt;
    }

    public Map<String, Object> getRawCancel() {
        return rawCancel;
    }

    public void setRawCancel(Map<String, Object> rawCancel) {
        this.rawCancel = rawCancel;
    }
}

package com.lanf.ai.dto;

import lombok.Data;

@Data
public class SubmitAiOrderDTO {
    private String draft_id;
    private String idempotency_key;
    private String client_order_id;
    private String dineInOrTakeOut;
    private String remark;
    private String openid;
    /** 指定或覆盖下单桌号（如 "01", "A01"） */
    private String table_number;
}

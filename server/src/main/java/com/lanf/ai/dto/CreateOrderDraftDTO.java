package com.lanf.ai.dto;

import lombok.Data;

@Data
public class CreateOrderDraftDTO {
    private String plan_id;
    private String session_id;
    private String table_number;
    private String openid;
}

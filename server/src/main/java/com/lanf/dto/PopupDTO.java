package com.lanf.dto;

import lombok.Data;
import java.math.BigDecimal;
import java.util.Date;


@Data
public class PopupDTO {
    private String type;
    private String openid;
    /** 门店 ID，可与请求头 X-Shop-Id / shop_code 合并解析 */
    private Integer shop_id;
    private String shop_code;
}
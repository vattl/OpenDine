package com.lanf.ai.dto;

import lombok.Data;

import java.util.List;

@Data
public class CreateDiningSessionDTO {
    private Integer shop_id;
    /** 门店ID别名，等同于 shop_id */
    private Integer store_id;
    private String table_number;
    private Integer party_size;
    /** 总预算 (分) */
    private Integer budget_fen;
    private String currency;
    private String dining_mode;
    private Boolean include_drinks;
    private String strategy;
    private List<String> table_goals;
    private List<DinerMemberDTO> members;
}

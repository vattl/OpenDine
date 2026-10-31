package com.lanf.ai.dto;

import lombok.Data;

import java.util.List;

@Data
public class UpdateDiningSessionDTO {
    private Integer expected_revision;
    private Integer budget_fen;
    private Integer party_size;
    private String strategy;
    private List<String> table_goals;
    private List<DinerMemberDTO> members;
}

package com.lanf.ai.dto;

import lombok.Data;

import java.util.List;
import java.util.Map;

@Data
public class MealPlanResponseDTO {
    private String plan_id;
    private String session_id;
    private Integer revision;
    private String menu_version;
    private Integer price_total_fen;
    private Integer remaining_budget_fen;
    private Boolean feasible;
    private String strategy;
    private List<MealLineItemDTO> line_items;
    private Map<String, Object> allocation_summary;
    private Map<String, Object> score_details;
    private Map<String, Object> conflict_details;
    private List<Map<String, Object>> explanation_cards;
}

package com.lanf.ai.solver;

import com.lanf.ai.dto.MealLineItemDTO;
import lombok.Data;

import java.util.List;
import java.util.Map;

@Data
public class SolverResult {
    private boolean feasible;
    private int price_total_fen;
    private int remaining_budget_fen;
    private String strategy;
    private List<MealLineItemDTO> line_items;
    private Map<String, Object> allocation_summary;
    private Map<String, Object> score_details;
    private Map<String, Object> conflict_details;
    private List<Map<String, Object>> explanation_cards;
}

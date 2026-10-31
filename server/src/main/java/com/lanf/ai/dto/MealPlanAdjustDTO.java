package com.lanf.ai.dto;

import lombok.Data;

import java.util.List;
import java.util.Map;

@Data
public class MealPlanAdjustDTO {
    private String natural_language_patch;
    private Integer budget_delta_fen;
    private List<Integer> remove_dish_ids;
    private Map<String, Object> add_member_restriction;
}

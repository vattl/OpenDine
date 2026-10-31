package com.lanf.ai.dto;

import lombok.Data;

import java.util.List;

@Data
public class DinerMemberDTO {
    private String diner_id;
    private String alias;
    private Boolean is_non_spicy;
    private List<String> disliked_ingredients;
    private List<String> verified_allergens;
    private String portion_target;
    private List<String> fitness_goals;
    private Boolean join_shared_dishes;
}

package com.lanf.ai.dto;

import lombok.Data;

import java.util.List;

@Data
public class MealLineItemDTO {
    private Integer dish_id;
    private String name;
    private String unit;
    private Integer quantity;
    private Integer unit_price_fen;
    private Integer subtotal_fen;
    private String spice_level;
    private String kitchen_note;
    private List<String> allocated_to;
    private String reason;
}

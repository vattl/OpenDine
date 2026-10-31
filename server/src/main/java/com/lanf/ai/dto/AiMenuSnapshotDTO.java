package com.lanf.ai.dto;

import lombok.Data;

import java.math.BigDecimal;
import java.util.List;

@Data
public class AiMenuSnapshotDTO {
    private Integer shop_id;
    private String menu_version;
    private Long timestamp;
    private List<AiMenuItemDTO> items;

    @Data
    public static class AiMenuItemDTO {
        private Integer dish_id;
        private String name;
        private String category_name;
        private Integer price_fen;
        private String unit;
        private Integer stock;
        /** 菜品月销量 */
        private Integer monthlysale;
        /** 销量别名（对齐标准命名） */
        private Integer sales_count;
        /** 菜品图片URL */
        private String image;
        private Boolean active;
        private Boolean sold_out;
        private Boolean non_spicy_available;
        private List<String> spice_options;
        private List<String> verified_allergens;
        private Boolean cross_contact_risk;
        private Boolean is_suitable_fitness;
        private BigDecimal calories_kcal;
        private BigDecimal protein_g;
        private BigDecimal fat_g;
        private Integer edible_weight_g;
        private String nutrition_source;
    }
}

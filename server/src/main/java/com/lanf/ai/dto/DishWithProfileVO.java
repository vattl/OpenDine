package com.lanf.ai.dto;

import com.lanf.ai.entity.DishFoodProfile;
import lombok.Data;

import java.math.BigDecimal;

/**
 * 菜品及其 AI 配餐画像组合视图对象（前端画像管理列表使用）
 */
@Data
public class DishWithProfileVO {

    private Integer dish_id;

    private String dish_name;

    private Integer category_id;

    private String category_name;

    /** 售价(元) */
    private BigDecimal price;

    /** 售价(分) */
    private Integer price_fen;

    /** 当前门店在售状态：1在售，0下架 */
    private Integer onsale;

    /** 当前门店是否售罄：1已售罄，0正常有货 */
    private Integer sold_out;

    /** 是否已配置 AI 食材画像 */
    private Boolean has_profile;

    /** 详细画像数据 */
    private DishFoodProfile profile;
}

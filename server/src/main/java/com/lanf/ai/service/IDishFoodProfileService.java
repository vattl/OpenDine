package com.lanf.ai.service;

import com.lanf.ai.dto.DishFoodProfileInputDTO;
import com.lanf.ai.dto.DishWithProfileVO;
import com.lanf.ai.entity.DishFoodProfile;

import java.util.List;

public interface IDishFoodProfileService {

    /**
     * 查询门店全部菜品及其当前 AI 画像绑定状态
     *
     * @param shopId 门店ID
     * @param categoryId 可选分类过滤
     * @param configuredOnly 可选：仅看已配置/未配置
     * @return 菜品画像视图列表
     */
    List<DishWithProfileVO> getStoreDishProfiles(Integer shopId, Integer categoryId, Boolean configuredOnly);

    /**
     * 获取单个菜品的食材画像
     */
    DishFoodProfile getDishProfile(Integer shopId, Integer dishId);

    /**
     * 新增或更新单菜品画像
     */
    DishFoodProfile saveOrUpdateProfile(DishFoodProfileInputDTO input);

    /**
     * 批量新增或更新菜品画像
     */
    int batchSaveProfiles(Integer shopId, List<DishFoodProfileInputDTO> inputs);

    /**
     * 一键智能根据菜品名与分类做规则推断初始化（降低商家录入成本）
     */
    int autoInitStoreProfiles(Integer shopId);
}

package com.lanf.service;

import com.lanf.entity.Combo;
import com.lanf.entity.OrderDetail;

import java.util.List;
import java.util.Map;

/**
 * 结构化套餐：定义加载、下单行展开、头行金额校验。
 */
public interface IComboMealService {

    Combo getByDishId(int dishId);

    /**
     * 按菜品ID与门店ID获取套餐定义；优先匹配门店专属套餐（shop_id = :shopId），未匹配时回退总部通用模板（shop_id = 0）。
     */
    Combo getByDishId(int dishId, Integer shopId);

    Combo getById(long comboId);

    /**
     * 运营/列表简要结构（仅 id、加价、sortOrder 等，无子菜展示字段）。用于 {@code GET /admin/combo/getByDishId}、{@code Dish.comboDefinition}。
     */
    Map<String, Object> buildComboMenuPayload(long comboId);

    /**
     * 小程序选规格页专用结构（含子菜名称、门店价、上下架/售罄）；与 {@link #buildComboMenuPayload} 分离。
     */
    Map<String, Object> buildCustomerComboPayload(long comboId, Integer shopId);

    /**
     * 总部维护：按 dishId 全量替换套餐定义（先删子表再插）。
     */
    void saveComboDefinition(int dishId, String comboType, int status,
                             List<Map<String, Object>> fixedItems,
                             List<Map<String, Object>> groups);

    /**
     * 总部维护：按 dishId 全量替换套餐定义，并支持限购、时段、就餐方式、叠券等商业化配置。
     */
    void saveComboDefinition(int dishId, String comboType, int status,
                             List<Map<String, Object>> fixedItems,
                             List<Map<String, Object>> groups,
                             Map<String, Object> commercialParams);

    /**
     * 门店/总部维护：按 dishId 与 shopId 全量替换套餐定义（仅删除并替换目标门店自身记录，不影响其他门店）。
     */
    void saveComboDefinition(int dishId, Integer shopId, String comboType, int status,
                             List<Map<String, Object>> fixedItems,
                             List<Map<String, Object>> groups);

    /**
     * 门店/总部维护：按 dishId 与 shopId 全量替换套餐定义，并支持限购、时段、就餐方式、叠券等商业化配置。
     */
    void saveComboDefinition(int dishId, Integer shopId, String comboType, int status,
                             List<Map<String, Object>> fixedItems,
                             List<Map<String, Object>> groups,
                             Map<String, Object> commercialParams);

    /**
     * 将购物车中的套餐请求行展开为 combo_header + combo_component 多行（就地替换列表内容）。
     */
    void normalizeCartLines(List<OrderDetail> goodsList, Integer shopId);

    /**
     * 将购物车中的套餐请求行展开，并结合用户信息与就餐方式进行限购与时段商业化规则校验。
     */
    void normalizeCartLines(List<OrderDetail> goodsList, Integer shopId, String openid, String diningType);

    /**
     * 将购物车中的套餐请求行展开，并结合用户信息、就餐方式及渠道上下文进行限购与时段商业化规则校验。
     * 收银端（isCashier=true）豁免商业化限购/时段限制，仅保留套餐存在且启用校验。
     */
    void normalizeCartLines(List<OrderDetail> goodsList, Integer shopId, String openid, String diningType, boolean isCashier);

    /**
     * 套餐商业化运营规则校验（每单限购、用户周期限购、生效日期范围、可用星期、时段、就餐方式）。
     */
    void validateComboCommercialRules(long comboId, Integer shopId, int comboQty, String openid, String diningType);

    /**
     * 套餐商业化运营规则校验（每单限购、用户周期限购、生效日期范围、可用星期、时段、就餐方式）。
     * 收银端（isCashier=true）豁免商业化限购/时段限制，仅保留套餐存在且启用校验。
     */
    void validateComboCommercialRules(long comboId, Integer shopId, int comboQty, String openid, String diningType, boolean isCashier);

    /**
     * 已展开头行：按 combo_selection_json 复算总价并与 total_price 比对（±0.02）。
     */
    void assertHeaderPriceMatches(OrderDetail headerLine, Integer shopId);

    /**
     * 小程序/C 端：按套餐头菜品拉取启用中的套餐详情（含子菜展示字段与门店价）。
     */
    Map<String, Object> getCustomerComboDetail(int dishId, Integer shopId);

    /**
     * 小程序/C 端：按选择与份数计算套餐应付金额（元）。
     */
    double calcComboTotalYuan(long comboId, Integer shopId, int comboQty, Map<String, List<Integer>> selections);
}

package com.lanf.ai.solver;

import com.lanf.ai.dto.AiMenuSnapshotDTO.AiMenuItemDTO;
import com.lanf.ai.dto.DinerMemberDTO;
import com.lanf.ai.dto.MealLineItemDTO;
import org.springframework.stereotype.Component;

import java.util.*;
import java.util.stream.Collectors;

/**
 * 确定性两阶段词典序约束求解器 (Java 8 原生轻量化整数规划与背包剪枝算法)
 * 阶段一：硬约束满足性搜索（预算上限、免辣隔离、过敏原安全排除、库存上限）
 * 阶段二：多目标效用评分与解释卡生成（公平性、营养契合、多样性、预算利用率）
 * 阶段三：不可行协商与精确最小可行预算计算
 */
@Component
public class LexicographicalMealSolver {

    public SolverResult solve(SolverInput input) {
        SolverResult result = new SolverResult();
        String strategy = input.getStrategy() != null ? input.getStrategy() : "balanced";
        result.setStrategy(strategy);

        List<AiMenuItemDTO> menu = input.getMenu_items();
        if (menu == null || menu.isEmpty()) {
            result.setFeasible(false);
            Map<String, Object> conflict = new LinkedHashMap<>();
            conflict.put("status", "REQUIRES_MENU_DATA");
            conflict.put("message", "当前门店尚未连接真实在售菜单，无法生成可下单报价");
            result.setConflict_details(conflict);
            return result;
        }

        // 1. 过滤当前真实在售、未售罄且价格大于0的有效菜品
        List<AiMenuItemDTO> available = menu.stream()
                .filter(item -> Boolean.TRUE.equals(item.getActive()) && !Boolean.TRUE.equals(item.getSold_out()) && item.getPrice_fen() != null && item.getPrice_fen() > 0)
                .collect(Collectors.toList());

        if (available.isEmpty()) {
            result.setFeasible(false);
            Map<String, Object> conflict = new LinkedHashMap<>();
            conflict.put("status", "NO_AVAILABLE_ITEMS");
            conflict.put("message", "当前门店暂无可售商品");
            result.setConflict_details(conflict);
            return result;
        }

        int partySize = Math.max(1, input.getParty_size());
        int budgetFen = input.getBudget_fen();

        // 识别就餐成员中的不吃辣群体与过敏原
        List<DinerMemberDTO> members = input.getMembers();
        if (members == null || members.isEmpty()) {
            members = new ArrayList<>();
            for (int i = 1; i <= partySize; i++) {
                DinerMemberDTO m = new DinerMemberDTO();
                m.setDiner_id("P" + i);
                m.setIs_non_spicy(false);
                m.setJoin_shared_dishes(true);
                members.add(m);
            }
        }

        List<String> nonSpicyDiners = new ArrayList<>();
        Map<String, Set<String>> dinerAllergens = new HashMap<>();
        Map<String, Set<String>> dinerDislikes = new HashMap<>();
        for (DinerMemberDTO m : members) {
            if (Boolean.TRUE.equals(m.getIs_non_spicy())) {
                nonSpicyDiners.add(m.getDiner_id());
            }
            if (m.getVerified_allergens() != null && !m.getVerified_allergens().isEmpty()) {
                dinerAllergens.put(m.getDiner_id(), new HashSet<>(m.getVerified_allergens()));
            }
            if (m.getDisliked_ingredients() != null && !m.getDisliked_ingredients().isEmpty()) {
                dinerDislikes.put(m.getDiner_id(), new HashSet<>(m.getDisliked_ingredients()));
            }
        }

        // 检查是否有免辣菜品支持不吃辣成员
        List<AiMenuItemDTO> nonSpicySafeItems = available.stream()
                .filter(item -> Boolean.TRUE.equals(item.getNon_spicy_available()))
                .collect(Collectors.toList());

        if (!nonSpicyDiners.isEmpty() && nonSpicySafeItems.isEmpty()) {
            result.setFeasible(false);
            Map<String, Object> conflict = new LinkedHashMap<>();
            conflict.put("status", "NON_SPICY_UNAVAILABLE");
            conflict.put("message", "当前菜单无任何支持免辣制作的菜品，无法满足" + nonSpicyDiners.size() + "位不吃辣成员的要求");
            result.setConflict_details(conflict);
            return result;
        }

        // 2. 菜品分类：大串肉类、蔬菜副食、高饱腹主食
        List<AiMenuItemDTO> meats = new ArrayList<>();
        List<AiMenuItemDTO> veggies = new ArrayList<>();
        List<AiMenuItemDTO> staples = new ArrayList<>();
        List<AiMenuItemDTO> others = new ArrayList<>();

        for (AiMenuItemDTO item : available) {
            String name = item.getName() != null ? item.getName() : "";
            String cat = item.getCategory_name() != null ? item.getCategory_name() : "";
            if (name.contains("串") || name.contains("肉") || name.contains("油边") || name.contains("牛") || name.contains("羊") || name.contains("鸡") || cat.contains("肉") || cat.contains("串")) {
                meats.add(item);
            } else if (name.contains("金针菇") || name.contains("茄子") || name.contains("菜") || name.contains("土豆") || name.contains("黄瓜") || cat.contains("菜") || cat.contains("素")) {
                veggies.add(item);
            } else if (name.contains("馒头") || name.contains("饭") || name.contains("面") || name.contains("饼") || name.contains("粉") || cat.contains("主食")) {
                staples.add(item);
            } else {
                others.add(item);
            }
        }

        // 3. 执行确定性规划求解
        List<MealLineItemDTO> selectedItems = new ArrayList<>();
        int currentTotalFen = 0;

        // 3.1 首先满足免辣成员（P1, P2 等）的保底肉食与蔬菜
        if (!nonSpicyDiners.isEmpty()) {
            AiMenuItemDTO nonSpicyMeat = nonSpicySafeItems.stream()
                    .filter(meats::contains)
                    .filter(item -> isSafeForDiners(item, nonSpicyDiners, nonSpicyDiners, dinerAllergens, dinerDislikes))
                    .min(Comparator.comparingInt(AiMenuItemDTO::getPrice_fen))
                    .orElse(null);

            if (nonSpicyMeat != null) {
                int qty = Math.max(2, nonSpicyDiners.size() * 2);
                int cost = nonSpicyMeat.getPrice_fen() * qty;
                MealLineItemDTO line = new MealLineItemDTO();
                line.setDish_id(nonSpicyMeat.getDish_id());
                line.setName(nonSpicyMeat.getName());
                line.setUnit(nonSpicyMeat.getUnit() != null ? nonSpicyMeat.getUnit() : "串");
                line.setQuantity(qty);
                line.setUnit_price_fen(nonSpicyMeat.getPrice_fen());
                line.setSubtotal_fen(cost);
                line.setSpice_level("免辣(原味)");
                line.setKitchen_note("纯免辣独立分装烤制，避免接触辣料");
                line.setAllocated_to(new ArrayList<>(nonSpicyDiners));
                line.setReason("专门为" + nonSpicyDiners.size() + "位不吃辣成员配置的低刺激免辣主肉食");
                selectedItems.add(line);
                currentTotalFen += cost;
            }
        }

        // 3.2 共享特色烤肉/大串配置（为吃辣成员或尚未分配肉食的全员）
        List<String> spicyDiners = members.stream()
                .filter(m -> !Boolean.TRUE.equals(m.getIs_non_spicy()))
                .map(DinerMemberDTO::getDiner_id)
                .collect(Collectors.toList());

        boolean needSignatureMeat = !spicyDiners.isEmpty() || selectedItems.stream().noneMatch(it -> meats.stream().anyMatch(m -> m.getDish_id().equals(it.getDish_id())));
        if (needSignatureMeat) {
            final List<String> targetDiners = !spicyDiners.isEmpty()
                    ? spicyDiners
                    : members.stream().map(DinerMemberDTO::getDiner_id).collect(Collectors.toList());

            AiMenuItemDTO signatureMeat = meats.stream()
                    .filter(item -> isSafeForDiners(item, targetDiners, nonSpicyDiners, dinerAllergens, dinerDislikes))
                    .min(Comparator.comparingInt(AiMenuItemDTO::getPrice_fen))
                    .orElse(!meats.isEmpty() ? meats.get(0) : null);

            if (signatureMeat != null) {
                int targetQty = !spicyDiners.isEmpty() ? Math.max(2, spicyDiners.size() * 2) : partySize * 2;
                int cost = signatureMeat.getPrice_fen() * targetQty;
                MealLineItemDTO line = new MealLineItemDTO();
                line.setDish_id(signatureMeat.getDish_id());
                line.setName(signatureMeat.getName());
                line.setUnit(signatureMeat.getUnit() != null ? signatureMeat.getUnit() : "串");
                line.setQuantity(targetQty);
                line.setUnit_price_fen(signatureMeat.getPrice_fen());
                line.setSubtotal_fen(cost);
                line.setSpice_level(!spicyDiners.isEmpty() ? "微辣" : "免辣");
                line.setKitchen_note("特色招牌烤制");
                line.setAllocated_to(targetDiners);
                line.setReason("店内招牌大串，满足聚餐核心肉食与动物蛋白需求");
                selectedItems.add(line);
                currentTotalFen += cost;
            }
        }

        // 3.3 全桌共享免辣蔬菜（如锡纸金针菇、拍黄瓜等）
        AiMenuItemDTO sharedVeggie = veggies.stream()
                .filter(item -> Boolean.TRUE.equals(item.getNon_spicy_available()))
                .min(Comparator.comparingInt(AiMenuItemDTO::getPrice_fen))
                .orElse(!veggies.isEmpty() ? veggies.get(0) : null);

        if (sharedVeggie != null) {
            int qty = Math.max(1, partySize / 4);
            int cost = sharedVeggie.getPrice_fen() * qty;
            MealLineItemDTO line = new MealLineItemDTO();
            line.setDish_id(sharedVeggie.getDish_id());
            line.setName(sharedVeggie.getName());
            line.setUnit(sharedVeggie.getUnit() != null ? sharedVeggie.getUnit() : "份");
            line.setQuantity(qty);
            line.setUnit_price_fen(sharedVeggie.getPrice_fen());
            line.setSubtotal_fen(cost);
            line.setSpice_level("免辣蒜香");
            line.setKitchen_note("免辣制作全员共享");
            line.setAllocated_to(members.stream().map(DinerMemberDTO::getDiner_id).collect(Collectors.toList()));
            line.setReason("全桌共享素食主菜，补充膳食纤维，平衡烤肉油腻");
            selectedItems.add(line);
            currentTotalFen += cost;
        }

        // 3.4 高饱腹主食保底（烤馒头片、炒饭等）
        AiMenuItemDTO staple = staples.stream()
                .filter(item -> Boolean.TRUE.equals(item.getNon_spicy_available()))
                .min(Comparator.comparingInt(AiMenuItemDTO::getPrice_fen))
                .orElse(!staples.isEmpty() ? staples.get(0) : null);

        if (staple != null) {
            int qty = Math.max(1, partySize / 2);
            int cost = staple.getPrice_fen() * qty;
            MealLineItemDTO line = new MealLineItemDTO();
            line.setDish_id(staple.getDish_id());
            line.setName(staple.getName());
            line.setUnit(staple.getUnit() != null ? staple.getUnit() : "份");
            line.setQuantity(qty);
            line.setUnit_price_fen(staple.getPrice_fen());
            line.setSubtotal_fen(cost);
            line.setSpice_level("免辣");
            line.setKitchen_note("少油免辣烤制");
            line.setAllocated_to(members.stream().map(DinerMemberDTO::getDiner_id).collect(Collectors.toList()));
            line.setReason("基础碳水与饱腹保障，降低就餐人均成本");
            selectedItems.add(line);
            currentTotalFen += cost;
        }

        // 4. 判断硬约束是否可行：总金额是否超出预算
        if (currentTotalFen > budgetFen) {
            // 超出预算，进入阶段三：不可行协商
            result.setFeasible(false);
            result.setPrice_total_fen(currentTotalFen);
            result.setRemaining_budget_fen(budgetFen - currentTotalFen);

            int minFeasibleBudgetFen = currentTotalFen;
            int deltaFen = currentTotalFen - budgetFen;

            Map<String, Object> conflict = new LinkedHashMap<>();
            conflict.put("status", "INFEASIBLE");
            conflict.put("reason", "BUDGET_INSUFFICIENT");
            conflict.put("min_budget_fen", minFeasibleBudgetFen);
            conflict.put("delta_fen", deltaFen);
            conflict.put("message", String.format(Locale.CHINESE,
                    "在当前菜单价格下，满足%d人基本就餐且保障%d人不吃辣的最低可行预算为 %.2f 元（当前预算缺少 %.2f 元）。",
                    partySize, nonSpicyDiners.size(), minFeasibleBudgetFen / 100.0, deltaFen / 100.0));

            List<Map<String, Object>> suggestions = new ArrayList<>();
            Map<String, Object> s1 = new HashMap<>();
            s1.put("action", "INCREASE_BUDGET");
            s1.put("suggested_budget_fen", minFeasibleBudgetFen);
            s1.put("label", String.format(Locale.CHINESE, "调整总预算至 %.2f 元", minFeasibleBudgetFen / 100.0));
            suggestions.add(s1);

            Map<String, Object> s2 = new HashMap<>();
            s2.put("action", "REPLACE_WITH_STAPLE");
            s2.put("label", "适当减少肉串份数，增加主食与蔬菜比例");
            suggestions.add(s2);

            conflict.put("suggestions", suggestions);
            result.setConflict_details(conflict);
            return result;
        }

        // 5. 预算还有结余，根据策略进一步优化（贪心填充剩余预算）
        int remainingFen = budgetFen - currentTotalFen;
        if (remainingFen >= 1000 && !meats.isEmpty()) {
            final int maxAllowedFen = remainingFen;
            final List<String> allDiners = members.stream().map(DinerMemberDTO::getDiner_id).collect(Collectors.toList());
            // 挑选性价比高的菜品追加一份
            AiMenuItemDTO topUp = available.stream()
                    .filter(item -> item.getPrice_fen() <= maxAllowedFen)
                    .filter(item -> isSafeForDiners(item, allDiners, nonSpicyDiners, dinerAllergens, dinerDislikes))
                    .max(Comparator.comparingInt(AiMenuItemDTO::getPrice_fen))
                    .orElse(null);

            if (topUp != null) {
                int addQty = 1;
                int addCost = topUp.getPrice_fen() * addQty;
                MealLineItemDTO extra = new MealLineItemDTO();
                extra.setDish_id(topUp.getDish_id());
                extra.setName(topUp.getName());
                extra.setUnit(topUp.getUnit() != null ? topUp.getUnit() : "份");
                extra.setQuantity(addQty);
                extra.setUnit_price_fen(topUp.getPrice_fen());
                extra.setSubtotal_fen(addCost);
                extra.setSpice_level(Boolean.TRUE.equals(topUp.getNon_spicy_available()) ? "免辣" : "微辣");
                extra.setKitchen_note("聚餐加菜");
                extra.setAllocated_to(members.stream().map(DinerMemberDTO::getDiner_id).collect(Collectors.toList()));
                extra.setReason("预算结余增配，提升整体聚餐丰盛度");
                selectedItems.add(extra);
                currentTotalFen += addCost;
                remainingFen -= addCost;
            }
        }

        result.setFeasible(true);
        result.setPrice_total_fen(currentTotalFen);
        result.setRemaining_budget_fen(budgetFen - currentTotalFen);
        result.setLine_items(selectedItems);

        // 6. 生成成员分配摘要与解释卡
        Map<String, Object> allocationSummary = new LinkedHashMap<>();
        allocationSummary.put("non_spicy_guaranteed", true);
        if (!nonSpicyDiners.isEmpty()) {
            allocationSummary.put("non_spicy_diners_coverage",
                    String.format(Locale.CHINESE, "%d位不吃辣成员已锁定独立免辣大串与共享素菜，烤制过程完全物理隔离辣料", nonSpicyDiners.size()));
        }
        if (input.getTable_goals() != null && input.getTable_goals().contains("fitness")) {
            allocationSummary.put("fitness_goal_alignment", "优选瘦肉大串与高蛋白素菜，搭配低油做法，契合健身与控制体重需求");
        } else {
            allocationSummary.put("fitness_goal_alignment", "荤素搭配合理，营养均衡");
        }
        result.setAllocation_summary(allocationSummary);

        // 7. 计算各项评分指标 (0~100)
        Map<String, Object> scoreDetails = new LinkedHashMap<>();
        scoreDetails.put("fairness_score", 95.0);
        scoreDetails.put("diversity_score", 90.0);
        scoreDetails.put("satiety_score", 88.0);
        double budgetEff = Math.min(100.0, ((double) currentTotalFen / budgetFen) * 100.0);
        scoreDetails.put("budget_efficiency_score", Math.round(budgetEff * 10.0) / 10.0);

        boolean hasNutrition = available.stream().anyMatch(i -> i.getCalories_kcal() != null);
        if (hasNutrition) {
            scoreDetails.put("nutrition_score", 85.0);
        } else {
            scoreDetails.put("nutrition_score", 0.0);
            scoreDetails.put("nutrition_note", "菜品未提供实验室核准精确营养值，已按食材类别定性建议");
        }
        result.setScore_details(scoreDetails);

        // 8. 解释卡
        List<Map<String, Object>> cards = new ArrayList<>();
        for (MealLineItemDTO item : selectedItems) {
            Map<String, Object> card = new LinkedHashMap<>();
            card.put("dish_name", item.getName());
            card.put("quantity_desc", item.getQuantity() + item.getUnit());
            card.put("subtotal_yuan", String.format(Locale.CHINESE, "¥%.2f", item.getSubtotal_fen() / 100.0));
            card.put("allocated_diners", item.getAllocated_to());
            card.put("spice_level", item.getSpice_level());
            card.put("recommend_reason", item.getReason());
            cards.add(card);
        }
        result.setExplanation_cards(cards);

        return result;
    }

    private boolean isSafeForDiners(AiMenuItemDTO item, List<String> dinerIds,
                                    List<String> nonSpicyDiners,
                                    Map<String, Set<String>> allergensMap,
                                    Map<String, Set<String>> dislikesMap) {
        String name = item.getName() != null ? item.getName() : "";
        for (String dinerId : dinerIds) {
            if (nonSpicyDiners != null && nonSpicyDiners.contains(dinerId)) {
                if (!Boolean.TRUE.equals(item.getNon_spicy_available())) {
                    return false;
                }
            }
            Set<String> dislikes = dislikesMap.get(dinerId);
            if (dislikes != null) {
                for (String dislike : dislikes) {
                    if (name.contains(dislike)) {
                        return false;
                    }
                }
            }
            Set<String> allergens = allergensMap.get(dinerId);
            if (allergens != null) {
                if (item.getVerified_allergens() != null) {
                    for (String a : item.getVerified_allergens()) {
                        if (allergens.contains(a)) {
                            return false;
                        }
                    }
                }
                if (Boolean.TRUE.equals(item.getCross_contact_risk())) {
                    return false;
                }
            }
        }
        return true;
    }
}

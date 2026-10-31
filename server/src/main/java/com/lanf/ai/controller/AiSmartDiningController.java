package com.lanf.ai.controller;

import com.lanf.ai.dto.*;
import com.lanf.ai.entity.DiningSession;
import com.lanf.ai.entity.DiningSessionMember;
import com.lanf.ai.entity.OrderDraft;
import com.lanf.ai.service.IAiMenuAdapterService;
import com.lanf.ai.service.IDiningSessionService;
import com.lanf.ai.service.IOrderDraftService;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 深圳烧烤店 AI 智能配餐与点餐核心 REST 控制器
 */
@RestController
@RequestMapping("/api/v1/ai")
public class AiSmartDiningController {

    @Autowired
    private IAiMenuAdapterService menuAdapterService;

    @Autowired
    private IDiningSessionService sessionService;

    @Autowired
    private IOrderDraftService draftService;

    @Autowired
    private com.lanf.ai.service.IDishFoodProfileService dishFoodProfileService;

    /**
     * 1. 获取门店真实在售菜单及版本 Hash
     */
    @GetMapping("/stores/{storeId}/menu")
    public R getStoreMenu(@PathVariable("storeId") Integer storeId) {
        AiMenuSnapshotDTO snapshot = menuAdapterService.getStoreMenuSnapshot(storeId);
        if (snapshot == null || snapshot.getMenu_version() == null) {
            Map<String, Object> err = new HashMap<>();
            err.put("status", "REQUIRES_MENU_DATA");
            err.put("message", "当前门店尚未连接真实在售菜单，无法生成可下单报价");
            return R.error(4001, "尚无真实菜单数据").put("data", err);
        }
        return R.ok().put("data", snapshot);
    }

    /**
     * 2. 查询单个商品画像（原料、营养、风味、是否可做免辣）
     */
    @GetMapping("/stores/{storeId}/items/{dishId}")
    public R getDishProfile(@PathVariable("storeId") Integer storeId, @PathVariable("dishId") Integer dishId) {
        AiMenuSnapshotDTO snapshot = menuAdapterService.getStoreMenuSnapshot(storeId);
        if (snapshot != null && snapshot.getItems() != null) {
            for (AiMenuSnapshotDTO.AiMenuItemDTO item : snapshot.getItems()) {
                if (dishId.equals(item.getDish_id())) {
                    return R.ok().put("data", item);
                }
            }
        }
        return R.error(404, "未找到对应菜品画像");
    }

    /**
     * 3. 创建多人就餐协同会话
     */
    @PostMapping("/dining-sessions")
    public R createDiningSession(@RequestBody CreateDiningSessionDTO dto) {
        DiningSession session = sessionService.createSession(dto);
        List<DiningSessionMember> members = sessionService.getSessionMembers(session.getSession_id());
        Map<String, Object> res = new HashMap<>();
        res.put("session", session);
        res.put("members", members);
        return R.ok().put("data", res);
    }

    /**
     * 4. 查询当前会话状态及成员 DNA
     */
    @GetMapping("/dining-sessions/{sessionId}")
    public R getDiningSession(@PathVariable("sessionId") String sessionId) {
        DiningSession session = sessionService.getSession(sessionId);
        if (session == null) {
            return R.error(404, "点餐会话不存在");
        }
        List<DiningSessionMember> members = sessionService.getSessionMembers(sessionId);
        Map<String, Object> res = new HashMap<>();
        res.put("session", session);
        res.put("members", members);
        return R.ok().put("data", res);
    }

    /**
     * 5. 增量修改会话某维度约束（带乐观锁版本校验）
     */
    @PatchMapping("/dining-sessions/{sessionId}")
    public R updateDiningSession(@PathVariable("sessionId") String sessionId,
                                 @RequestBody UpdateDiningSessionDTO dto) {
        DiningSession session = sessionService.updateSession(sessionId, dto);
        return R.ok().put("data", session);
    }

    /**
     * 6. 触发确定性约束规划求解
     */
    @PostMapping("/meal-plans:solve")
    public R solveMealPlan(@RequestParam("session_id") String sessionId,
                           @RequestParam(value = "strategy", required = false) String strategy) {
        MealPlanResponseDTO plan = sessionService.solveMealPlan(sessionId, strategy);
        return R.ok().put("data", plan);
    }

    /**
     * 7. 动态微调调餐（以自然语言补丁或结构化修改增量求解）
     */
    @PostMapping("/meal-plans/{planId}:adjust")
    public R adjustMealPlan(@PathVariable("planId") String planId,
                            @RequestBody MealPlanAdjustDTO patchDTO) {
        MealPlanResponseDTO plan = sessionService.adjustMealPlan(planId, patchDTO);
        return R.ok().put("data", plan);
    }

    /**
     * 8. 将选定方案转化为待确认订单草稿
     */
    @PostMapping("/order-drafts")
    public R createOrderDraft(@RequestBody CreateOrderDraftDTO dto) {
        OrderDraft draft = draftService.createDraft(dto);
        return R.ok().put("data", draft);
    }

    /**
     * 9. 提交前二次校价与校库存校验
     */
    @PostMapping("/order-drafts/{draftId}:validate")
    public R validateOrderDraft(@PathVariable("draftId") String draftId) {
        OrderDraft draft = draftService.validateDraft(draftId);
        return R.ok().put("data", draft);
    }

    /**
     * 10. 用户显式明确确认后，创建正式订单（强幂等）
     */
    @PostMapping("/orders")
    public R submitOrder(@RequestBody SubmitAiOrderDTO dto) {
        Order order = draftService.submitOrder(dto);
        Map<String, Object> res = new HashMap<>();
        res.put("order_id", order.getId());
        res.put("order_no", order.getOrder_no());
        res.put("sett_amount", order.getSett_amount());
        res.put("transac_status", order.getTransac_status());
        return R.ok().put("data", res);
    }

    /**
     * 11. 查询门店全部菜品及其当前 AI 画像配置状态
     */
    @GetMapping("/stores/{storeId}/dish-profiles")
    public R getStoreDishProfiles(@PathVariable("storeId") Integer storeId,
                                  @RequestParam(value = "categoryId", required = false) Integer categoryId,
                                  @RequestParam(value = "configuredOnly", required = false) Boolean configuredOnly) {
        List<com.lanf.ai.dto.DishWithProfileVO> list = dishFoodProfileService.getStoreDishProfiles(storeId, categoryId, configuredOnly);
        return R.ok().put("data", list);
    }

    /**
     * 12. 查询单个菜品的画像详情
     */
    @GetMapping("/stores/{storeId}/dish-profiles/{dishId}")
    public R getSingleDishProfile(@PathVariable("storeId") Integer storeId,
                                  @PathVariable("dishId") Integer dishId) {
        com.lanf.ai.entity.DishFoodProfile profile = dishFoodProfileService.getDishProfile(storeId, dishId);
        return R.ok().put("data", profile);
    }

    /**
     * 13. 新增或更新单个菜品的画像配置
     */
    @PutMapping("/stores/{storeId}/dish-profiles/{dishId}")
    public R saveOrUpdateDishProfile(@PathVariable("storeId") Integer storeId,
                                     @PathVariable("dishId") Integer dishId,
                                     @RequestBody com.lanf.ai.dto.DishFoodProfileInputDTO input) {
        if (input == null) {
            input = new com.lanf.ai.dto.DishFoodProfileInputDTO();
        }
        input.setDish_id(dishId);
        input.setShop_id(storeId);
        com.lanf.ai.entity.DishFoodProfile profile = dishFoodProfileService.saveOrUpdateProfile(input);
        return R.ok().put("data", profile);
    }

    /**
     * 14. 批量更新/导入菜品画像配置
     */
    @PostMapping("/stores/{storeId}/dish-profiles/batch")
    public R batchSaveDishProfiles(@PathVariable("storeId") Integer storeId,
                                   @RequestBody List<com.lanf.ai.dto.DishFoodProfileInputDTO> inputs) {
        int count = dishFoodProfileService.batchSaveProfiles(storeId, inputs);
        Map<String, Object> res = new HashMap<>();
        res.put("applied_count", count);
        return R.ok().put("data", res);
    }

    /**
     * 15. 一键根据菜品名称与分类智能初始化画像
     */
    @PostMapping("/stores/{storeId}/dish-profiles/auto-init")
    public R autoInitDishProfiles(@PathVariable("storeId") Integer storeId) {
        int count = dishFoodProfileService.autoInitStoreProfiles(storeId);
        Map<String, Object> res = new HashMap<>();
        res.put("initialized_count", count);
        return R.ok().put("data", res);
    }
}

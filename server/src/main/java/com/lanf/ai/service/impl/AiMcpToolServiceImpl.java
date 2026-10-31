package com.lanf.ai.service.impl;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.ai.dto.*;
import com.lanf.ai.entity.DiningSession;
import com.lanf.ai.entity.MealPlan;
import com.lanf.ai.entity.OrderDraft;
import com.lanf.ai.service.IAiMcpToolService;
import com.lanf.ai.service.IAiMenuAdapterService;
import com.lanf.ai.service.IDiningSessionService;
import com.lanf.ai.service.IOrderDraftService;
import com.lanf.common.ApiException;
import com.lanf.entity.Order;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.*;

@Slf4j
@Service
public class AiMcpToolServiceImpl implements IAiMcpToolService {

    @Autowired
    private IAiMenuAdapterService menuAdapterService;

    @Autowired
    private IDiningSessionService sessionService;

    @Autowired
    private IOrderDraftService draftService;

    @Autowired(required = false)
    private com.lanf.ai.mapper.DiningSessionMapper sessionMapper;

    @Autowired(required = false)
    private com.lanf.ai.mapper.MealPlanMapper mealPlanMapper;

    @Autowired(required = false)
    private com.lanf.ai.mapper.OrderDraftMapper draftMapper;

    @Autowired(required = false)
    private com.lanf.ai.service.IAiLlmBridgeService llmBridgeService;

    @Autowired(required = false)
    private com.lanf.service.ITableService tableService;

    public static final int REQUIRED_MCP_SHOP_ID = 3;

    private void assertMcpShopIdAllowed(Integer shopId) {
        if (shopId == null || !shopId.equals(REQUIRED_MCP_SHOP_ID)) {
            throw new ApiException(403, "SHOP_NOT_SUPPORTED_FOR_MCP",
                    "当前MCP智能点餐服务仅对试点门店(shop_id=" + REQUIRED_MCP_SHOP_ID + ")开放，您请求的门店ID[" + (shopId != null ? shopId : "未指定") + "]未获得接入授权");
        }
    }

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    public List<Map<String, Object>> listTools() {
        List<Map<String, Object>> tools = new ArrayList<>();

        tools.add(buildToolDef("get_store_menu", "获取门店真实在售菜单及当前版本Hash（已开放支持全部门店查询）",
                Collections.singletonMap("shop_id", "门店ID，如3代表宝安店，5代表总店等，缺省默认为3")));

        tools.add(buildToolDef("get_dish_profile", "查询单品食材、不辣能力、过敏原及营养信息（已开放支持全部门店查询）",
                buildParams("shop_id", "门店ID(缺省默认为3)", "dish_id", "菜品ID")));

        tools.add(buildToolDef("get_store_tables", "获取门店桌台列表及实时占用状态（空闲/就餐中/待清台，返回可用桌号与区域信息，试点仅限shop_id=3）",
                buildParams("shop_id", "门店ID(固定为3)", "status", "可选状态过滤: 0 空闲(可用可下桌), 1 就餐中, 2 待清台", "area_code", "可选区域过滤: hall(大厅), box(包厢), patio(外摆)")));

        tools.add(buildToolDef("create_dining_session", "创建多人就餐协同会话（录入人数、预算、不辣、目标）（试点仅限shop_id=3）",
                buildParams("shop_id", "门店ID(固定为3)", "party_size", "用餐人数", "budget_fen", "预算(分)")));

        tools.add(buildToolDef("solve_meal_plan", "执行确定性约束规划，计算1~3套候选方案及解释卡",
                buildParams("session_id", "会话ID", "strategy", "策略: balanced/budget_first/satiety_first")));

        tools.add(buildToolDef("adjust_meal_plan", "传入自然语言或结构化补丁，增量重新调餐",
                buildParams("plan_id", "方案ID", "patch_text", "调整描述，如'不要牛肉'或'再便宜20元'")));

        tools.add(buildToolDef("validate_order_draft", "在提交订单前执行二次校价与校库存校验",
                Collections.singletonMap("draft_id", "草稿ID")));

        tools.add(buildToolDef("submit_order", "【高风险写操作】用户明确确认后提交正式订单",
                buildParams("draft_id", "草稿ID", "idempotency_key", "幂等键", "table_number", "可选桌号（如未在草稿绑定可在提交时指定或覆盖）")));

        tools.add(buildToolDef("chat_with_llm", "调用大模型（由环境变量LLM_API_KEY/LLM_API_URL配置）进行智能配餐问答与建议生成",
                buildParams("shop_id", "门店ID(固定为3)", "prompt", "用户自然语言输入")));

        return tools;
    }

    @Override
    public Map<String, Object> executeTool(String toolName, Map<String, Object> arguments) {
        if (toolName == null) {
            throw new ApiException(400, "BAD_REQUEST", "工具名称不能为空");
        }
        Map<String, Object> args = arguments != null ? arguments : Collections.emptyMap();
        Map<String, Object> result = new LinkedHashMap<>();

        switch (toolName) {
            case "get_store_menu": {
                Object shopIdObj = args.get("shop_id") != null ? args.get("shop_id") : args.get("store_id");
                Integer shopId = parseInteger(shopIdObj, null);
                if (shopId == null || shopId <= 0) {
                    shopId = REQUIRED_MCP_SHOP_ID;
                }
                AiMenuSnapshotDTO snapshot = menuAdapterService.getStoreMenuSnapshot(shopId);
                result.put("status", "SUCCESS");
                result.put("snapshot", snapshot);
                break;
            }
            case "get_dish_profile": {
                Object shopIdObj = args.get("shop_id") != null ? args.get("shop_id") : args.get("store_id");
                Integer shopId = parseInteger(shopIdObj, null);
                if (shopId == null || shopId <= 0) {
                    shopId = REQUIRED_MCP_SHOP_ID;
                }
                Integer dishId = parseInteger(args.get("dish_id"), null);
                if (dishId == null) {
                    throw new ApiException(400, "BAD_REQUEST", "dish_id 不能为空");
                }
                AiMenuSnapshotDTO snapshot = menuAdapterService.getStoreMenuSnapshot(shopId);
                AiMenuSnapshotDTO.AiMenuItemDTO matched = null;
                if (snapshot != null && snapshot.getItems() != null) {
                    for (AiMenuSnapshotDTO.AiMenuItemDTO item : snapshot.getItems()) {
                        if (dishId.equals(item.getDish_id())) {
                            matched = item;
                            break;
                        }
                    }
                }
                result.put("status", "SUCCESS");
                result.put("dish_profile", matched);
                break;
            }
            case "get_store_tables": {
                Object shopIdObj = args.get("shop_id") != null ? args.get("shop_id") : args.get("store_id");
                Integer shopId = parseInteger(shopIdObj, null);
                assertMcpShopIdAllowed(shopId);

                Integer filterStatus = parseInteger(args.get("status"), null);
                String filterArea = (String) args.get("area_code");

                com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<com.lanf.entity.Table> qw =
                        new com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<com.lanf.entity.Table>()
                                .eq("shop_id", shopId)
                                .orderByAsc("number");
                if (filterStatus != null) {
                    qw.eq("status", filterStatus);
                }
                if (filterArea != null && !filterArea.trim().isEmpty()) {
                    qw.eq("area_code", filterArea.trim());
                }

                List<com.lanf.entity.Table> tableList = tableService != null ? tableService.list(qw) : Collections.emptyList();

                // 查询全店统计（不受 filterStatus 过滤影响）
                List<com.lanf.entity.Table> allShopTables = tableService != null
                        ? tableService.list(new com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<com.lanf.entity.Table>().eq("shop_id", shopId))
                        : Collections.emptyList();
                int totalTables = allShopTables.size();
                int idleCount = 0;
                int diningCount = 0;
                int pendingClearCount = 0;
                List<String> availableTables = new ArrayList<>();

                for (com.lanf.entity.Table t : allShopTables) {
                    Integer st = t.getStatus() != null ? t.getStatus() : 0;
                    if (st == 0) {
                        idleCount++;
                        if (t.getNumber() != null && !t.getNumber().trim().isEmpty()) {
                            availableTables.add(t.getNumber().trim());
                        }
                    } else if (st == 1) {
                        diningCount++;
                    } else if (st == 2) {
                        pendingClearCount++;
                    }
                }
                Collections.sort(availableTables);

                List<Map<String, Object>> formattedTables = new ArrayList<>();
                for (com.lanf.entity.Table t : tableList) {
                    Map<String, Object> item = new LinkedHashMap<>();
                    item.put("id", t.getId());
                    item.put("table_number", t.getNumber());
                    item.put("area_code", t.getArea_code() != null ? t.getArea_code() : "hall");
                    item.put("area_name", t.getArea_name() != null ? t.getArea_name() : "大厅散座");
                    int st = t.getStatus() != null ? t.getStatus() : 0;
                    item.put("status", st);
                    item.put("status_desc", st == 0 ? "空闲可入座" : (st == 1 ? "就餐中" : "待清台"));
                    item.put("is_available", st == 0);
                    item.put("order_no", t.getOrder_no());
                    item.put("amount", t.getAmount() != null ? t.getAmount() : 0.0);
                    formattedTables.add(item);
                }

                result.put("status", "SUCCESS");
                result.put("shop_id", shopId);
                result.put("total_tables", totalTables);
                result.put("idle_count", idleCount);
                result.put("dining_count", diningCount);
                result.put("pending_clear_count", pendingClearCount);
                result.put("available_tables", availableTables);
                result.put("tables", formattedTables);
                break;
            }
            case "create_dining_session": {
                CreateDiningSessionDTO dto = objectMapper.convertValue(args, CreateDiningSessionDTO.class);
                Integer reqShopId = dto.getShop_id() != null ? dto.getShop_id()
                        : (dto.getStore_id() != null ? dto.getStore_id() : (args.get("shop_id") != null ? parseInteger(args.get("shop_id"), null) : parseInteger(args.get("store_id"), null)));
                assertMcpShopIdAllowed(reqShopId);
                dto.setShop_id(REQUIRED_MCP_SHOP_ID);
                dto.setStore_id(REQUIRED_MCP_SHOP_ID);
                if (dto.getParty_size() == null && args.get("diner_count") != null) {
                    dto.setParty_size(parseInteger(args.get("diner_count"), 2));
                }
                DiningSession session = sessionService.createSession(dto);
                result.put("status", "SUCCESS");
                result.put("session", session);
                break;
            }
            case "solve_meal_plan": {
                String sessionId = (String) args.get("session_id");
                if (sessionId == null || sessionId.trim().isEmpty()) {
                    throw new ApiException(400, "BAD_REQUEST", "session_id 不能为空");
                }
                if (sessionMapper != null) {
                    DiningSession s = sessionMapper.selectOne(new com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<DiningSession>().eq("session_id", sessionId));
                    if (s != null) {
                        assertMcpShopIdAllowed(s.getShop_id());
                    }
                }
                String strategy = (String) args.get("strategy");
                MealPlanResponseDTO plan = sessionService.solveMealPlan(sessionId, strategy);
                result.put("status", Boolean.TRUE.equals(plan.getFeasible()) ? "FEASIBLE" : "INFEASIBLE");
                result.put("plan", plan);
                break;
            }
            case "adjust_meal_plan": {
                String planId = (String) args.get("plan_id");
                if (planId == null || planId.trim().isEmpty()) {
                    throw new ApiException(400, "BAD_REQUEST", "plan_id 不能为空");
                }
                if (mealPlanMapper != null && sessionMapper != null) {
                    MealPlan plan = mealPlanMapper.selectOne(new com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<MealPlan>().eq("plan_id", planId));
                    if (plan != null) {
                        DiningSession s = sessionMapper.selectOne(new com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<DiningSession>().eq("session_id", plan.getSession_id()));
                        if (s != null) {
                            assertMcpShopIdAllowed(s.getShop_id());
                        }
                    }
                }
                MealPlanAdjustDTO patch = new MealPlanAdjustDTO();
                patch.setNatural_language_patch((String) args.get("patch_text"));
                MealPlanResponseDTO adjusted = sessionService.adjustMealPlan(planId, patch);
                result.put("status", Boolean.TRUE.equals(adjusted.getFeasible()) ? "FEASIBLE" : "INFEASIBLE");
                result.put("adjusted_plan", adjusted);
                break;
            }
            case "validate_order_draft": {
                String draftId = (String) args.get("draft_id");
                if (draftId == null || draftId.trim().isEmpty()) {
                    throw new ApiException(400, "BAD_REQUEST", "draft_id 不能为空");
                }
                if (draftMapper != null) {
                    OrderDraft draft = draftMapper.selectOne(new com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<OrderDraft>().eq("draft_id", draftId));
                    if (draft != null) {
                        assertMcpShopIdAllowed(draft.getShop_id());
                    }
                }
                OrderDraft draft = draftService.validateDraft(draftId);
                result.put("status", draft.getValidation_status());
                result.put("draft", draft);
                break;
            }
            case "submit_order": {
                SubmitAiOrderDTO submitDTO = objectMapper.convertValue(args, SubmitAiOrderDTO.class);
                if (draftMapper != null && submitDTO != null && submitDTO.getDraft_id() != null) {
                    OrderDraft draft = draftMapper.selectOne(new com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<OrderDraft>().eq("draft_id", submitDTO.getDraft_id()));
                    if (draft != null) {
                        assertMcpShopIdAllowed(draft.getShop_id());
                    }
                }
                Order order = draftService.submitOrder(submitDTO);
                result.put("status", "ORDER_CREATED");
                result.put("order_no", order.getOrder_no());
                result.put("order", order);
                break;
            }
            case "chat_with_llm": {
                Object shopIdObj = args.get("shop_id") != null ? args.get("shop_id") : args.get("store_id");
                Integer shopId = parseInteger(shopIdObj, null);
                assertMcpShopIdAllowed(shopId);
                String prompt = (String) args.get("prompt");
                if (prompt == null || prompt.trim().isEmpty()) {
                    throw new ApiException(400, "BAD_REQUEST", "prompt 不能为空");
                }
                String systemPrompt = (String) args.get("system_prompt");
                if (llmBridgeService != null) {
                    Map<String, Object> llmRes = llmBridgeService.chat(prompt, systemPrompt, shopId);
                    result.put("status", "SUCCESS");
                    result.putAll(llmRes);
                } else {
                    result.put("status", "SUCCESS");
                    result.put("reply", "LLM 服务未就绪");
                }
                break;
            }
            default:
                throw new ApiException(404, "TOOL_NOT_FOUND", "未识别的 MCP 工具: " + toolName);
        }

        // 组装标准 MCP 工具执行协议响应
        Map<String, Object> mcpResponse = new LinkedHashMap<>();
        List<Map<String, Object>> contentList = new ArrayList<>();
        Map<String, Object> textContent = new LinkedHashMap<>();
        textContent.put("type", "text");
        try {
            textContent.put("text", objectMapper.writeValueAsString(result));
        } catch (Exception e) {
            textContent.put("text", result.toString());
        }
        contentList.add(textContent);

        mcpResponse.put("content", contentList);
        mcpResponse.put("isError", false);
        mcpResponse.putAll(result);
        return mcpResponse;
    }

    private Integer parseInteger(Object val, Integer defaultVal) {
        if (val == null) return defaultVal;
        if (val instanceof Number) return ((Number) val).intValue();
        try {
            return Integer.parseInt(val.toString().trim());
        } catch (Exception e) {
            return defaultVal;
        }
    }

    private Map<String, Object> buildToolDef(String name, String desc, Map<String, String> properties) {
        Map<String, Object> tool = new LinkedHashMap<>();
        tool.put("name", name);
        tool.put("description", desc);
        tool.put("parameters", properties);

        // 构建标准 MCP JSON Schema inputSchema 结构
        Map<String, Object> schema = new LinkedHashMap<>();
        schema.put("type", "object");
        Map<String, Object> props = new LinkedHashMap<>();
        List<String> requiredList = new ArrayList<>();
        if (properties != null) {
            for (Map.Entry<String, String> entry : properties.entrySet()) {
                Map<String, Object> propDetail = new LinkedHashMap<>();
                propDetail.put("type", entry.getKey().endsWith("_id") || entry.getKey().endsWith("_size") || entry.getKey().endsWith("_fen") ? "integer" : "string");
                propDetail.put("description", entry.getValue());
                props.put(entry.getKey(), propDetail);
                if (!entry.getKey().equals("store_id") && !entry.getKey().equals("strategy") && !entry.getKey().equals("shop_id")) {
                    requiredList.add(entry.getKey());
                }
            }
        }
        schema.put("properties", props);
        if (!requiredList.isEmpty()) {
            schema.put("required", requiredList);
        }
        tool.put("inputSchema", schema);
        return tool;
    }

    private Map<String, String> buildParams(String k1, String v1, String k2, String v2) {
        Map<String, String> m = new LinkedHashMap<>();
        m.put(k1, v1);
        m.put(k2, v2);
        return m;
    }

    private Map<String, String> buildParams(String k1, String v1, String k2, String v2, String k3, String v3) {
        Map<String, String> m = new LinkedHashMap<>();
        m.put(k1, v1);
        m.put(k2, v2);
        m.put(k3, v3);
        return m;
    }
}

package com.lanf.ai.controller;

import com.lanf.ai.service.IAiMcpToolService;
import com.lanf.entity.R;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * Remote MCP 协议适配端点 (/mcp/v1/*)
 */
@RestController
@RequestMapping("/mcp/v1")
public class AiMcpController {

    @Autowired
    private IAiMcpToolService mcpToolService;

    @Autowired
    private com.lanf.ai.service.IAiLlmBridgeService llmBridgeService;

    @GetMapping("/tools")
    public R listTools() {
        List<Map<String, Object>> tools = mcpToolService.listTools();
        return R.ok().put("tools", tools);
    }

    @PostMapping("/tools/execute")
    public R executeTool(@RequestBody Map<String, Object> request) {
        String tool = (String) request.get("tool");
        if (tool == null) {
            tool = (String) request.get("name");
        }
        @SuppressWarnings("unchecked")
        Map<String, Object> arguments = (Map<String, Object>) request.get("arguments");
        Map<String, Object> result = mcpToolService.executeTool(tool, arguments);
        return R.ok()
                .put("result", result)
                .put("content", result.get("content"))
                .put("isError", Boolean.TRUE.equals(result.get("isError")));
    }

    @PostMapping("/tools/{toolName}")
    public R callTool(@PathVariable("toolName") String toolName, @RequestBody(required = false) Map<String, Object> request) {
        @SuppressWarnings("unchecked")
        Map<String, Object> arguments = (request != null && request.containsKey("arguments"))
                ? (Map<String, Object>) request.get("arguments")
                : (request != null ? request : java.util.Collections.emptyMap());
        Map<String, Object> result = mcpToolService.executeTool(toolName, arguments);
        return R.ok()
                .put("result", result)
                .put("content", result.get("content"))
                .put("isError", Boolean.TRUE.equals(result.get("isError")));
    }

    /**
     * MCP 大模型自然语言调用接口（参数由环境变量 LLM_API_KEY / LLM_API_URL / LLM_MODEL 配置驱动）
     */
    @PostMapping("/chat")
    public R chatWithLlm(@RequestBody(required = false) Map<String, Object> request) {
        if (request == null) {
            throw new com.lanf.common.ApiException(400, "BAD_REQUEST", "请求体不能为空");
        }
        Object shopIdObj = request.get("shop_id") != null ? request.get("shop_id") : request.get("store_id");
        Integer shopId = null;
        if (shopIdObj instanceof Number) {
            shopId = ((Number) shopIdObj).intValue();
        } else if (shopIdObj != null) {
            try { shopId = Integer.parseInt(shopIdObj.toString().trim()); } catch (Exception ignored) {}
        }
        if (shopId == null) {
            shopId = 3;
        }

        String prompt = (String) request.get("prompt");
        String systemPrompt = (String) request.get("system_prompt");

        @SuppressWarnings("unchecked")
        List<Map<String, Object>> messages = (List<Map<String, Object>>) request.get("messages");

        Map<String, Object> result;
        if (messages != null && !messages.isEmpty()) {
            result = llmBridgeService.chatWithHistory(messages, shopId, request);
        } else {
            if (prompt == null || prompt.trim().isEmpty()) {
                throw new com.lanf.common.ApiException(400, "BAD_REQUEST", "prompt 或 messages 不能为空");
            }
            result = llmBridgeService.chat(prompt, systemPrompt, shopId);
        }
        return R.ok().put("data", result);
    }

    /**
     * 查看当前环境生效的大模型配置状态（API Key 自动脱敏）
     */
    @GetMapping("/config")
    public R getEffectiveConfig() {
        return R.ok().put("data", llmBridgeService.getEffectiveConfig());
    }

    /**
     * MCP 门店桌台查询接口（试点限定 shop_id=3，返回实时状态与可下桌空闲桌号列表）
     */
    @GetMapping("/tables")
    public R getTables(@RequestParam(value = "shop_id", required = false) Integer shopId,
                       @RequestParam(value = "store_id", required = false) Integer storeId,
                       @RequestParam(value = "status", required = false) Integer status,
                       @RequestParam(value = "area_code", required = false) String areaCode) {
        Integer effectiveShopId = shopId != null ? shopId : (storeId != null ? storeId : 3);
        Map<String, Object> args = new java.util.LinkedHashMap<>();
        args.put("shop_id", effectiveShopId);
        if (status != null) {
            args.put("status", status);
        }
        if (areaCode != null && !areaCode.trim().isEmpty()) {
            args.put("area_code", areaCode.trim());
        }
        Map<String, Object> result = mcpToolService.executeTool("get_store_tables", args);
        return R.ok().put("data", result);
    }
}

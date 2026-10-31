package com.lanf.ai.service.impl;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.ai.dto.AiMenuSnapshotDTO;
import com.lanf.ai.dto.AiMenuSnapshotDTO.AiMenuItemDTO;
import com.lanf.ai.service.IAiLlmBridgeService;
import com.lanf.ai.service.IAiMenuAdapterService;
import com.lanf.common.ApiException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.http.converter.HttpMessageConverter;
import org.springframework.http.converter.StringHttpMessageConverter;
import org.springframework.http.converter.json.MappingJackson2HttpMessageConverter;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.HttpServerErrorException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestTemplate;

import java.net.InetSocketAddress;
import java.net.Proxy;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.util.*;

@Slf4j
@Service
public class AiLlmBridgeServiceImpl implements IAiLlmBridgeService {

    private volatile RestTemplate llmRestTemplate;

    @Autowired
    private IAiMenuAdapterService menuAdapterService;

    @Autowired(required = false)
    private com.lanf.service.ITableService tableService;

    @Value("${ai.api.url:}")
    private String configuredAiUrl;

    @Value("${ai.api.key:}")
    private String configuredAiKey;

    @Value("${ai.model:}")
    private String configuredAiModel;

    private final ObjectMapper objectMapper = new ObjectMapper();

    public static final int REQUIRED_SHOP_ID = 3;

    @Override
    public Map<String, Object> chat(String prompt, String systemPrompt, Integer shopId) {
        if (prompt == null || prompt.trim().isEmpty()) {
            throw new ApiException(400, "BAD_REQUEST", "用户输入提示词 (prompt) 不能为空");
        }
        int effectiveShopId = (shopId != null && shopId > 0) ? shopId : REQUIRED_SHOP_ID;
        if (effectiveShopId != REQUIRED_SHOP_ID) {
            throw new ApiException(403, "SHOP_NOT_SUPPORTED_FOR_MCP",
                    "当前AI大模型服务仅对试点门店(shop_id=" + REQUIRED_SHOP_ID + ")开放，门店[" + effectiveShopId + "]未授权");
        }

        List<Map<String, Object>> messages = new ArrayList<>();

        // 构建系统提示词（若未指定，自动基于门店在售菜品构建）
        String sysPrompt = systemPrompt;
        if (sysPrompt == null || sysPrompt.trim().isEmpty()) {
            sysPrompt = buildDefaultSystemPrompt(effectiveShopId);
        }
        Map<String, Object> sysMsg = new HashMap<>();
        sysMsg.put("role", "system");
        sysMsg.put("content", sysPrompt);
        messages.add(sysMsg);

        Map<String, Object> userMsg = new HashMap<>();
        userMsg.put("role", "user");
        userMsg.put("content", prompt.trim());
        messages.add(userMsg);

        return chatWithHistory(messages, effectiveShopId, Collections.emptyMap());
    }

    @Override
    public Map<String, Object> chatWithHistory(List<Map<String, Object>> messages, Integer shopId, Map<String, Object> options) {
        if (messages == null || messages.isEmpty()) {
            throw new ApiException(400, "BAD_REQUEST", "对话消息列表 (messages) 不能为空");
        }
        int effectiveShopId = (shopId != null && shopId > 0) ? shopId : REQUIRED_SHOP_ID;
        if (effectiveShopId != REQUIRED_SHOP_ID) {
            throw new ApiException(403, "SHOP_NOT_SUPPORTED_FOR_MCP",
                    "当前AI大模型服务仅对试点门店(shop_id=" + REQUIRED_SHOP_ID + ")开放，门店[" + effectiveShopId + "]未授权");
        }

        // 1. 读取由环境变量优先驱动的配置
        Map<String, String> cfg = resolveLlmConfig();
        String apiUrl = cfg.get("url");
        String apiKey = cfg.get("key");
        String model = cfg.get("model");

        if (apiKey == null || apiKey.trim().isEmpty()) {
            throw new ApiException(500, "LLM_CONFIG_MISSING",
                    "未配置大模型密钥，请设置环境变量 LLM_API_KEY 或 AI_API_KEY");
        }
        if (apiUrl == null || apiUrl.trim().isEmpty()) {
            throw new ApiException(500, "LLM_CONFIG_MISSING",
                    "未配置大模型接口地址，请设置环境变量 LLM_API_URL 或 AI_API_URL");
        }

        // 2. 组装请求 Payload
        // 兼容控制台/环境变量误保存的 ASCII 或中文包裹引号，避免把引号带入上游协议字段。
        apiUrl = normalizeApiUrl(apiUrl);
        apiKey = stripWrappingQuotes(apiKey);
        model = stripWrappingQuotes(model);
        if (apiUrl.isEmpty()) {
            throw new ApiException(500, "LLM_CONFIG_MISSING", "大模型接口地址为空，请设置完整的 LLM_API_URL");
        }
        if (model.isEmpty()) {
            throw new ApiException(500, "LLM_CONFIG_MISSING", "大模型模型名为空，请设置 LLM_MODEL");
        }

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("model", model);
        payload.put("messages", messages);

        double temp = 0.7;
        if (options != null && options.get("temperature") instanceof Number) {
            temp = ((Number) options.get("temperature")).doubleValue();
        } else {
            String envTemp = System.getenv("LLM_TEMPERATURE");
            if (envTemp != null && !envTemp.trim().isEmpty()) {
                try { temp = Double.parseDouble(envTemp.trim()); } catch (Exception ignored) {}
            }
        }
        payload.put("temperature", temp);

        int maxTokens = 2048;
        if (options != null && options.get("max_tokens") instanceof Number) {
            maxTokens = ((Number) options.get("max_tokens")).intValue();
        } else {
            String envTokens = System.getenv("LLM_MAX_TOKENS");
            if (envTokens != null && !envTokens.trim().isEmpty()) {
                try { maxTokens = Integer.parseInt(envTokens.trim()); } catch (Exception ignored) {}
            }
        }
        payload.put("max_tokens", maxTokens);

        // 3. 构建 HTTP 头部
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.set("Authorization", "Bearer " + apiKey.trim());

        log.info("[LLM_BRIDGE] Calling LLM model={} at url={} with messageCount={}", model, apiUrl, messages.size());

        try {
            String jsonReq = objectMapper.writeValueAsString(payload);
            HttpEntity<String> entity = new HttpEntity<>(jsonReq, headers);
            String respBody = getLlmRestTemplate().postForObject(apiUrl, entity, String.class);

            if (respBody == null || respBody.trim().isEmpty()) {
                throw new ApiException(502, "LLM_EMPTY_RESPONSE", "大模型接口返回空内容");
            }

            String trimmedResp = respBody.trim();
            if (trimmedResp.startsWith("<") || trimmedResp.toLowerCase(Locale.ROOT).contains("<!doctype") || trimmedResp.toLowerCase(Locale.ROOT).contains("<html")) {
                log.error("[LLM_BRIDGE] Received HTML response instead of JSON from {}: {}", apiUrl, respBody.length() > 500 ? respBody.substring(0, 500) : respBody);
                throw new ApiException(502, "LLM_INVALID_ENDPOINT",
                        "大模型网关地址配置错误：目标地址返回了 HTML 网页（非 API JSON 接口）。"
                                + "您当前配置的 LLM_API_URL 访问到了 TokLens/网关的前端管理页面，请将其设置为正确的 API 路由（如 /v1/chat/completions）。当前请求地址: " + apiUrl);
            }

            // 4. 解析响应内容
            @SuppressWarnings("unchecked")
            Map<String, Object> respMap = objectMapper.readValue(respBody, Map.class);
            String replyText = extractReplyText(respMap);

            Map<String, Object> result = new LinkedHashMap<>();
            result.put("status", "SUCCESS");
            result.put("reply", replyText);
            result.put("model", model);
            result.put("shop_id", effectiveShopId);
            result.put("timestamp", System.currentTimeMillis());
            if (respMap.containsKey("usage")) {
                result.put("usage", respMap.get("usage"));
            }
            return result;

        } catch (HttpClientErrorException | HttpServerErrorException e) {
            String errBody = e.getResponseBodyAsString();
            log.error("[LLM_BRIDGE] HTTP error status={} body={}", e.getStatusCode(), errBody);
            throw new ApiException(e.getRawStatusCode(), "LLM_CALL_FAILED",
                    "调用大模型服务失败: HTTP " + e.getRawStatusCode() + " - " + extractErrorMessage(errBody));
        } catch (ResourceAccessException rae) {
            Throwable cause = rae.getCause();
            int timeoutSec = getLlmReadTimeoutMs() / 1000;
            if (cause instanceof SocketTimeoutException) {
                String msg = cause.getMessage();
                if (msg != null && msg.toLowerCase(Locale.ROOT).contains("connect")) {
                    log.error("[LLM_BRIDGE] Connect timeout to {}: {}", apiUrl, msg);
                    throw new ApiException(504, "LLM_CONNECT_TIMEOUT",
                            "连接大模型网关超时，请检查网关地址或服务器外网连通性: " + apiUrl);
                } else {
                    log.error("[LLM_BRIDGE] Read timeout after {}s from {}: {}", timeoutSec, apiUrl, msg);
                    throw new ApiException(504, "LLM_READ_TIMEOUT",
                            "调用大模型响应超时（已等待 " + timeoutSec + " 秒）。网关或大模型生成耗时较长，可通过环境变量 LLM_TIMEOUT_SECONDS=120 调大超时时间，或检查 lax.toklens.ai 境外网关连通性。");
                }
            }
            log.error("[LLM_BRIDGE] Network resource access failed for {}: {}", apiUrl, rae.getMessage());
            throw new ApiException(502, "LLM_NETWORK_ERROR", "访问大模型接口网络异常: " + rae.getMessage());
        } catch (ApiException ae) {
            throw ae;
        } catch (Exception e) {
            log.error("[LLM_BRIDGE] Call failed: {}", e.getMessage(), e);
            throw new ApiException(500, "LLM_INVOCATION_ERROR", "调用大模型异常: " + e.getMessage());
        }
    }

    @Override
    public Map<String, Object> getEffectiveConfig() {
        Map<String, String> cfg = resolveLlmConfig();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("api_url", cfg.get("url"));
        out.put("model", cfg.get("model"));
        out.put("api_url_source_format", "full_endpoint_or_base_url_v1");
        out.put("read_timeout_seconds", getLlmReadTimeoutMs() / 1000);
        out.put("connect_timeout_seconds", getLlmConnectTimeoutMs() / 1000);
        String proxyHost = System.getenv("LLM_PROXY_HOST");
        String proxyPort = System.getenv("LLM_PROXY_PORT");
        if (proxyHost != null && !proxyHost.trim().isEmpty()) {
            out.put("proxy_configured", proxyHost.trim() + ":" + (proxyPort != null ? proxyPort.trim() : ""));
        } else {
            out.put("proxy_configured", false);
        }
        String key = cfg.get("key");
        boolean configured = (key != null && !key.trim().isEmpty());
        out.put("api_key_configured", configured);
        out.put("api_key_masked", maskApiKey(key));
        out.put("env_priority", Arrays.asList("LLM_API_KEY", "AI_API_KEY", "ARK_API_KEY", "application.yml (ai.api.key)"));
        out.put("pilot_shop_id", REQUIRED_SHOP_ID);
        return out;
    }

    private RestTemplate getLlmRestTemplate() {
        if (llmRestTemplate == null) {
            synchronized (this) {
                if (llmRestTemplate == null) {
                    llmRestTemplate = createLlmRestTemplate();
                }
            }
        }
        return llmRestTemplate;
    }

    private RestTemplate createLlmRestTemplate() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        int connectTimeout = getLlmConnectTimeoutMs();
        int readTimeout = getLlmReadTimeoutMs();
        factory.setConnectTimeout(connectTimeout);
        factory.setReadTimeout(readTimeout);

        String proxyHost = System.getenv("LLM_PROXY_HOST");
        String proxyPortStr = System.getenv("LLM_PROXY_PORT");
        if (proxyHost != null && !proxyHost.trim().isEmpty() && proxyPortStr != null && !proxyPortStr.trim().isEmpty()) {
            try {
                int proxyPort = Integer.parseInt(proxyPortStr.trim());
                factory.setProxy(new Proxy(Proxy.Type.HTTP, new InetSocketAddress(proxyHost.trim(), proxyPort)));
                log.info("[LLM_BRIDGE] Configured HTTP proxy {}:{} for LLM client", proxyHost.trim(), proxyPort);
            } catch (Exception e) {
                log.warn("[LLM_BRIDGE] Failed to set proxy {}:{}", proxyHost, proxyPortStr, e);
            }
        }

        RestTemplate template = new RestTemplate(factory);
        List<HttpMessageConverter<?>> converters = new ArrayList<>();
        converters.add(new StringHttpMessageConverter(StandardCharsets.UTF_8));
        converters.add(new MappingJackson2HttpMessageConverter());
        template.setMessageConverters(converters);
        log.info("[LLM_BRIDGE] Initialized dedicated LLM RestTemplate with connectTimeout={}ms, readTimeout={}ms", connectTimeout, readTimeout);
        return template;
    }

    private int getLlmReadTimeoutMs() {
        String sec = System.getenv("LLM_TIMEOUT_SECONDS");
        if (sec != null && !sec.trim().isEmpty()) {
            try {
                return Math.max(1000, Integer.parseInt(sec.trim()) * 1000);
            } catch (Exception ignored) {}
        }
        String ms = System.getenv("LLM_TIMEOUT_MS");
        if (ms != null && !ms.trim().isEmpty()) {
            try {
                return Math.max(1000, Integer.parseInt(ms.trim()));
            } catch (Exception ignored) {}
        }
        return 90_000; // 默认 90 秒，给大模型充足的推理生成与跨境网关往返时间
    }

    private int getLlmConnectTimeoutMs() {
        String sec = System.getenv("LLM_CONNECT_TIMEOUT_SECONDS");
        if (sec != null && !sec.trim().isEmpty()) {
            try {
                return Math.max(1000, Integer.parseInt(sec.trim()) * 1000);
            } catch (Exception ignored) {}
        }
        return 15_000; // 默认 15 秒连接超时
    }

    /**
     * 按优先级解析环境变量与配置文件中的大模型参数
     */
    private Map<String, String> resolveLlmConfig() {
        // 1. API Key: LLM_API_KEY -> AI_API_KEY -> ARK_API_KEY -> configured
        String key = System.getenv("LLM_API_KEY");
        if (key == null || key.trim().isEmpty()) {
            key = System.getenv("AI_API_KEY");
        }
        if (key == null || key.trim().isEmpty()) {
            key = System.getenv("ARK_API_KEY");
        }
        if (key == null || key.trim().isEmpty()) {
            key = configuredAiKey;
        }

        // 2. API URL: LLM_API_URL -> AI_API_URL -> configured -> default DeepSeek
        String url = System.getenv("LLM_API_URL");
        if (url == null || url.trim().isEmpty()) {
            url = System.getenv("AI_API_URL");
        }
        if (url == null || url.trim().isEmpty()) {
            url = configuredAiUrl;
        }
        if (url == null || url.trim().isEmpty()) {
            url = "https://api.deepseek.com/v1/chat/completions";
        }
        url = normalizeApiUrl(url);

        // 3. Model: LLM_MODEL -> AI_MODEL -> ARK_MODEL -> configured -> default deepseek-chat
        String model = System.getenv("LLM_MODEL");
        if (model == null || model.trim().isEmpty()) {
            model = System.getenv("AI_MODEL");
        }
        if (model == null || model.trim().isEmpty()) {
            model = System.getenv("ARK_MODEL");
        }
        if (model == null || model.trim().isEmpty()) {
            model = configuredAiModel;
        }
        if (model == null || model.trim().isEmpty()) {
            model = "deepseek-chat";
        }

        Map<String, String> map = new HashMap<>();
        map.put("key", stripWrappingQuotes(key));
        map.put("url", normalizeApiUrl(url));
        map.put("model", stripWrappingQuotes(model));
        return map;
    }

    /**
     * 清理配置中心/启动参数可能写入的外层 ASCII 或中文引号。
     * 只剥离成对的最外层引号，不修改 Key、URL、模型名内部字符。
     */
    private String stripWrappingQuotes(String value) {
        if (value == null) return "";
        String normalized = value.trim();
        boolean changed = true;
        while (changed && normalized.length() >= 2) {
            changed = false;
            char first = normalized.charAt(0);
            char last = normalized.charAt(normalized.length() - 1);
            if ((first == '\"' && last == '\"')
                    || (first == '\'' && last == '\'')
                    || (first == '“' && last == '”')
                    || (first == '‘' && last == '’')) {
                normalized = normalized.substring(1, normalized.length() - 1).trim();
                changed = true;
            }
        }
        return normalized;
    }

    /**
     * 智能归一化大模型接口 URL：
     * 1. 剥离外层引号与结尾斜杠。
     * 2. 若配置了完整端点（如 /v1/chat/completions），保持原样。
     * 3. 若配置到 /v1 或 /v3（如 http://ip:port/v1），自动补全 /chat/completions。
     * 4. 若配置为根地址或基础 host（如 http://127.0.0.1:3000），自动补全 /v1/chat/completions，防止命中 TokLens/网关的前端管理页面。
     */
    private String normalizeApiUrl(String value) {
        String normalized = stripWrappingQuotes(value);
        if (normalized.isEmpty()) return normalized;
        while (normalized.endsWith("/")) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        if (normalized.endsWith("/chat/completions")) {
            return normalized;
        }
        if (normalized.endsWith("/v1") || normalized.endsWith("/v3")) {
            return normalized + "/chat/completions";
        }
        if (normalized.contains("/services/aigc/") || normalized.contains("/api/v1/services/")) {
            return normalized;
        }
        try {
            java.net.URI uri = java.net.URI.create(normalized);
            String path = uri.getPath();
            if (path == null || path.isEmpty() || "/".equals(path)) {
                return normalized + "/v1/chat/completions";
            }
        } catch (Exception ignored) {
        }
        return normalized;
    }

    private String buildDefaultSystemPrompt(int shopId) {
        StringBuilder sb = new StringBuilder();
        sb.append("你是【深圳东北大串烧烤店】（试点门店ID: ").append(shopId).append("）的官方AI智能点餐管家。\n");
        sb.append("【核心准则】\n");
        sb.append("1. 你只能推荐当前门店真实在售的菜品，严禁编造或凭空捏造不存在的菜品或价格。\n");
        sb.append("2. 当顾客提到不吃辣时，必须分配免辣保底荤食（non_spicy_available=true），绝不能将微辣或不可免辣的菜推荐给免辣成员。\n");
        sb.append("3. 严格遵循顾客的人数与预算范围。\n");

        // 附加门店真实在售菜单核心参考
        try {
            AiMenuSnapshotDTO snapshot = menuAdapterService.getStoreMenuSnapshot(shopId);
            if (snapshot != null && snapshot.getItems() != null && !snapshot.getItems().isEmpty()) {
                sb.append("【当前门店热销菜单参考】\n");
                int count = 0;
                for (AiMenuItemDTO item : snapshot.getItems()) {
                    if (Boolean.TRUE.equals(item.getActive()) && !Boolean.TRUE.equals(item.getSold_out())) {
                        sb.append("- ").append(item.getName())
                                .append(" (¥").append(String.format("%.2f", item.getPrice_fen() / 100.0)).append(")")
                                .append(Boolean.TRUE.equals(item.getNon_spicy_available()) ? " [可做免辣]" : "")
                                .append("\n");
                        count++;
                        if (count >= 15) break; // 控制上下文长度
                    }
                }
            }
        } catch (Exception ignored) {}

        // 附加当前门店空闲可用桌台状态感知
        if (tableService != null) {
            try {
                List<com.lanf.entity.Table> idleTables = tableService.list(new com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<com.lanf.entity.Table>()
                        .eq("shop_id", shopId)
                        .eq("status", 0)
                        .orderByAsc("number"));
                if (idleTables != null && !idleTables.isEmpty()) {
                    sb.append("【当前空闲可用桌号】: ");
                    List<String> idleNums = new ArrayList<>();
                    for (com.lanf.entity.Table t : idleTables) {
                        if (t.getNumber() != null && !t.getNumber().trim().isEmpty()) {
                            idleNums.add(t.getNumber().trim());
                        }
                    }
                    sb.append(String.join(", ", idleNums)).append("\n");
                    sb.append("4. 当顾客询问桌位、换桌或要求开台下单时，优先向顾客推荐上述空闲桌号。\n");
                }
            } catch (Exception ignored) {}
        }

        return sb.toString();
    }

    @SuppressWarnings("unchecked")
    private String extractReplyText(Map<String, Object> respMap) {
        if (respMap == null) return "";

        // 1. 标准 choices[0].message.content
        Object choicesObj = respMap.get("choices");
        if (choicesObj instanceof List && !((List<?>) choicesObj).isEmpty()) {
            Object first = ((List<?>) choicesObj).get(0);
            if (first instanceof Map) {
                Map<?, ?> choiceMap = (Map<?, ?>) first;
                Object msgObj = choiceMap.get("message");
                if (msgObj instanceof Map) {
                    Object content = ((Map<?, ?>) msgObj).get("content");
                    if (content != null) return content.toString();
                }
                Object text = choiceMap.get("text");
                if (text != null) return text.toString();
            }
        }

        // 2. DashScope / 通义 output.text 或 output.choices
        Object outputObj = respMap.get("output");
        if (outputObj instanceof Map) {
            Map<?, ?> output = (Map<?, ?>) outputObj;
            Object text = output.get("text");
            if (text != null && !text.toString().trim().isEmpty()) {
                return text.toString();
            }
            Object cList = output.get("choices");
            if (cList instanceof List && !((List<?>) cList).isEmpty()) {
                Object f = ((List<?>) cList).get(0);
                if (f instanceof Map) {
                    Object m = ((Map<?, ?>) f).get("message");
                    if (m instanceof Map && ((Map<?, ?>) m).get("content") != null) {
                        return ((Map<?, ?>) m).get("content").toString();
                    }
                }
            }
        }

        return respMap.toString();
    }

    private String extractErrorMessage(String body) {
        if (body == null || body.trim().isEmpty()) return "未知远程服务错误";
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> root = objectMapper.readValue(body, Map.class);
            if (root.get("error") instanceof Map) {
                Object msg = ((Map<?, ?>) root.get("error")).get("message");
                if (msg != null) return msg.toString();
            }
            if (root.get("message") != null) return root.get("message").toString();
        } catch (Exception ignored) {}
        return body.length() > 200 ? body.substring(0, 200) + "..." : body;
    }

    private String maskApiKey(String key) {
        if (key == null || key.trim().isEmpty()) return "未设置";
        String trimmed = key.trim();
        if (trimmed.length() <= 8) return "******";
        return trimmed.substring(0, 3) + "****" + trimmed.substring(trimmed.length() - 4);
    }
}

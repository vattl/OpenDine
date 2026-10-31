package com.lanf.service;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.util.*;
import java.util.regex.*;
/** Pure model-response parsing. Does not execute tools or resolve identity. */
@Component
public class AiToolResponseParser {
    private static final Logger log=LoggerFactory.getLogger(AiToolResponseParser.class);
    private final ObjectMapper objectMapper;
    public AiToolResponseParser(ObjectMapper objectMapper) { this.objectMapper=objectMapper; }
    private static final Pattern AI_MARKDOWN_JSON_BLOCK =
            Pattern.compile("```(?:json)?\\s*\\r?\\n?([\\s\\S]*?)```", Pattern.CASE_INSENSITIVE);
    private static final Pattern AI_EMBEDDED_TOOL_CALL_NAME =
            Pattern.compile("\\{\\s*\"name\"\\s*:\\s*\"([a-z][a-z0-9_]*)\"", Pattern.CASE_INSENSITIVE);
    private List<String> extractMarkdownJsonBlocks(String text) {
        List<String> out = new ArrayList<>();
        if (text == null || text.isEmpty()) {
            return out;
        }
        Matcher m = AI_MARKDOWN_JSON_BLOCK.matcher(text);
        while (m.find()) {
            String inner = m.group(1).trim();
            if (!inner.isEmpty()) {
                out.add(inner);
            }
        }
        return out;
    }

    private static void sortToolJsonBlocksPreferOrder(List<String> blocks) {
        blocks.sort((a, b) -> Integer.compare(scoreBlockForOrderTool(b), scoreBlockForOrderTool(a)));
    }

    private static int scoreBlockForOrderTool(String s) {
        if (s == null) {
            return 0;
        }
        if (s.contains("create_order")) {
            return 3;
        }
        if (s.contains("add_dishes")) {
            return 3;
        }
        if (s.contains("\"name\"") && s.contains("\"arguments\"")) {
            return 1;
        }
        return 0;
    }

    /**
     * 与 OpenAI tool_calls 中 function.arguments 同义：部分模型/伪协议写 parameters 或 params。
     */
    private static Object pickToolArgumentsFromMap(Map<?, ?> m) {
        if (m == null) {
            return null;
        }
        Object a = m.get("arguments");
        if (a != null) {
            return a;
        }
        a = m.get("parameters");
        if (a != null) {
            return a;
        }
        return m.get("params");
    }

    /**
     * 解析 OpenAI/方舟类「工具调用 JSON 数组」：[{"name":"x","arguments":{...}}, ...]
     * 兼容 {"name":"x","parameters":{...}}（与 arguments 同义）。
     */
    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> parseToolCallsArrayFromJson(String json) {
        if (json == null || json.isEmpty()) {
            return null;
        }
        String t = json.trim();
        if (!t.startsWith("[")) {
            return null;
        }
        try {
            List<?> arr = objectMapper.readValue(t, List.class);
            if (arr == null || arr.isEmpty()) {
                return null;
            }
            List<Map<String, Object>> out = new ArrayList<>();
            for (Object o : arr) {
                if (!(o instanceof Map)) {
                    continue;
                }
                Map<?, ?> m = (Map<?, ?>) o;
                Object nameObj = m.get("name");
                Object argsObj = pickToolArgumentsFromMap(m);
                if (nameObj == null || argsObj == null) {
                    continue;
                }
                Map<String, Object> tc = new HashMap<>();
                tc.put("name", nameObj);
                tc.put("arguments", argsObj);
                out.add(tc);
            }
            return out.isEmpty() ? null : out;
        } catch (Exception e) {
            log.debug("[AI_TOOL_PARSE] invalid tool calls array");
            return null;
        }
    }

    /**
     * 解析单段 JSON：{"name":"...","arguments":{...}} 或 parameters 同义；或 {"tool_calls":[...]}。
     */
    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> parseSingleToolCallObjectFromJson(String json) {
        if (json == null || json.isEmpty() || !json.trim().startsWith("{")) {
            return null;
        }
        String text = json.trim();
        try {
            Map<?, ?> single = objectMapper.readValue(text, Map.class);
            Object nameObj = single.get("name");
            Object argsObj = pickToolArgumentsFromMap(single);
            if (nameObj != null && argsObj != null) {
                Map<String, Object> tc = new HashMap<>();
                tc.put("name", nameObj);
                tc.put("arguments", argsObj);
                return Collections.singletonList(tc);
            }
            Object tc = single.get("tool_calls");
            if (tc instanceof List && !((List<?>) tc).isEmpty()) {
                return (List<Map<String, Object>>) tc;
            }
        } catch (Exception ignored) {
            // fall through
        }
        return null;
    }

    /**
     * 从「前面是自然语言、末尾是 {"name":"create_order","arguments":{...}}」类正文里抠出完整 JSON 对象并解析。
     */
    private List<Map<String, Object>> tryParseEmbeddedToolJsonObject(String rawText) {
        if (rawText == null || rawText.isEmpty()) {
            return null;
        }
        Matcher m = AI_EMBEDDED_TOOL_CALL_NAME.matcher(rawText);
        List<Integer> starts = new ArrayList<>();
        while (m.find()) {
            starts.add(m.start());
        }
        for (int i = starts.size() - 1; i >= 0; i--) {
            String balanced = extractBalancedJsonObject(rawText, starts.get(i));
            if (balanced == null) {
                continue;
            }
            List<Map<String, Object>> tc = parseSingleToolCallObjectFromJson(balanced);
            if (tc != null && !tc.isEmpty()) {
                log.info("[AI_TOOL_PARSE] embedded tool JSON extracted, length={}", balanced.length());
                return tc;
            }
        }
        return null;
    }

    /**
     * 从 start 处的 '{' 起截取配对的 JSON 对象（忽略字符串内的括号）。
     */
    private static String extractBalancedJsonObject(String s, int start) {
        if (s == null || start < 0 || start >= s.length() || s.charAt(start) != '{') {
            return null;
        }
        int depth = 0;
        boolean inString = false;
        boolean escape = false;
        for (int i = start; i < s.length(); i++) {
            char c = s.charAt(i);
            if (escape) {
                escape = false;
                continue;
            }
            if (inString) {
                if (c == '\\') {
                    escape = true;
                } else if (c == '"') {
                    inString = false;
                }
                continue;
            }
            if (c == '"') {
                inString = true;
                continue;
            }
            if (c == '{') {
                depth++;
            } else if (c == '}') {
                depth--;
                if (depth == 0) {
                    return s.substring(start, i + 1);
                }
            }
        }
        return null;
    }

    /**
     * 从 start 处的 '[' 起截取配对的 JSON 数组（忽略字符串内的括号）。
     */
    private static String extractBalancedJsonArray(String s, int start) {
        if (s == null || start < 0 || start >= s.length() || s.charAt(start) != '[') {
            return null;
        }
        int depth = 0;
        boolean inString = false;
        boolean escape = false;
        for (int i = start; i < s.length(); i++) {
            char c = s.charAt(i);
            if (escape) {
                escape = false;
                continue;
            }
            if (inString) {
                if (c == '\\') {
                    escape = true;
                } else if (c == '"') {
                    inString = false;
                }
                continue;
            }
            if (c == '"') {
                inString = true;
                continue;
            }
            if (c == '[') {
                depth++;
            } else if (c == ']') {
                depth--;
                if (depth == 0) {
                    return s.substring(start, i + 1);
                }
            }
        }
        return null;
    }

    /**
     * 从「前面是自然语言、文中或末尾为 [{"name":"get_order_by_table","arguments":{...}}, ...]」类正文里抠出工具调用数组。
     * 自右向左尝试每个 '['，避免整段 trim 后不以 '[' 开头导致无法识别。
     */
    private List<Map<String, Object>> tryParseEmbeddedToolJsonArray(String rawText) {
        if (rawText == null || rawText.isEmpty()) {
            return null;
        }
        for (int idx = rawText.lastIndexOf('['); idx >= 0; idx = rawText.lastIndexOf('[', idx - 1)) {
            String balanced = extractBalancedJsonArray(rawText, idx);
            if (balanced == null) {
                continue;
            }
            List<Map<String, Object>> arr = parseToolCallsArrayFromJson(balanced);
            if (arr != null && !arr.isEmpty()) {
                log.info("[AI_TOOL_PARSE] embedded tool JSON array extracted from offset={}, size={}", idx, arr.size());
                return arr;
            }
        }
        return null;
    }

    /**
     * 从助手正文提取可执行工具调用：优先 Markdown 代码块内的 JSON，再尝试整段文本。
     */
    @SuppressWarnings("unchecked")
    public List<Map<String, Object>> parseToolCallsFromText(String rawText) {
        if (rawText == null) {
            return null;
        }
        List<String> blocks = extractMarkdownJsonBlocks(rawText);
        sortToolJsonBlocksPreferOrder(blocks);
        for (String block : blocks) {
            List<Map<String, Object>> arr = parseToolCallsArrayFromJson(block);
            if (arr != null && !arr.isEmpty()) {
                return arr;
            }
            List<Map<String, Object>> tc = parseSingleToolCallObjectFromJson(block);
            if (tc != null && !tc.isEmpty()) {
                return tc;
            }
        }
        // 说明文字 + 内嵌工具 JSON 数组（如 plan.explanation 中「自然语言\\n[{...}]」）
        List<Map<String, Object>> embeddedArr = tryParseEmbeddedToolJsonArray(rawText);
        if (embeddedArr != null && !embeddedArr.isEmpty()) {
            return embeddedArr;
        }
        // 说明文字 + 末尾裸 JSON 对象（无 ``` 包裹）
        List<Map<String, Object>> embedded = tryParseEmbeddedToolJsonObject(rawText);
        if (embedded != null && !embedded.isEmpty()) {
            return embedded;
        }
        String text = rawText.trim();
        if (text.startsWith("```")) {
            text = text.replaceFirst("(?i)```json?", "").replaceAll("```\\s*$", "").trim();
        }
        List<Map<String, Object>> asArray = parseToolCallsArrayFromJson(text);
        if (asArray != null && !asArray.isEmpty()) {
            log.info("[AI_TOOL_PARSE] parsed tool_calls JSON array, size={}", asArray.size());
            return asArray;
        }
        List<Map<String, Object>> direct = parseSingleToolCallObjectFromJson(text);
        if (direct != null) {
            return direct;
        }
        if (!text.contains("tool_calls")) {
            return null;
        }
        int idx = text.indexOf("tool_calls");
        if (idx < 0) {
            return null;
        }
        int colon = text.indexOf(":", idx);
        if (colon < 0) {
            return null;
        }
        String tail = text.substring(colon + 1).trim();
        try {
            if (tail.startsWith("[")) {
                return objectMapper.readValue(tail, new TypeReference<List<Map<String, Object>>>() {});
            }
            if (tail.startsWith("{")) {
                Map<?, ?> obj = objectMapper.readValue(tail, Map.class);
                Object tc = obj.get("tool_calls");
                if (tc instanceof List) {
                    return (List<Map<String, Object>>) tc;
                }
            }
        } catch (Exception ignored) { }
        return null;
    }

    /**
     * 规范化 tool_calls：保证每条都含 function 对象（name + arguments），满足 API 要求。
     * 模型有时把 name/arguments 写在顶层，此处统一为 function: { name, arguments }。
     */
    public List<Map<String, Object>> normalizeToolCalls(List<Map<String, Object>> raw) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> tc : raw) {
            Map<String, Object> fn = new HashMap<>();
            Object nameObj = null;
            Object argsObj = null;
            Object fnObj = tc.get("function");
            if (fnObj instanceof Map) {
                Map<?, ?> existing = (Map<?, ?>) fnObj;
                nameObj = existing.get("name");
                argsObj = pickToolArgumentsFromMap(existing);
            }
            if (nameObj == null && tc.get("name") != null) {
                nameObj = tc.get("name");
                argsObj = pickToolArgumentsFromMap(tc);
            }
            if (nameObj == null) {
                continue;
            }
            fn.put("name", nameObj);
            // API 要求 function.arguments 为 JSON 字符串
            if (argsObj instanceof String) {
                fn.put("arguments", argsObj);
            } else if (argsObj instanceof Map) {
                try {
                    fn.put("arguments", objectMapper.writeValueAsString(argsObj));
                } catch (Exception e) {
                    fn.put("arguments", "{}");
                }
            } else {
                fn.put("arguments", argsObj != null ? argsObj.toString() : "{}");
            }
            Map<String, Object> normalized = new HashMap<>();
            Object existingId = tc.get("id");
            if (existingId != null && StringUtils.hasText(existingId.toString().trim())) {
                normalized.put("id", existingId.toString().trim());
            } else {
                // 火山方舟等接口强制要求每条 tool_call 带非空 id，否则下一轮 messages 校验失败
                normalized.put("id", "call_" + UUID.randomUUID().toString().replace("-", ""));
            }
            normalized.put("type", tc.get("type") != null ? tc.get("type") : "function");
            normalized.put("function", fn);
            out.add(normalized);
        }
        return out;
    }

    /**
     * 从 API 返回的 content（可能为字符串或多模态数组 [{text: "..."}]）中提取纯文本，用于展示或解析。
     */
    public String extractTextFromContent(Object content) {
        if (content == null) {
            return null;
        }
        if (content instanceof String) {
            return (String) content;
        }
        if (content instanceof List) {
            StringBuilder sb = new StringBuilder();
            for (Object item : (List<?>) content) {
                if (item instanceof Map) {
                    Object text = ((Map<?, ?>) item).get("text");
                    if (text != null) {
                        sb.append(text.toString());
                    }
                }
            }
            return sb.length() > 0 ? sb.toString() : content.toString();
        }
        return content.toString();
    }

}

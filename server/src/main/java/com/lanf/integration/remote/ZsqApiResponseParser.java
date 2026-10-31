package com.lanf.integration.remote;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JavaType;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.integration.exception.ZsqApiException;

/**
 * 真省钱部分接口 {@code data} 为 JSON 字符串（如发配送返回支付信息），需二次解析。
 */
public final class ZsqApiResponseParser {

    private ZsqApiResponseParser() {
    }

    public static <T> ZsqApiResponse<T> parse(ObjectMapper mapper, String json,
                                              TypeReference<ZsqApiResponse<T>> typeRef) {
        if (json == null || json.trim().isEmpty()) {
            throw new ZsqApiException("真省钱接口响应为空");
        }
        try {
            JsonNode root = mapper.readTree(json);
            ZsqApiResponse<T> api = new ZsqApiResponse<>();
            api.setCode(root.path("code").asInt(0));
            JsonNode messageNode = root.get("message");
            if (messageNode != null && !messageNode.isNull()) {
                api.setMessage(messageNode.asText());
            }
            JsonNode traceNode = root.get("traceId");
            if (traceNode != null && !traceNode.isNull()) {
                api.setTraceId(traceNode.asText());
            }
            api.setData(parseDataNode(mapper, root.get("data"), resolveDataType(mapper, typeRef)));
            return api;
        } catch (ZsqApiException e) {
            throw e;
        } catch (Exception e) {
            throw new ZsqApiException("真省钱响应解析失败: " + e.getMessage());
        }
    }

    private static JavaType resolveDataType(ObjectMapper mapper, TypeReference<?> typeRef) {
        JavaType full = mapper.getTypeFactory().constructType(typeRef.getType());
        if (full.containedTypeCount() < 1) {
            return mapper.constructType(Object.class);
        }
        return full.containedType(0);
    }

    private static <T> T parseDataNode(ObjectMapper mapper, JsonNode dataNode, JavaType dataType) throws Exception {
        if (dataNode == null || dataNode.isNull()) {
            return null;
        }
        JsonNode resolved = unwrapEmbeddedJsonNode(mapper, dataNode);
        if (resolved == null || resolved.isNull()) {
            return null;
        }
        if (dataType.isCollectionLikeType() && resolved.isArray()) {
            return mapper.convertValue(parseArrayElements(mapper, resolved, dataType), dataType);
        }
        return mapper.convertValue(resolved, dataType);
    }

    /**
     * 真省钱有时把 data 或数组元素包成 JSON 字符串。
     */
    private static JsonNode unwrapEmbeddedJsonNode(ObjectMapper mapper, JsonNode node) throws Exception {
        if (node == null || node.isNull()) {
            return node;
        }
        if (!node.isTextual()) {
            return node;
        }
        String text = node.asText().trim();
        if (text.isEmpty()) {
            return null;
        }
        JsonNode inner = mapper.readTree(text);
        if (inner.isTextual()) {
            return unwrapEmbeddedJsonNode(mapper, inner);
        }
        return inner;
    }

    private static JsonNode parseArrayElements(ObjectMapper mapper, JsonNode arrayNode, JavaType listType)
            throws Exception {
        JavaType elementType = listType.getContentType();
        com.fasterxml.jackson.databind.node.ArrayNode out = mapper.createArrayNode();
        for (JsonNode item : arrayNode) {
            JsonNode resolved = unwrapEmbeddedJsonNode(mapper, item);
            if (resolved == null || resolved.isNull()) {
                out.addNull();
                continue;
            }
            if (elementType != null && elementType.isMapLikeType() && resolved.isTextual()) {
                resolved = unwrapEmbeddedJsonNode(mapper, resolved);
            }
            out.add(resolved);
        }
        return out;
    }
}

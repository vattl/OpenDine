package com.lanf.ai.service;

import java.util.List;
import java.util.Map;

/**
 * 大模型调用桥接服务
 * 通过环境变量 (LLM_API_KEY, LLM_API_URL, LLM_MODEL 等) 统一配置大模型参数
 */
public interface IAiLlmBridgeService {

    /**
     * 单轮问答/提示词调用大模型
     *
     * @param prompt       用户输入提示词
     * @param systemPrompt 可选自定义系统提示词
     * @param shopId       门店ID（试点固定为 3）
     * @return 大模型响应结果（含 reply, model, shop_id 等）
     */
    Map<String, Object> chat(String prompt, String systemPrompt, Integer shopId);

    /**
     * 多轮对话上下文调用大模型
     *
     * @param messages 消息历史列表 [{role: 'system'/'user'/'assistant', content: '...'}]
     * @param shopId   门店ID（试点固定为 3）
     * @param options  可选控制参数 (temperature, max_tokens, etc.)
     * @return 大模型响应结果
     */
    Map<String, Object> chatWithHistory(List<Map<String, Object>> messages, Integer shopId, Map<String, Object> options);

    /**
     * 获取当前生效的大模型配置（含脱敏 API Key）
     */
    Map<String, Object> getEffectiveConfig();
}

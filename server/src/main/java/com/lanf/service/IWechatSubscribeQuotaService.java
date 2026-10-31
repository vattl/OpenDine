package com.lanf.service;

import com.lanf.entity.SubscribeSceneTemplate;
import com.lanf.entity.SubscribeSendLog;

import java.util.List;
import java.util.Map;

/**
 * 微信订阅消息后端可控与配额台账服务
 */
public interface IWechatSubscribeQuotaService {

    /**
     * 智能决策：根据用户当前有效配额与历史拒绝状态，决定是否需要唤起微信订阅弹窗
     * @param openid 微信用户OpenID
     * @param sceneCode 业务场景编码（如 ORDER_PICKUP, ORDER_STATUS 等，为null则评估全部启用场景）
     * @return 包含 need_prompt(boolean), tmpl_ids(List<String>), scene_decisions(Map)
     */
    Map<String, Object> getPromptDecision(String openid, String sceneCode);

    /**
     * 前端授权结果回传记账
     * @param openid 微信用户OpenID
     * @param sceneCode 业务场景编码
     * @param authResults 前端 wx.requestSubscribeMessage 返回的授权字典，如 {"tmplId1": "accept", "tmplId2": "reject"}
     * @return 更新后的台账状态
     */
    Map<String, Object> reportAuthResult(String openid, String sceneCode, Map<String, String> authResults);

    /**
     * 判断指定用户在目标场景是否具备可用的订阅消息配额
     */
    boolean hasAvailableQuota(String openid, String sceneCode);

    /**
     * 获取指定场景当前启用的微信模板配置
     */
    SubscribeSceneTemplate getActiveTemplateByScene(String sceneCode);

    /**
     * 处理微信接口发送返回结果：自动扣减额度或遇到 43101 自动校准归零，并落盘审计日志
     */
    void handleSendResult(String openid, String sceneCode, String templateId,
                          int errcode, String errmsg, String bizNo,
                          long durationMs, String payloadSummary);

    /**
     * 查询用户所有场景的订阅配额摘要
     */
    Map<String, Object> getUserQuotaSummary(String openid);

    /**
     * 管理后台：查询全部场景配置
     */
    List<SubscribeSceneTemplate> listSceneTemplates();

    /**
     * 管理后台：保存或修改场景模板配置
     */
    boolean saveOrUpdateSceneTemplate(SubscribeSceneTemplate template);

    /**
     * 管理后台：删除指定场景模板配置
     */
    boolean deleteSceneTemplate(String sceneCode);

    /**
     * 管理后台：查询订阅发送审计日志列表
     */
    List<SubscribeSendLog> listSendLogs(String bizNo, String openid, String sceneCode, String status, int limit);
}

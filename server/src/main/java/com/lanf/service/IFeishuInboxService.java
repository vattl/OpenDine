package com.lanf.service;

import com.lanf.entity.FeishuInboxMeta;

import java.io.File;
import java.util.Map;

/**
 * 飞书素材接收与本地烧烤 AI 工作流收件箱服务
 */
public interface IFeishuInboxService {

    /**
     * 处理飞书回调请求（包含 URL 验证与事件通知推送）
     *
     * @param requestBody 原始请求体 JSON
     * @param headers     请求头
     * @return 响应报文（URL验证返回 challenge，事件返回 code:0）
     */
    Map<String, Object> handleCallback(String requestBody, Map<String, String> headers);

    /**
     * 本地主控轮询拉取待处理素材列表
     *
     * @param platformFilter 平台过滤条件（可选）
     * @return 包含 items 的数据结构
     */
    Map<String, Object> listPendingInboxItems(String platformFilter);

    /**
     * 本地主控完成素材拉取后确认（移走/归档子目录，防止重复处理）
     *
     * @param inboxId 收件箱子目录唯一标识
     * @param status  确认状态（如 ok）
     * @return 操作结果
     */
    Map<String, Object> ackInboxItem(String inboxId, String status);

    /**
     * 读取收件箱内的静态文件（如 meta.json、media/1.jpg 等）
     *
     * @param inboxId      收件箱子目录唯一标识
     * @param relativePath 相对路径
     * @return 目标文件对象（不存在或非法路径返回 null）
     */
    File getInboxFile(String inboxId, String relativePath);

    /**
     * 保存/更新元数据到指定的收件箱目录
     *
     * @param inboxId 收件箱子目录 ID
     * @param meta    元数据
     */
    void saveMeta(String inboxId, FeishuInboxMeta meta);

    /**
     * 读取指定的收件箱元数据
     *
     * @param inboxId 收件箱子目录 ID
     * @return 元数据对象（不存在返回 null）
     */
    FeishuInboxMeta readMeta(String inboxId);
}

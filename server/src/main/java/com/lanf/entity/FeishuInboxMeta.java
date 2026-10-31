package com.lanf.entity;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.io.Serializable;
import java.util.ArrayList;
import java.util.List;

/**
 * 飞书素材收件箱元信息（meta.json 模型）
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonInclude(JsonInclude.Include.NON_NULL)
public class FeishuInboxMeta implements Serializable {

    private static final long serialVersionUID = 1L;

    /**
     * 飞书消息唯一 ID（如 om_xxx）
     */
    @JsonProperty("message_id")
    private String messageId;

    /**
     * 会话 ID（如 oc_xxx）
     */
    @JsonProperty("chat_id")
    private String chatId;

    /**
     * 发送人 Open ID（如 ou_xxx）
     */
    @JsonProperty("sender_open_id")
    private String senderOpenId;

    /**
     * 消息创建毫秒时间戳字符串
     */
    @JsonProperty("create_time")
    private String createTime;

    /**
     * 文字需求内容（无则空串）
     */
    @JsonProperty("text")
    @Builder.Default
    private String text = "";

    /**
     * 本条消息包含的媒体类型（如 ["image"], ["video"], ["text"] 等）
     */
    @JsonProperty("message_types")
    @Builder.Default
    private List<String> messageTypes = new ArrayList<>();

    /**
     * 媒体文件相对路径（如 ["media/1.jpg"]）
     */
    @JsonProperty("media_files")
    @Builder.Default
    private List<String> mediaFiles = new ArrayList<>();

    /**
     * 是否下载完成（true 才能被本地主控拉取）
     */
    @JsonProperty("downloaded")
    @Builder.Default
    private Boolean downloaded = false;

    /**
     * 下载失败原因（选填）
     */
    @JsonProperty("error_msg")
    private String errorMsg;
}

package com.lanf.properties;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.io.File;

/**
 * 飞书应用及素材收件箱配置属性
 */
@Component
@ConfigurationProperties(prefix = "feishu")
@Data
public class FeishuProperties {

    /**
     * 飞书应用 App ID
     */
    private String appId;

    /**
     * 飞书应用 App Secret
     */
    private String appSecret;

    /**
     * 飞书事件订阅 Verification Token
     */
    private String verificationToken;

    /**
     * 飞书事件订阅 Encrypt Key（用于加密模式解密，选填）
     */
    private String encryptKey;

    /**
     * 素材收件箱根目录（默认 /data/bbq_inbox/）
     */
    private String inboxDir = "/data/bbq_inbox/";

    /**
     * 已取走归档目录（默认 /data/bbq_inbox_archive/）
     */
    private String archiveDir = "/data/bbq_inbox_archive/";

    /**
     * 本地主控拉取素材访问令牌（Header: X-Inbox-Token 或 query: token，选填）
     */
    private String inboxToken;

    /**
     * 飞书 OpenAPI 基础地址（默认 https://open.feishu.cn）
     */
    private String baseUrl = "https://open.feishu.cn";

    /**
     * 解析并获取可写的收件箱根目录（支持多环境容错）
     */
    public File getResolvedInboxDir() {
        File dir = new File(inboxDir);
        if (dir.isAbsolute()) {
            if (dir.exists() || dir.mkdirs()) {
                return dir;
            }
        }
        // 环境不支持绝对路径写入时（如 Windows 本地开发），降级到当前工程相对目录
        File fallbackDir = new File(System.getProperty("user.dir"), "data/bbq_inbox");
        fallbackDir.mkdirs();
        return fallbackDir;
    }

    /**
     * 解析并获取可写的归档目录（支持多环境容错）
     */
    public File getResolvedArchiveDir() {
        File dir = new File(archiveDir);
        if (dir.isAbsolute()) {
            if (dir.exists() || dir.mkdirs()) {
                return dir;
            }
        }
        File fallbackDir = new File(System.getProperty("user.dir"), "data/bbq_inbox_archive");
        fallbackDir.mkdirs();
        return fallbackDir;
    }
}

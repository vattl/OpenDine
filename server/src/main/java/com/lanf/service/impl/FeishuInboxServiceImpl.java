package com.lanf.service.impl;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.FeishuInboxMeta;
import com.lanf.properties.FeishuProperties;
import com.lanf.service.IFeishuInboxService;
import com.lanf.util.FeishuCipherUtil;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.io.FileUtils;
import org.apache.http.HttpEntity;
import org.apache.http.client.config.RequestConfig;
import org.apache.http.client.methods.CloseableHttpResponse;
import org.apache.http.client.methods.HttpGet;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.entity.ContentType;
import org.apache.http.entity.StringEntity;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.util.EntityUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.annotation.PreDestroy;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.concurrent.*;
import java.util.regex.Pattern;

/**
 * 飞书素材接收与本地烧烤 AI 工作流收件箱服务实现
 */
@Slf4j
@Service
public class FeishuInboxServiceImpl implements IFeishuInboxService {

    private static final Pattern SAFE_ID_PATTERN = Pattern.compile("^[a-zA-Z0-9_-]+$");

    @Autowired
    private FeishuProperties feishuProperties;

    @Autowired
    private ObjectMapper objectMapper;

    @Value("${app.public-base-url:https://laofei.com.cn}")
    private String publicBaseUrl;

    private final CloseableHttpClient httpClient = HttpClients.custom()
            .setDefaultRequestConfig(RequestConfig.custom()
                    .setConnectTimeout(10000)
                    .setSocketTimeout(30000)
                    .setConnectionRequestTimeout(10000)
                    .build())
            .build();

    private final ExecutorService downloadExecutor = Executors.newFixedThreadPool(4, new ThreadFactory() {
        private int count = 0;
        @Override
        public Thread newThread(Runnable r) {
            Thread t = new Thread(r, "feishu-media-downloader-" + (++count));
            t.setDaemon(true);
            return t;
        }
    });

    private volatile String cachedTenantAccessToken;
    private volatile long tokenExpireTime = 0L;

    @PreDestroy
    public void destroy() {
        try {
            downloadExecutor.shutdown();
        } catch (Exception ignored) {
        }
        try {
            httpClient.close();
        } catch (Exception ignored) {
        }
    }

    @Override
    public Map<String, Object> handleCallback(String requestBody, Map<String, String> headers) {
        Map<String, Object> result = new HashMap<>();
        if (requestBody == null || requestBody.trim().isEmpty()) {
            result.put("code", 400);
            result.put("msg", "请求体不能为空");
            return result;
        }

        try {
            JsonNode rootNode = objectMapper.readTree(requestBody);

            // 1. 若为加密模式，先解密
            if (rootNode.has("encrypt")) {
                String encryptStr = rootNode.get("encrypt").asText();
                String encryptKey = feishuProperties.getEncryptKey();
                if (encryptKey == null || encryptKey.trim().isEmpty()) {
                    log.error("收到飞书加密请求，但服务器未配置 feishu.encrypt-key");
                    result.put("code", 500);
                    result.put("msg", "服务端未配置 Encrypt Key，无法解密");
                    return result;
                }
                String plainJson = FeishuCipherUtil.decrypt(encryptStr, encryptKey.trim());
                rootNode = objectMapper.readTree(plainJson);
            }

            // 2. 检查 URL 首次验证（type=url_verification）
            if (rootNode.has("type") && "url_verification".equals(rootNode.get("type").asText())) {
                String token = rootNode.has("token") ? rootNode.get("token").asText() : "";
                String configuredToken = feishuProperties.getVerificationToken();
                if (configuredToken != null && !configuredToken.trim().isEmpty()) {
                    if (!configuredToken.trim().equals(token)) {
                        log.warn("飞书 url_verification token 校验未通过: req={}, configured={}", token, configuredToken);
                        result.put("code", 403);
                        result.put("msg", "Verification token 校验不一致");
                        return result;
                    }
                }
                String challenge = rootNode.has("challenge") ? rootNode.get("challenge").asText() : "";
                result.put("challenge", challenge);
                return result;
            }

            // 3. 校验事件 Header Token（明文模式安全防线）
            String configuredToken = feishuProperties.getVerificationToken();
            if (configuredToken != null && !configuredToken.trim().isEmpty()) {
                String eventToken = "";
                if (rootNode.has("header") && rootNode.get("header").has("token")) {
                    eventToken = rootNode.get("header").get("token").asText();
                } else if (rootNode.has("token")) {
                    eventToken = rootNode.get("token").asText();
                }
                if (eventToken != null && !eventToken.isEmpty() && !configuredToken.trim().equals(eventToken)) {
                    log.warn("飞书事件推送 token 校验未通过: req={}, configured={}", eventToken, configuredToken);
                    result.put("code", 403);
                    result.put("msg", "Verification token 不匹配");
                    return result;
                }
            }

            // 4. 解析事件体
            String eventType = "";
            if (rootNode.has("header") && rootNode.get("header").has("event_type")) {
                eventType = rootNode.get("header").get("event_type").asText();
            } else if (rootNode.has("event") && rootNode.get("event").has("type")) {
                eventType = rootNode.get("event").get("type").asText();
            }

            if ("im.message.receive_v1".equals(eventType)) {
                JsonNode eventNode = rootNode.path("event");
                JsonNode msgNode = eventNode.path("message");
                String messageId = msgNode.path("message_id").asText();
                String chatId = msgNode.path("chat_id").asText();
                String senderOpenId = eventNode.path("sender").path("sender_id").path("open_id").asText();
                String createTime = msgNode.path("create_time").asText();
                String messageType = msgNode.path("message_type").asText();
                String contentStr = msgNode.path("content").asText();

                processMessageAsync(messageId, chatId, senderOpenId, createTime, messageType, contentStr);
            }

            // 快速返回成功，避免飞书重试风暴
            result.put("code", 0);
            return result;
        } catch (Exception e) {
            log.error("处理飞书回调异常", e);
            result.put("code", 500);
            result.put("msg", "处理飞书回调异常: " + e.getMessage());
            return result;
        }
    }

    private void processMessageAsync(String rawMessageId, String chatId, String senderOpenId,
                                     String createTime, String messageType, String contentStr) {
        if (rawMessageId == null || rawMessageId.trim().isEmpty()) {
            return;
        }
        final String messageId = rawMessageId.trim();

        // 幂等防重检查：如果该 messageId 已存在于收件箱或归档中，直接跳过
        File inboxDir = feishuProperties.getResolvedInboxDir();
        File[] existingInbox = inboxDir.listFiles((dir, name) -> name.endsWith("_" + messageId) || name.equals(messageId));
        if (existingInbox != null && existingInbox.length > 0) {
            log.info("飞书消息已存在于收件箱，跳过重复处理: messageId={}", messageId);
            return;
        }
        File archiveDir = feishuProperties.getResolvedArchiveDir();
        File[] existingArchived = archiveDir.listFiles((dir, name) -> name.endsWith("_" + messageId) || name.equals(messageId));
        if (existingArchived != null && existingArchived.length > 0) {
            log.info("飞书消息已归档，跳过重复处理: messageId={}", messageId);
            return;
        }

        // 构建子目录名称：{yyyyMMdd_HHmmss}_{message_id}
        long epoch = 0;
        try {
            epoch = Long.parseLong(createTime);
        } catch (Exception ignored) {
        }
        if (epoch <= 0) {
            epoch = System.currentTimeMillis();
        }
        LocalDateTime ldt = LocalDateTime.ofInstant(Instant.ofEpochMilli(epoch), ZoneId.of("Asia/Shanghai"));
        String timePrefix = DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss").format(ldt);
        final String inboxId = timePrefix + "_" + messageId;

        final File targetSubDir = new File(inboxDir, inboxId);
        final File mediaDir = new File(targetSubDir, "media");
        mediaDir.mkdirs();

        // 解析消息文本与媒体键
        String text = "";
        String imageKey = null;
        String fileKey = null;
        String fileName = null;

        try {
            JsonNode contentJson = objectMapper.readTree(contentStr);
            if (contentJson != null) {
                if (contentJson.has("text")) {
                    text = contentJson.get("text").asText("");
                }
                if (contentJson.has("image_key")) {
                    imageKey = contentJson.get("image_key").asText();
                }
                if (contentJson.has("file_key")) {
                    fileKey = contentJson.get("file_key").asText();
                }
                if (contentJson.has("file_name")) {
                    fileName = contentJson.get("file_name").asText();
                }
            }
        } catch (Exception e) {
            text = contentStr != null ? contentStr : "";
        }

        List<String> messageTypes = new ArrayList<>();
        if (messageType != null && !messageType.trim().isEmpty()) {
            messageTypes.add(messageType.trim().toLowerCase());
        }

        // 创建初始元数据
        final FeishuInboxMeta meta = FeishuInboxMeta.builder()
                .messageId(messageId)
                .chatId(chatId)
                .senderOpenId(senderOpenId)
                .createTime(createTime)
                .text(text)
                .messageTypes(messageTypes)
                .mediaFiles(new ArrayList<>())
                .downloaded(false)
                .build();
        saveMeta(inboxId, meta);

        boolean hasMedia = "image".equalsIgnoreCase(messageType)
                || "video".equalsIgnoreCase(messageType)
                || "media".equalsIgnoreCase(messageType)
                || "file".equalsIgnoreCase(messageType)
                || (imageKey != null && !imageKey.isEmpty())
                || (fileKey != null && !fileKey.isEmpty());

        if (!hasMedia) {
            // 纯文本消息，无需下载媒体，直接标记 downloaded=true
            meta.setDownloaded(true);
            saveMeta(inboxId, meta);
            log.info("纯文本飞书消息已落地收件箱: inboxId={}, text={}", inboxId, text);
            return;
        }

        // 异步下载素材资源
        final String finalImageKey = imageKey;
        final String finalFileKey = fileKey;
        final String finalFileName = fileName;
        final String currentMsgType = messageType != null ? messageType.toLowerCase() : "image";
        final String finalMessageId = messageId;

        downloadExecutor.submit(() -> {
            try {
                log.info("开始异步下载飞书素材: inboxId={}, messageType={}", inboxId, currentMsgType);
                List<String> downloadedFiles = downloadMediaFiles(finalMessageId, currentMsgType, finalImageKey, finalFileKey, finalFileName, mediaDir);
                meta.setMediaFiles(downloadedFiles);
                meta.setDownloaded(true);
                meta.setErrorMsg(null);
                saveMeta(inboxId, meta);
                log.info("飞书素材下载完成并就绪: inboxId={}, files={}", inboxId, downloadedFiles);
            } catch (Exception e) {
                log.error("下载飞书素材失败: inboxId=" + inboxId, e);
                meta.setDownloaded(false);
                meta.setErrorMsg(e.getMessage());
                saveMeta(inboxId, meta);
            }
        });
    }

    private List<String> downloadMediaFiles(String messageId, String messageType,
                                           String imageKey, String fileKey, String fileName,
                                           File mediaDir) throws Exception {
        List<String> list = new ArrayList<>();
        String token = getTenantAccessToken();

        String resourceKey = fileKey != null && !fileKey.isEmpty() ? fileKey : imageKey;
        String ext = ".jpg";
        String downloadType = "image";

        if ("video".equalsIgnoreCase(messageType) || "media".equalsIgnoreCase(messageType)) {
            ext = ".mp4";
            downloadType = "file";
        } else if ("file".equalsIgnoreCase(messageType)) {
            downloadType = "file";
            if (fileName != null && fileName.contains(".")) {
                ext = fileName.substring(fileName.lastIndexOf("."));
            } else {
                ext = ".bin";
            }
        }

        File targetFile = new File(mediaDir, "1" + ext);

        // 1. 尝试以指定 resourceKey 请求飞书资源
        boolean downloaded = false;
        if (resourceKey != null && !resourceKey.isEmpty()) {
            downloaded = fetchResourceToFile(messageId, resourceKey, downloadType, token, targetFile);
        }

        // 2. 若未成功，尝试不带 resourceKey 兜底请求
        if (!downloaded) {
            downloaded = fetchResourceToFile(messageId, null, downloadType, token, targetFile);
        }

        if (downloaded && targetFile.exists() && targetFile.length() > 0) {
            list.add("media/" + targetFile.getName());
        } else {
            throw new RuntimeException("未能成功下载飞书资源文件，messageId=" + messageId);
        }

        return list;
    }

    private boolean fetchResourceToFile(String messageId, String resourceKey, String type,
                                        String token, File targetFile) {
        String baseUrl = feishuProperties.getBaseUrl() != null && !feishuProperties.getBaseUrl().isEmpty()
                ? feishuProperties.getBaseUrl() : "https://open.feishu.cn";

        String url;
        if (resourceKey != null && !resourceKey.isEmpty()) {
            url = baseUrl + "/open-apis/im/v1/messages/" + messageId + "/resources/" + resourceKey + "?type=" + type;
        } else {
            url = baseUrl + "/open-apis/im/v1/messages/" + messageId + "/resources?type=" + type;
        }

        HttpGet get = new HttpGet(url);
        get.setHeader("Authorization", "Bearer " + token);

        try (CloseableHttpResponse response = httpClient.execute(get)) {
            int status = response.getStatusLine().getStatusCode();
            HttpEntity entity = response.getEntity();

            if (status == 200 && entity != null) {
                String contentType = entity.getContentType() != null ? entity.getContentType().getValue().toLowerCase() : "";
                if (contentType.contains("application/json")) {
                    String jsonStr = EntityUtils.toString(entity, StandardCharsets.UTF_8);
                    JsonNode node = objectMapper.readTree(jsonStr);
                    String tempUrl = "";
                    if (node.path("data").has("temp_download_url")) {
                        tempUrl = node.path("data").path("temp_download_url").asText();
                    } else if (node.has("temp_download_url")) {
                        tempUrl = node.path("temp_download_url").asText();
                    } else if (node.path("data").has("url")) {
                        tempUrl = node.path("data").path("url").asText();
                    }

                    if (tempUrl != null && !tempUrl.isEmpty()) {
                        return downloadDirectUrl(tempUrl, targetFile);
                    } else {
                        log.warn("飞书资源响应返回JSON但无下载地址: {}", jsonStr);
                        return false;
                    }
                } else {
                    // 二进制流直接写入文件
                    try (InputStream in = entity.getContent();
                         FileOutputStream out = new FileOutputStream(targetFile)) {
                        byte[] buf = new byte[8192];
                        int n;
                        while ((n = in.read(buf)) != -1) {
                            out.write(buf, 0, n);
                        }
                        out.flush();
                    }
                    return targetFile.exists() && targetFile.length() > 0;
                }
            } else {
                log.warn("请求飞书资源接口失败: url={}, status={}", url, status);
            }
        } catch (Exception e) {
            log.error("请求飞书资源异常: url=" + url, e);
        }
        return false;
    }

    private boolean downloadDirectUrl(String directUrl, File targetFile) {
        HttpGet get = new HttpGet(directUrl);
        try (CloseableHttpResponse response = httpClient.execute(get)) {
            if (response.getStatusLine().getStatusCode() == 200 && response.getEntity() != null) {
                try (InputStream in = response.getEntity().getContent();
                     FileOutputStream out = new FileOutputStream(targetFile)) {
                    byte[] buf = new byte[8192];
                    int n;
                    while ((n = in.read(buf)) != -1) {
                        out.write(buf, 0, n);
                    }
                    out.flush();
                }
                return targetFile.exists() && targetFile.length() > 0;
            }
        } catch (Exception e) {
            log.error("从临时链接下载飞书素材失败: " + directUrl, e);
        }
        return false;
    }

    private synchronized String getTenantAccessToken() throws Exception {
        if (cachedTenantAccessToken != null && System.currentTimeMillis() < tokenExpireTime) {
            return cachedTenantAccessToken;
        }

        String appId = feishuProperties.getAppId();
        String appSecret = feishuProperties.getAppSecret();
        if (appId == null || appId.trim().isEmpty() || appSecret == null || appSecret.trim().isEmpty()) {
            throw new IllegalStateException("飞书 app-id 或 app-secret 未配置，无法获取 tenant_access_token");
        }

        String baseUrl = feishuProperties.getBaseUrl() != null && !feishuProperties.getBaseUrl().isEmpty()
                ? feishuProperties.getBaseUrl() : "https://open.feishu.cn";
        String tokenUrl = baseUrl + "/open-apis/auth/v3/tenant_access_token/internal";

        Map<String, String> bodyMap = new HashMap<>();
        bodyMap.put("app_id", appId.trim());
        bodyMap.put("app_secret", appSecret.trim());

        HttpPost post = new HttpPost(tokenUrl);
        post.setEntity(new StringEntity(objectMapper.writeValueAsString(bodyMap), ContentType.APPLICATION_JSON));

        try (CloseableHttpResponse response = httpClient.execute(post)) {
            String json = EntityUtils.toString(response.getEntity(), StandardCharsets.UTF_8);
            JsonNode node = objectMapper.readTree(json);
            if (node.has("code") && node.get("code").asInt() == 0) {
                cachedTenantAccessToken = node.get("tenant_access_token").asText();
                long expire = node.has("expire") ? node.get("expire").asLong() : 7200L;
                tokenExpireTime = System.currentTimeMillis() + Math.max(60, expire - 300) * 1000L;
                return cachedTenantAccessToken;
            } else {
                throw new RuntimeException("获取飞书 tenant_access_token 失败: " + json);
            }
        }
    }

    @Override
    public Map<String, Object> listPendingInboxItems(String platformFilter) {
        Map<String, Object> result = new HashMap<>();
        result.put("code", 0);

        List<Map<String, Object>> items = new ArrayList<>();
        File inboxDir = feishuProperties.getResolvedInboxDir();

        if (inboxDir.exists() && inboxDir.isDirectory()) {
            File[] subDirs = inboxDir.listFiles(File::isDirectory);
            if (subDirs != null) {
                // 按目录名排序（时序先后）
                Arrays.sort(subDirs, Comparator.comparing(File::getName));

                for (File subDir : subDirs) {
                    String inboxId = subDir.getName();
                    if (inboxId.startsWith(".") || "archive".equalsIgnoreCase(inboxId) || "acked".equalsIgnoreCase(inboxId)) {
                        continue;
                    }

                    FeishuInboxMeta meta = readMeta(inboxId);
                    if (meta != null && Boolean.TRUE.equals(meta.getDownloaded())) {
                        Map<String, Object> item = new HashMap<>();
                        item.put("inbox_id", inboxId);
                        item.put("meta_url", getNormalizedPublicBaseUrl() + "/bbq/inbox/" + inboxId + "/meta.json");

                        List<String> mediaUrls = new ArrayList<>();
                        if (meta.getMediaFiles() != null) {
                            for (String mediaFile : meta.getMediaFiles()) {
                                String normalizedRel = mediaFile.replace('\\', '/');
                                mediaUrls.add(getNormalizedPublicBaseUrl() + "/bbq/inbox/" + inboxId + "/" + normalizedRel);
                            }
                        }
                        item.put("media_urls", mediaUrls);
                        item.put("downloaded", true);
                        items.add(item);
                    }
                }
            }
        }

        Map<String, Object> data = new HashMap<>();
        data.put("items", items);
        result.put("data", data);
        return result;
    }

    @Override
    public Map<String, Object> ackInboxItem(String inboxId, String status) {
        Map<String, Object> result = new HashMap<>();

        if (inboxId == null || !SAFE_ID_PATTERN.matcher(inboxId).matches()) {
            result.put("code", 400);
            result.put("msg", "非法 inbox_id 格式");
            return result;
        }

        File inboxDir = feishuProperties.getResolvedInboxDir();
        File targetDir = new File(inboxDir, inboxId);

        if (!targetDir.exists() || !targetDir.isDirectory()) {
            // 已不存在（可能已被此前请求 ack 移走），幂等返回成功
            result.put("code", 0);
            result.put("msg", "已处于归档状态");
            return result;
        }

        try {
            File archiveDir = feishuProperties.getResolvedArchiveDir();
            File destDir = new File(archiveDir, inboxId);
            if (destDir.exists()) {
                destDir = new File(archiveDir, inboxId + "_" + System.currentTimeMillis());
            }

            boolean moved = targetDir.renameTo(destDir);
            if (!moved) {
                FileUtils.moveDirectory(targetDir, destDir);
            }
            log.info("成功确认并归档收件箱素材: inboxId={}, dest={}", inboxId, destDir.getAbsolutePath());
            result.put("code", 0);
            return result;
        } catch (Exception e) {
            log.error("归档素材子目录失败: inboxId=" + inboxId, e);
            result.put("code", 500);
            result.put("msg", "归档失败: " + e.getMessage());
            return result;
        }
    }

    @Override
    public File getInboxFile(String inboxId, String relativePath) {
        if (inboxId == null || !SAFE_ID_PATTERN.matcher(inboxId).matches()) {
            return null;
        }
        if (relativePath == null || relativePath.contains("..") || relativePath.contains("\\")) {
            return null;
        }

        File inboxDir = feishuProperties.getResolvedInboxDir();
        File subDir = new File(inboxDir, inboxId);
        if (!subDir.exists()) {
            // 归档目录兜底查找，支持本地取走后偶发重试读取
            File archiveDir = feishuProperties.getResolvedArchiveDir();
            subDir = new File(archiveDir, inboxId);
        }

        if (!subDir.exists() || !subDir.isDirectory()) {
            return null;
        }

        try {
            File targetFile = new File(subDir, relativePath);
            String targetCanonical = targetFile.getCanonicalPath();
            String dirCanonical = subDir.getCanonicalPath();

            if (!targetCanonical.startsWith(dirCanonical)) {
                log.warn("防跨目录访问拦截: canonical={}, dir={}", targetCanonical, dirCanonical);
                return null;
            }

            if (targetFile.exists() && targetFile.isFile()) {
                return targetFile;
            }
        } catch (Exception e) {
            log.error("检查目标静态文件异常", e);
        }
        return null;
    }

    @Override
    public void saveMeta(String inboxId, FeishuInboxMeta meta) {
        if (inboxId == null || meta == null) {
            return;
        }
        File inboxDir = feishuProperties.getResolvedInboxDir();
        File subDir = new File(inboxDir, inboxId);
        if (!subDir.exists()) {
            subDir.mkdirs();
        }
        File metaFile = new File(subDir, "meta.json");
        try {
            objectMapper.writerWithDefaultPrettyPrinter().writeValue(metaFile, meta);
        } catch (Exception e) {
            log.error("保存收件箱 meta.json 失败: inboxId=" + inboxId, e);
        }
    }

    @Override
    public FeishuInboxMeta readMeta(String inboxId) {
        if (inboxId == null) {
            return null;
        }
        File inboxDir = feishuProperties.getResolvedInboxDir();
        File subDir = new File(inboxDir, inboxId);
        if (!subDir.exists()) {
            subDir = new File(feishuProperties.getResolvedArchiveDir(), inboxId);
        }
        File metaFile = new File(subDir, "meta.json");
        if (metaFile.exists() && metaFile.isFile()) {
            try {
                return objectMapper.readValue(metaFile, FeishuInboxMeta.class);
            } catch (Exception e) {
                log.error("读取收件箱 meta.json 失败: inboxId=" + inboxId, e);
            }
        }
        return null;
    }

    private String getNormalizedPublicBaseUrl() {
        if (publicBaseUrl == null || publicBaseUrl.trim().isEmpty()) {
            return "https://laofei.com.cn";
        }
        String base = publicBaseUrl.trim();
        if (base.endsWith("/")) {
            base = base.substring(0, base.length() - 1);
        }
        return base;
    }
}

package com.lanf.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.FeishuInboxMeta;
import com.lanf.properties.FeishuProperties;
import com.lanf.service.impl.FeishuInboxServiceImpl;
import com.lanf.util.FeishuCipherUtil;
import org.apache.commons.io.FileUtils;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Collections;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

public class FeishuInboxServiceTest {

    private FeishuInboxServiceImpl feishuInboxService;
    private FeishuProperties feishuProperties;
    private File tempInboxDir;
    private File tempArchiveDir;
    private ObjectMapper objectMapper;

    @BeforeEach
    public void setUp() throws IOException {
        tempInboxDir = Files.createTempDirectory("feishu_test_inbox_").toFile();
        tempArchiveDir = Files.createTempDirectory("feishu_test_archive_").toFile();

        feishuProperties = new FeishuProperties();
        feishuProperties.setAppId("cli_test_app_id");
        feishuProperties.setAppSecret("test_app_secret");
        feishuProperties.setVerificationToken("v_token_123");
        feishuProperties.setEncryptKey("enc_key_12345678901234567890");
        feishuProperties.setInboxDir(tempInboxDir.getAbsolutePath());
        feishuProperties.setArchiveDir(tempArchiveDir.getAbsolutePath());
        feishuProperties.setInboxToken("inbox_secret_token_888");

        objectMapper = new ObjectMapper();

        feishuInboxService = new FeishuInboxServiceImpl();
        ReflectionTestUtils.setField(feishuInboxService, "feishuProperties", feishuProperties);
        ReflectionTestUtils.setField(feishuInboxService, "objectMapper", objectMapper);
        ReflectionTestUtils.setField(feishuInboxService, "publicBaseUrl", "https://laofei.com.cn");
    }

    @AfterEach
    public void tearDown() {
        FileUtils.deleteQuietly(tempInboxDir);
        FileUtils.deleteQuietly(tempArchiveDir);
        feishuInboxService.destroy();
    }

    @Test
    public void testUrlVerification_success() {
        String body = "{\"type\":\"url_verification\",\"token\":\"v_token_123\",\"challenge\":\"test_challenge_abc\"}";
        Map<String, Object> resp = feishuInboxService.handleCallback(body, Collections.emptyMap());

        assertNotNull(resp);
        assertEquals("test_challenge_abc", resp.get("challenge"));
    }

    @Test
    public void testUrlVerification_tokenMismatch_returns403() {
        String body = "{\"type\":\"url_verification\",\"token\":\"wrong_token\",\"challenge\":\"test_challenge_abc\"}";
        Map<String, Object> resp = feishuInboxService.handleCallback(body, Collections.emptyMap());

        assertNotNull(resp);
        assertEquals(403, resp.get("code"));
    }

    @Test
    public void testPlaintextEvent_textMessage_createsInboxAndMeta() {
        String eventJson = "{\n" +
                "  \"schema\": \"2.0\",\n" +
                "  \"header\": {\n" +
                "    \"event_id\": \"ev_101\",\n" +
                "    \"event_type\": \"im.message.receive_v1\",\n" +
                "    \"token\": \"v_token_123\"\n" +
                "  },\n" +
                "  \"event\": {\n" +
                "    \"sender\": {\"sender_id\": {\"open_id\": \"ou_test_user\"}},\n" +
                "    \"message\": {\n" +
                "      \"message_id\": \"om_test_msg_001\",\n" +
                "      \"chat_id\": \"oc_test_chat\",\n" +
                "      \"create_time\": \"1720000000000\",\n" +
                "      \"message_type\": \"text\",\n" +
                "      \"content\": \"{\\\"text\\\":\\\"今天做小红书油边王种草\\\"}\"\n" +
                "    }\n" +
                "  }\n" +
                "}";

        Map<String, Object> resp = feishuInboxService.handleCallback(eventJson, Collections.emptyMap());
        assertEquals(0, resp.get("code"));

        // 验证收件箱文件与 meta.json
        File[] subDirs = tempInboxDir.listFiles(File::isDirectory);
        assertNotNull(subDirs);
        assertEquals(1, subDirs.length);
        String dirName = subDirs[0].getName();
        assertTrue(dirName.endsWith("_om_test_msg_001"));

        FeishuInboxMeta meta = feishuInboxService.readMeta(dirName);
        assertNotNull(meta);
        assertEquals("om_test_msg_001", meta.getMessageId());
        assertEquals("oc_test_chat", meta.getChatId());
        assertEquals("ou_test_user", meta.getSenderOpenId());
        assertEquals("今天做小红书油边王种草", meta.getText());
        assertTrue(meta.getDownloaded());
    }

    @Test
    public void testEncryptedEvent_decryptsAndProcesses() {
        String plainJson = "{\n" +
                "  \"type\": \"url_verification\",\n" +
                "  \"token\": \"v_token_123\",\n" +
                "  \"challenge\": \"enc_challenge_xyz\"\n" +
                "}";

        String cipher = FeishuCipherUtil.encrypt(plainJson, feishuProperties.getEncryptKey());
        String body = "{\"encrypt\":\"" + cipher + "\"}";

        Map<String, Object> resp = feishuInboxService.handleCallback(body, Collections.emptyMap());
        assertNotNull(resp);
        assertEquals("enc_challenge_xyz", resp.get("challenge"));
    }

    @Test
    public void testListPendingInboxItems_andAck() throws IOException {
        String inboxId = "20261031_100001_om_test_002";
        File dir = new File(tempInboxDir, inboxId);
        File mediaDir = new File(dir, "media");
        mediaDir.mkdirs();

        File sampleMedia = new File(mediaDir, "1.jpg");
        FileUtils.writeStringToFile(sampleMedia, "fake_jpg_content", StandardCharsets.UTF_8);

        FeishuInboxMeta meta = FeishuInboxMeta.builder()
                .messageId("om_test_002")
                .chatId("oc_002")
                .senderOpenId("ou_002")
                .createTime("1720000001000")
                .text("测试图片需求")
                .messageTypes(Collections.singletonList("image"))
                .mediaFiles(Collections.singletonList("media/1.jpg"))
                .downloaded(true)
                .build();
        feishuInboxService.saveMeta(inboxId, meta);

        // 1. 查询
        Map<String, Object> listResp = feishuInboxService.listPendingInboxItems(null);
        assertEquals(0, listResp.get("code"));
        Map<String, Object> data = (Map<String, Object>) listResp.get("data");
        List<Map<String, Object>> items = (List<Map<String, Object>>) data.get("items");
        assertEquals(1, items.size());

        Map<String, Object> item = items.get(0);
        assertEquals(inboxId, item.get("inbox_id"));
        assertEquals("https://laofei.com.cn/bbq/inbox/" + inboxId + "/meta.json", item.get("meta_url"));
        List<String> mediaUrls = (List<String>) item.get("media_urls");
        assertEquals(1, mediaUrls.size());
        assertEquals("https://laofei.com.cn/bbq/inbox/" + inboxId + "/media/1.jpg", mediaUrls.get(0));

        // 2. 读取文件
        File metaFile = feishuInboxService.getInboxFile(inboxId, "meta.json");
        assertNotNull(metaFile);
        assertTrue(metaFile.exists());

        File mediaFile = feishuInboxService.getInboxFile(inboxId, "media/1.jpg");
        assertNotNull(mediaFile);
        assertTrue(mediaFile.exists());

        // 3. 防路径穿越
        File illegal = feishuInboxService.getInboxFile(inboxId, "../meta.json");
        assertNull(illegal);

        // 4. ACK 移走归档
        Map<String, Object> ackResp = feishuInboxService.ackInboxItem(inboxId, "ok");
        assertEquals(0, ackResp.get("code"));

        // 再次查询收件箱列表应为空
        Map<String, Object> emptyListResp = feishuInboxService.listPendingInboxItems(null);
        List<Map<String, Object>> emptyItems = (List<Map<String, Object>>) ((Map<String, Object>) emptyListResp.get("data")).get("items");
        assertEquals(0, emptyItems.size());

        // 归档目录中应存在
        File archivedDir = new File(tempArchiveDir, inboxId);
        assertTrue(archivedDir.exists());
    }
}

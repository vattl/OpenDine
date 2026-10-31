package com.lanf.controller;

import com.lanf.properties.FeishuProperties;
import com.lanf.service.IFeishuInboxService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.util.AntPathMatcher;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.HandlerMapping;

import javax.servlet.http.HttpServletRequest;
import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.util.HashMap;
import java.util.Map;

/**
 * 本地主控拉取素材与确认收件箱控制器（对外暴露 /bbq/inbox）
 */
@Slf4j
@RestController
@RequestMapping({"/bbq/inbox", "/api/bbq/inbox"})
public class BbqInboxController {

    @Autowired
    private IFeishuInboxService feishuInboxService;

    @Autowired
    private FeishuProperties feishuProperties;

    /**
     * 3.2 GET /bbq/inbox（本地拉取待处理素材）
     */
    @GetMapping
    public ResponseEntity<Map<String, Object>> listInbox(
            @RequestParam(required = false) String platform,
            @RequestParam(required = false) String token,
            @RequestHeader(value = "X-Inbox-Token", required = false) String headerToken) {
        if (!validateInboxToken(headerToken, token)) {
            Map<String, Object> err = new HashMap<>();
            err.put("code", 401);
            err.put("msg", "未授权访问：X-Inbox-Token 凭证校验失败");
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(err);
        }

        Map<String, Object> resp = feishuInboxService.listPendingInboxItems(platform);
        return ResponseEntity.ok(resp);
    }

    /**
     * 3.3 POST /bbq/inbox/ack（本地确认已取走素材）
     */
    @PostMapping("/ack")
    public ResponseEntity<Map<String, Object>> ackInbox(
            @RequestBody(required = false) Map<String, Object> body,
            @RequestParam(required = false) String token,
            @RequestHeader(value = "X-Inbox-Token", required = false) String headerToken) {
        if (!validateInboxToken(headerToken, token)) {
            Map<String, Object> err = new HashMap<>();
            err.put("code", 401);
            err.put("msg", "未授权访问：X-Inbox-Token 凭证校验失败");
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(err);
        }

        if (body == null || body.isEmpty()) {
            Map<String, Object> err = new HashMap<>();
            err.put("code", 400);
            err.put("msg", "请求体不能为空");
            return ResponseEntity.badRequest().body(err);
        }

        String inboxId = body.containsKey("inbox_id") ? String.valueOf(body.get("inbox_id")) : String.valueOf(body.get("inboxId"));
        String status = body.containsKey("status") ? String.valueOf(body.get("status")) : "ok";

        Map<String, Object> resp = feishuInboxService.ackInboxItem(inboxId, status);
        if (resp != null && resp.containsKey("code") && (Integer) resp.get("code") == 400) {
            return ResponseEntity.badRequest().body(resp);
        }
        return ResponseEntity.ok(resp);
    }

    /**
     * 静态文件下载与查看：GET /bbq/inbox/{inboxId}/**
     */
    @GetMapping("/{inboxId}/**")
    public ResponseEntity<Resource> getInboxFile(
            @PathVariable String inboxId,
            @RequestParam(required = false) String token,
            @RequestHeader(value = "X-Inbox-Token", required = false) String headerToken,
            HttpServletRequest request) {
        if (!validateInboxToken(headerToken, token)) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        String pattern = (String) request.getAttribute(HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE);
        String fullPath = (String) request.getAttribute(HandlerMapping.PATH_WITHIN_HANDLER_MAPPING_ATTRIBUTE);
        String subPath = new AntPathMatcher().extractPathWithinPattern(pattern, fullPath);

        File file = feishuInboxService.getInboxFile(inboxId, subPath);
        if (file == null || !file.exists() || !file.isFile()) {
            return ResponseEntity.notFound().build();
        }

        MediaType mediaType = MediaType.APPLICATION_OCTET_STREAM;
        try {
            String probeContentType = Files.probeContentType(file.toPath());
            if (probeContentType != null) {
                mediaType = MediaType.parseMediaType(probeContentType);
            } else if (file.getName().endsWith(".json")) {
                mediaType = MediaType.APPLICATION_JSON;
            }
        } catch (IOException ignored) {
        }

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(mediaType);
        headers.setContentLength(file.length());
        headers.set(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + file.getName() + "\"");

        return new ResponseEntity<>(new FileSystemResource(file), headers, HttpStatus.OK);
    }

    private boolean validateInboxToken(String headerToken, String queryToken) {
        String configured = feishuProperties.getInboxToken();
        if (configured == null || configured.trim().isEmpty()) {
            // 未配置 token 时默认允许访问（内网或受限网络环境）
            return true;
        }
        configured = configured.trim();
        if (headerToken != null && configured.equals(headerToken.trim())) {
            return true;
        }
        return queryToken != null && configured.equals(queryToken.trim());
    }
}

package com.lanf.controller;

import com.lanf.service.IFeishuInboxService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

/**
 * 飞书事件订阅回调控制器（对外暴露 /feishu/callback 与 /api/feishu/callback 别名）
 */
@Slf4j
@RestController
@RequestMapping({"/feishu", "/api/feishu"})
public class FeishuCallbackController {

    @Autowired
    private IFeishuInboxService feishuInboxService;

    /**
     * 接收飞书事件订阅推送与 URL 验证（POST 方式）
     */
    @PostMapping(value = "/callback", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> handleCallback(
            @RequestBody(required = false) String requestBody,
            @RequestHeader Map<String, String> headers) {
        log.info("收到飞书订阅回调请求");
        Map<String, Object> resp = feishuInboxService.handleCallback(requestBody, headers);
        if (resp != null && resp.containsKey("code")) {
            int code = (Integer) resp.get("code");
            if (code == 400) {
                return ResponseEntity.badRequest().contentType(MediaType.APPLICATION_JSON).body(resp);
            } else if (code == 403) {
                return ResponseEntity.status(403).contentType(MediaType.APPLICATION_JSON).body(resp);
            }
        }
        return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(resp);
    }

    /**
     * 针对探针或 GET 请求的兜底返回（确保任何探测均返回合法的 application/json）
     */
    @GetMapping(value = "/callback", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> pingCallback(
            @RequestParam(required = false) String challenge,
            @RequestParam(required = false) String token) {
        Map<String, Object> resp = new HashMap<>();
        if (challenge != null && !challenge.trim().isEmpty()) {
            resp.put("challenge", challenge.trim());
            return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(resp);
        }
        resp.put("code", 0);
        resp.put("msg", "feishu callback endpoint is active");
        return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(resp);
    }
}

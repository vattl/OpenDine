package com.lanf.controller;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.*;
import com.lanf.printing.entity.PrintingDevice;
import com.lanf.printing.mapper.PrintingDeviceMapper;
import com.lanf.service.IFeieyunService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.util.HashMap;
import java.util.Map;

/**
 * 飞鹅云打印接口。
 *
 * <p>自 v1.2.223 起，所有飞鹅云凭据（url/user/ukey）统一从 {@code t_printing_device}
 * （请求参数 {@code deviceId} 指定）的 {@code connection_json} 获取，不再支持门店配置
 * （t_shop_printer_config）与全局配置（feieyun.*）兜底。</p>
 */
@RestController
@RequestMapping("/api/feieyun")
public class FeieyunController {

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    private final IFeieyunService feieyunService;
    private final PrintingDeviceMapper printingDeviceMapper;

    public FeieyunController(IFeieyunService feieyunService, PrintingDeviceMapper printingDeviceMapper) {
        this.feieyunService = feieyunService;
        this.printingDeviceMapper = printingDeviceMapper;
    }

    /**
     * 打印订单
     */
    @PostMapping("/print")
    public ResponseEntity<Map<String, Object>> printOrder(@RequestBody PrintRequest request) {
        Map<String, Object> result = new HashMap<>();
        try {
            if (request.getContent() == null || request.getContent().equals("")) {
                result.put("success", false);
                result.put("message", "打印失败:内容不能为空 ");
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(result);
            }
            CloudCredential cred = resolveCredential(request.getDeviceId());
            String sn = StringUtils.hasText(request.getPrinterSn()) ? request.getPrinterSn().trim() : cred.sn;
            String response = feieyunService.printWithCredential(
                    cred.apiUrl, cred.user, cred.ukey, sn, request.getContent(), request.getTimes());
            result.put("success", true);
            result.put("data", response);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            // 记录完整的异常堆栈信息
            e.printStackTrace();
            result.put("success", false);
            // 返回更详细的错误信息
            result.put("message", "打印失败: " + e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(result);
        }
    }

    /**
     * 打印标签
     */
    @PostMapping("/print-label")
    public ResponseEntity<Map<String, Object>> printLabel(@RequestBody PrintRequest request) {
        Map<String, Object> result = new HashMap<>();

        try {
            CloudCredential cred = resolveCredential(request.getDeviceId());
            String sn = StringUtils.hasText(request.getPrinterSn()) ? request.getPrinterSn().trim() : cred.sn;
            String response = feieyunService.printLabelMsgWithCredential(
                    cred.apiUrl, cred.user, cred.ukey, sn, request.getContent(), request.getTimes());
            result.put("success", true);
            result.put("data", response);
            return ResponseEntity.ok(result);
        } catch (IOException e) {
            result.put("success", false);
            result.put("message", "标签打印失败: " + e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(result);
        }
    }

    /**
     * 查询订单状态
     */
    @GetMapping("/order-status")
    public ResponseEntity<Map<String, Object>> queryOrderStatus(@RequestParam Long deviceId,
                                                                @RequestParam String orderId) {
        Map<String, Object> result = new HashMap<>();

        try {
            CloudCredential cred = resolveCredential(deviceId);
            String response = feieyunService.queryOrderStateWithCredential(
                    cred.apiUrl, cred.user, cred.ukey, orderId);
            result.put("success", true);
            result.put("data", response);
            return ResponseEntity.ok(result);
        } catch (IOException e) {
            result.put("success", false);
            result.put("message", "查询失败: " + e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(result);
        }
    }

    /**
     * 查询打印机状态
     */
    @GetMapping("/printer-status")
    public ResponseEntity<Map<String, Object>> queryPrinterStatus(@RequestParam Long deviceId,
                                                                  @RequestParam(required = false) String printerSn) {
        Map<String, Object> result = new HashMap<>();

        try {
            CloudCredential cred = resolveCredential(deviceId);
            String sn = StringUtils.hasText(printerSn) ? printerSn.trim() : cred.sn;
            String response = feieyunService.queryPrinterStatusWithCredential(
                    cred.apiUrl, cred.user, cred.ukey, sn);
            result.put("success", true);
            result.put("data", response);
            return ResponseEntity.ok(result);
        } catch (IOException e) {
            result.put("success", false);
            result.put("message", "查询失败: " + e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(result);
        }
    }

    /**
     * 添加打印机（使用指定设备同账号的飞鹅凭据）
     */
    @PostMapping("/add-printer")
    public ResponseEntity<Map<String, Object>> addPrinter(@RequestBody PrintRequest request) {
        Map<String, Object> result = new HashMap<>();

        try {
            CloudCredential cred = resolveCredential(request.getDeviceId());
            String printerContent = String.format("%s,%s,%s",
                    request.getPrinterSn(),
                    request.getKey(),
                    request.getName()
            );
            String response = feieyunService.addPrinterWithCredential(
                    cred.apiUrl, cred.user, cred.ukey, printerContent);
            result.put("success", true);
            result.put("data", response);
            return ResponseEntity.ok(result);
        } catch (IOException e) {
            result.put("success", false);
            result.put("message", "添加打印机失败: " + e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(result);
        }
    }

    /**
     * 按设备 ID 从 t_printing_device.connection_json 解析飞鹅云凭据。
     */
    private CloudCredential resolveCredential(Long deviceId) {
        if (deviceId == null) {
            throw new IllegalArgumentException("缺少 deviceId：飞鹅凭据统一从 t_printing_device 获取");
        }
        PrintingDevice device = printingDeviceMapper.selectById(deviceId);
        if (device == null) {
            throw new IllegalArgumentException("打印设备不存在: deviceId=" + deviceId);
        }
        Map<String, Object> conn;
        try {
            conn = OBJECT_MAPPER.readValue(device.getConnection_json(),
                    new TypeReference<Map<String, Object>>() {});
        } catch (Exception e) {
            throw new IllegalArgumentException("打印设备 connection 配置解析失败: deviceId=" + deviceId);
        }
        String apiUrl = conn.get("url") != null ? String.valueOf(conn.get("url")).trim()
                : (conn.get("apiUrl") != null ? String.valueOf(conn.get("apiUrl")).trim() : null);
        String user = conn.get("user") != null ? String.valueOf(conn.get("user")).trim() : null;
        String ukey = conn.get("ukey") != null ? String.valueOf(conn.get("ukey")).trim() : null;
        String sn = conn.get("sn") != null ? String.valueOf(conn.get("sn")).trim() : null;
        if (!StringUtils.hasText(apiUrl)) {
            throw new IllegalArgumentException("打印设备未配置飞鹅云接口地址(connection.url/apiUrl): deviceId=" + deviceId);
        }
        if (!StringUtils.hasText(user) || !StringUtils.hasText(ukey)) {
            throw new IllegalArgumentException("打印设备未配置飞鹅云凭据(connection.user/ukey): deviceId=" + deviceId);
        }
        return new CloudCredential(apiUrl, user, ukey, sn);
    }

    private static final class CloudCredential {
        final String apiUrl;
        final String user;
        final String ukey;
        final String sn;

        private CloudCredential(String apiUrl, String user, String ukey, String sn) {
            this.apiUrl = apiUrl;
            this.user = user;
            this.ukey = ukey;
            this.sn = sn;
        }
    }
}

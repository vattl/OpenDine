package com.lanf.controller.admin;

import com.lanf.audit.annotation.AuditLog;
import com.lanf.entity.R;
import com.lanf.kds.service.KdsAuthorityConfigSnapshotService;
import com.lanf.util.AdminShopRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import java.util.Map;

import javax.servlet.http.HttpServletRequest;

@RestController
@RequestMapping("/admin/kds/authority")
public class AdminKdsAuthorityController {
    private final KdsAuthorityConfigSnapshotService service;

    public AdminKdsAuthorityController(KdsAuthorityConfigSnapshotService service) {
        this.service = service;
    }

    @GetMapping("/config-snapshot")
    public ResponseEntity<R> snapshot(HttpServletRequest request) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null || shopId <= 0) {
            return ResponseEntity.badRequest().body(R.error(4000, "X-Shop-Id is required"));
        }
        return ResponseEntity.ok(R.ok().put("data", service.snapshot(shopId)));
    }

    @PostMapping("/device")
    @AuditLog(module = "kds", action = "admin_kds_authority_device")
    public ResponseEntity<R> setAuthorityDevice(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null || shopId <= 0) return ResponseEntity.badRequest().body(R.error(4000, "X-Shop-Id is required"));
        try {
            Object code = body != null ? body.get("cashier_device_code") : null;
            service.setAuthorityDevice(shopId, code != null ? String.valueOf(code) : null);
            return ResponseEntity.ok(R.ok().put("data", service.snapshot(shopId)));
        } catch (IllegalArgumentException ex) {
            return ResponseEntity.badRequest().body(R.error(4000, ex.getMessage()));
        }
    }
}

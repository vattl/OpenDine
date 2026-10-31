package com.lanf.controller.admin;

import com.lanf.entity.R;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.service.KdsCommandResultService;
import com.lanf.kds.service.KdsV2RejectedCommandException;
import com.lanf.kds.service.KdsWorkflowV2Service;
import com.lanf.util.AdminShopRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.Map;

/**
 * Unified command entrypoint for POS Admin, executing KDS V2 compatible commands.
 */
@RestController
@RequestMapping("/admin/order")
public class AdminPosCommandController {

    private static final Logger log = LoggerFactory.getLogger(AdminPosCommandController.class);

    @Autowired
    private KdsWorkflowV2Service kdsWorkflowV2Service;

    @Autowired
    private KdsCommandResultService commandResultService;

    @PostMapping("/commands")
    public R posCommands(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null) {
            return R.error(401, "未找到门店上下文");
        }

        KdsDevice mockDevice = new KdsDevice();
        mockDevice.setShop_id(shopId);
        mockDevice.setDevice_code("pos-admin");
        
        try {
            Map<String, Object> data = kdsWorkflowV2Service.executeCommand(mockDevice, body);
            return R.ok(data);
        } catch (KdsV2RejectedCommandException e) {
            return R.error(e.getBusinessCode(), e.getMessage()).put("command", e.getResult());
        } catch (com.lanf.kds.service.KdsWorkflowService.OptimisticLockException e) {
            persistStableRejection(mockDevice, body, 409, 4090, e.getMessage());
            return R.error(4090, e.getMessage());
        } catch (IllegalArgumentException e) {
            persistStableRejection(mockDevice, body, 400, 4000, e.getMessage());
            return R.error(4000, e.getMessage());
        } catch (Exception e) {
            log.error("[admin/order/commands] failed", e);
            return R.error(e.getMessage() != null ? e.getMessage() : "command 执行失败");
        }
    }

    private void persistStableRejection(KdsDevice device, Map<String, Object> body,
                                        int httpStatus, int businessCode, String message) {
        if (commandResultService == null || device == null || body == null) return;
        Object rawCommandId = body.get("command_id");
        Object rawType = body.get("type");
        if (rawCommandId == null || rawCommandId.toString().trim().isEmpty()
                || rawType == null || rawType.toString().trim().isEmpty()) return;
        String actorId = device.getDevice_code();
        try {
            commandResultService.saveResultInNewTransaction(
                    device.getShop_id(), rawCommandId.toString().trim(), actorId,
                    "POS", rawType.toString(), "2.0", body,
                    httpStatus, businessCode, message);
        } catch (Exception persistenceFailure) {
            log.error("[admin/order/commands] failed to persist stable rejection command_id={}", rawCommandId, persistenceFailure);
        }
    }
}

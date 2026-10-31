package com.lanf.controller.admin;

import com.lanf.audit.annotation.AuditLog;
import com.lanf.entity.R;
import com.lanf.entity.SubscribeSceneTemplate;
import com.lanf.entity.SubscribeSendLog;
import com.lanf.service.IWechatSubscribeQuotaService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * 管理后台：微信订阅消息场景模板与发送审计
 */
@RestController
@RequestMapping("/admin/subscribe")
public class AdminSubscribeConfigController {

    @Autowired
    private IWechatSubscribeQuotaService subscribeQuotaService;

    /**
     * 查询微信订阅消息全部场景与模板配置
     */
    @GetMapping("/scenes")
    public R listScenes() {
        List<SubscribeSceneTemplate> list = subscribeQuotaService.listSceneTemplates();
        return R.ok().put("data", list);
    }

    /**
     * 新增微信订阅消息场景模板配置
     */
    @PostMapping("/scenes")
    @AuditLog(module = "subscribe", action = "create_scene_template", target = "#p0.scene_code")
    public R createScene(@RequestBody SubscribeSceneTemplate template) {
        if (template == null || template.getScene_code() == null || template.getScene_code().trim().isEmpty()) {
            return R.error("场景编码(scene_code)不能为空");
        }
        boolean ok = subscribeQuotaService.saveOrUpdateSceneTemplate(template);
        return ok ? R.ok("场景模板创建成功") : R.error("创建失败");
    }

    /**
     * 更新指定场景的微信模板配置
     */
    @PutMapping("/scenes/{sceneCode}")
    @AuditLog(module = "subscribe", action = "update_scene_template", target = "#p0")
    public R updateScene(@PathVariable("sceneCode") String sceneCode,
                         @RequestBody SubscribeSceneTemplate template) {
        if (template != null) {
            template.setScene_code(sceneCode);
        }
        boolean ok = subscribeQuotaService.saveOrUpdateSceneTemplate(template);
        return ok ? R.ok("场景模板配置保存成功") : R.error("保存失败");
    }

    /**
     * 删除指定场景的微信模板配置
     */
    @DeleteMapping("/scenes/{sceneCode}")
    @AuditLog(module = "subscribe", action = "delete_scene_template", target = "#p0")
    public R deleteScene(@PathVariable("sceneCode") String sceneCode) {
        boolean ok = subscribeQuotaService.deleteSceneTemplate(sceneCode);
        return ok ? R.ok("场景模板删除成功") : R.error("删除失败或场景不存在");
    }

    /**
     * 查询订阅消息发送审计日志
     */
    @GetMapping("/logs")
    public R listLogs(@RequestParam(value = "bizNo", required = false) String bizNo,
                      @RequestParam(value = "openid", required = false) String openid,
                      @RequestParam(value = "scene", required = false) String scene,
                      @RequestParam(value = "status", required = false) String status,
                      @RequestParam(value = "limit", defaultValue = "50") int limit) {
        List<SubscribeSendLog> logs = subscribeQuotaService.listSendLogs(bizNo, openid, scene, status, limit);
        return R.ok().put("data", logs);
    }
}

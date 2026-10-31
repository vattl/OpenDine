package com.lanf.controller;

import com.lanf.entity.R;
import com.lanf.service.IWechatSubscribeQuotaService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * C端微信订阅消息控制接口（智能决策与授权上报）
 */
@RestController
@RequestMapping("/api/v1/subscribe")
public class WechatSubscribeController {

    @Autowired
    private IWechatSubscribeQuotaService subscribeQuotaService;

    /**
     * 智能决策：查询当前用户在指定业务场景下是否需要唤起微信订阅弹窗
     * @param openid 微信用户OpenID
     * @param scene 场景编码（如 ORDER_PICKUP, ORDER_STATUS, COUPON_EXPIRING 等）
     */
    @GetMapping("/prompt-decision")
    public R getPromptDecision(@RequestParam("openid") String openid,
                               @RequestParam(value = "scene", required = false) String scene) {
        Map<String, Object> decision = subscribeQuotaService.getPromptDecision(openid, scene);
        return R.ok().put("data", decision);
    }

    /**
     * 授权回传：小程序前端完成 wx.requestSubscribeMessage 后上报用户勾选结果
     */
    @PostMapping("/report")
    public R reportAuthResult(@RequestBody Map<String, Object> body) {
        String openid = (String) body.get("openid");
        String scene = (String) body.get("scene");
        if (scene == null) {
            scene = (String) body.get("scene_code");
        }
        @SuppressWarnings("unchecked")
        Map<String, String> results = (Map<String, String>) body.get("auth_results");
        if (results == null) {
            @SuppressWarnings("unchecked")
            Map<String, String> alt = (Map<String, String>) body.get("results");
            results = alt;
        }

        Map<String, Object> res = subscribeQuotaService.reportAuthResult(openid, scene, results);
        return R.ok().put("data", res);
    }

    /**
     * 查询用户各场景的剩余订阅配额与台账
     */
    @GetMapping("/quota")
    public R getUserQuota(@RequestParam("openid") String openid) {
        Map<String, Object> summary = subscribeQuotaService.getUserQuotaSummary(openid);
        return R.ok().put("data", summary);
    }
}

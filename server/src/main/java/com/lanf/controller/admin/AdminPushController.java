package com.lanf.controller.admin;

import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.AdminPushDeviceService;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

@RestController
@RequestMapping("/admin/push")
public class AdminPushController {

    private static final Set<String> PLATFORMS = new HashSet<>(Arrays.asList("ios", "android"));
    private static final Set<String> CHANNELS = new HashSet<>(Arrays.asList(
            "apns", "fcm", "huawei", "xiaomi", "oppo", "vivo"));

    @Autowired
    private AdminPushDeviceService pushDeviceService;
    @Autowired
    private HttpServletRequest request;

    @PostMapping("/device/register")
    public R register(@RequestBody Map<String, Object> body) {
        Integer adminId = adminId();
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        String token = text(body != null ? body.get("deviceToken") : null);
        String platform = lower(body != null ? body.get("platform") : null);
        String channel = lower(body != null ? body.get("channel") : null);
        if (adminId == null || shopId == null) return R.error(4001, "缺少登录或门店上下文");
        if (token == null || token.length() > 512) return R.error(400, "deviceToken 不能为空且不能超过 512 个字符");
        if (!PLATFORMS.contains(platform)) return R.error(400, "platform 仅支持 ios 或 android");
        if (!CHANNELS.contains(channel)) return R.error(400, "不支持的推送 channel");
        if (("ios".equals(platform) && !"apns".equals(channel))
                || ("android".equals(platform) && "apns".equals(channel))) {
            return R.error(400, "platform 与 channel 不匹配");
        }
        pushDeviceService.register(adminId, shopId, token, platform, channel,
                limited(body.get("appVersion"), 32), limited(body.get("deviceModel"), 128));
        return R.ok("注册成功");
    }

    @PostMapping("/device/unregister")
    public R unregister(@RequestBody Map<String, Object> body) {
        Integer adminId = adminId();
        String token = text(body != null ? body.get("deviceToken") : null);
        if (adminId == null) return R.error(401, "未登录或登录已过期");
        if (token == null || token.length() > 512) return R.error(400, "deviceToken 不能为空且不能超过 512 个字符");
        pushDeviceService.unregister(adminId, token);
        return R.ok("解绑成功");
    }

    @PostMapping("/preference")
    public R preference(@RequestBody Map<String, Object> body) {
        Integer adminId = adminId();
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        Object raw = body != null ? body.get("types") : null;
        if (adminId == null || shopId == null) return R.error(4001, "缺少登录或门店上下文");
        if (!(raw instanceof List)) return R.error(400, "types 必须是字符串数组");
        List<String> types = new ArrayList<>();
        for (Object item : (List<?>) raw) {
            String type = lower(item);
            if (type == null || !type.matches("[a-z][a-z0-9_]{0,63}")) {
                return R.error(400, "通知类型格式不合法");
            }
            if (!types.contains(type)) types.add(type);
        }
        if (types.size() > 32) return R.error(400, "通知类型不能超过 32 项");
        pushDeviceService.savePreference(adminId, shopId, types);
        return R.ok("保存成功").put("types", types);
    }

    private Integer adminId() {
        Object value = request.getAttribute(SysInterceptor.ATTR_ADMIN_ID);
        return value instanceof Integer ? (Integer) value : null;
    }

    private static String limited(Object value, int maxLength) {
        String text = text(value);
        return text == null || text.length() <= maxLength ? text : text.substring(0, maxLength);
    }

    private static String lower(Object value) {
        String text = text(value);
        return text == null ? null : text.toLowerCase(Locale.ROOT);
    }

    private static String text(Object value) {
        if (value == null) return null;
        String text = value.toString().trim();
        return text.isEmpty() ? null : text;
    }
}

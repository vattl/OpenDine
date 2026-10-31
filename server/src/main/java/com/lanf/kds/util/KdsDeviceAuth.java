package com.lanf.kds.util;

import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.interceptor.KdsDeviceAuthInterceptor;
import com.lanf.kds.service.KdsDeviceService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import javax.servlet.http.HttpServletRequest;

@Component
public class KdsDeviceAuth {

    public static final String HEADER_DEVICE_TOKEN = "X-Kds-Device-Token";

    @Autowired
    private KdsDeviceService deviceService;

    public KdsDevice requireDevice(HttpServletRequest request) {
        Object attr = request.getAttribute(KdsDeviceAuthInterceptor.ATTR_KDS_DEVICE);
        if (attr instanceof KdsDevice) {
            return (KdsDevice) attr;
        }
        String token = request.getHeader(HEADER_DEVICE_TOKEN);
        if (token == null || token.trim().isEmpty()) {
            if (request.getParameter("device_token") != null) {
                throw new IllegalStateException("已废弃 URL 查询参数传递令牌，请在请求头携带 X-Kds-Device-Token");
            }
            throw new IllegalStateException("缺少厨显设备令牌 X-Kds-Device-Token");
        }
        KdsDevice device = deviceService.findByToken(token.trim());
        if (device == null) {
            throw new IllegalStateException("设备未绑定或已禁用");
        }
        return device;
    }
}

package com.lanf.kds.controller;

import com.lanf.entity.R;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.interceptor.KdsDeviceAuthInterceptor;
import com.lanf.kds.service.KdsStatsService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;

@RestController
@RequestMapping("/kds/stats")
public class KdsStatsController {

    @Autowired
    private KdsStatsService statsService;
    @Autowired
    private HttpServletRequest request;

    @GetMapping("/today")
    public R today() {
        KdsDevice device = (KdsDevice) request.getAttribute(KdsDeviceAuthInterceptor.ATTR_KDS_DEVICE);
        if (device == null) {
            return R.error(401, "未认证");
        }
        return R.ok().put("stats", statsService.todayStats(device.getShop_id()));
    }
}
